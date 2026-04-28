"""
test_webcam_landmarks.py

Requirements:
  pip install torch torchvision opencv-python numpy scipy

Notes:
- Set NUM_LANDMARKS to match training (478 or 468).
- Put your trained weights next to this file:
    best_landmark_model.pth
- This model expects the same preprocessing as training:
    Haar face box -> expanded square crop -> resize 224x224 -> predict (x,y in crop-normalized coords)
"""

from __future__ import annotations

import time
import threading
from dataclasses import dataclass
from typing import Optional, Tuple

import cv2
import numpy as np
import torch
import torch.nn as nn

try:
    import winsound
    HAS_BEEP = True
except Exception:
    HAS_BEEP = False

try:
    from scipy.spatial import Delaunay
    _HAS_SCIPY = True
except Exception:
    Delaunay = None  # type: ignore
    _HAS_SCIPY = False


# =========================
# Configuration
# =========================
MODEL_PATH = "C:/Users/dell/Downloads/Drowsiness_Detector/drowsiness_model.pth"

NUM_LANDMARKS = 478  # MUST match training
IMAGE_SIZE = 224     # MUST match training
CROP_EXPAND_RATIO = 1.6

# Adaptive EAR config (replaces fixed EAR_THRESHOLD logic)
EAR_CLOSE_REL_DROP = 0.07         # closed if EAR drops >= 7% below personal baseline
EAR_REOPEN_REL_DROP = 0.04        # reopen hysteresis (lower than close drop)
EAR_CLOSE_MIN_DROP = 0.008        # minimum absolute EAR drop
EAR_BASELINE_ALPHA = 0.03         # EMA speed for open-eye baseline adaptation
EAR_BASELINE_UPDATE_MAX_DROP = 0.05
EAR_VALID_MIN = 0.08
EAR_VALID_MAX = 0.60
EYE_CLOSED_CONFIRM_SEC = 0.45     # blink rejection for more sensitive close threshold

# Adaptive MAR / yawn config
MAR_BASELINE_ALPHA = 0.03
MAR_VALID_MIN = 0.10
MAR_VALID_MAX = 1.20
MAR_DROWSY_REL_INCREASE = EAR_CLOSE_REL_DROP   # proportional to EAR drowsy severity
MAR_DROWSY_MIN_ABS_INC = 0.02
MAR_REOPEN_REL_INCREASE = 0.04                 # hysteresis for stable yawn state
MAR_LONG_YAWN_SEC = 1.0
MAR_EVENT_MIN_SEC = 0.35
MAR_CONSECUTIVE_EVENTS_FOR_DROWSY = 2
MAR_CONSECUTIVE_GAP_SEC = 6.0

LANDMARK_SMOOTH_ALPHA = 0.55
FACE_BOX_SMOOTH_ALPHA = 0.40
MAX_LOST_FRAMES = 10

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

LANDMARK_DIM = NUM_LANDMARKS * 3

LAST_BEEP_TIME = 0
BEEP_INTERVAL = 1.0
TERMINAL_LOG_INTERVAL_SEC = 0.25


# =========================
# Beep Function
# =========================
def play_beep(freq=1200, duration=400):
    global LAST_BEEP_TIME

    now = time.time()

    if now - LAST_BEEP_TIME < BEEP_INTERVAL:
        return

    LAST_BEEP_TIME = now

    if HAS_BEEP:
        threading.Thread(
            target=lambda: winsound.Beep(freq, duration),
            daemon=True
        ).start()


# =========================
# Model Architecture (must match training)
# =========================
class SEBlock(nn.Module):
    def __init__(self, channels: int, reduction: int = 16):
        super().__init__()
        self.pool = nn.AdaptiveAvgPool2d(1)
        self.fc = nn.Sequential(
            nn.Linear(channels, channels // reduction, bias=False),
            nn.ReLU(inplace=True),
            nn.Linear(channels // reduction, channels, bias=False),
            nn.Sigmoid(),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        b, c, _, _ = x.shape
        w = self.pool(x).view(b, c)
        w = self.fc(w).view(b, c, 1, 1)
        return x * w


class ResidualBlock(nn.Module):
    def __init__(self, in_ch: int, out_ch: int, stride: int = 1):
        super().__init__()
        self.conv1 = nn.Conv2d(in_ch, out_ch, 3, stride=stride, padding=1, bias=False)
        self.bn1 = nn.BatchNorm2d(out_ch)
        self.conv2 = nn.Conv2d(out_ch, out_ch, 3, padding=1, bias=False)
        self.bn2 = nn.BatchNorm2d(out_ch)
        self.se = SEBlock(out_ch)
        self.relu = nn.ReLU(inplace=True)

        self.shortcut = nn.Sequential()
        if stride != 1 or in_ch != out_ch:
            self.shortcut = nn.Sequential(
                nn.Conv2d(in_ch, out_ch, 1, stride=stride, bias=False),
                nn.BatchNorm2d(out_ch),
            )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        out = self.relu(self.bn1(self.conv1(x)))
        out = self.bn2(self.conv2(out))
        out = self.se(out)
        out = out + self.shortcut(x)
        return self.relu(out)


class CoordAttention(nn.Module):
    def __init__(self, channels: int, reduction: int = 16):
        super().__init__()
        mid = max(8, channels // reduction)
        self.pool_h = nn.AdaptiveAvgPool2d((None, 1))
        self.pool_w = nn.AdaptiveAvgPool2d((1, None))
        self.conv_reduce = nn.Conv2d(channels, mid, 1, bias=False)
        self.bn = nn.BatchNorm2d(mid)
        self.relu = nn.ReLU(inplace=True)
        self.conv_h = nn.Conv2d(mid, channels, 1, bias=False)
        self.conv_w = nn.Conv2d(mid, channels, 1, bias=False)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        b, c, h, w = x.shape
        x_h = self.pool_h(x)
        x_w = self.pool_w(x).permute(0, 1, 3, 2)

        cat = torch.cat([x_h, x_w], dim=2)
        cat = self.relu(self.bn(self.conv_reduce(cat)))

        split_h, split_w = cat.split([h, w], dim=2)
        att_h = torch.sigmoid(self.conv_h(split_h))
        att_w = torch.sigmoid(self.conv_w(split_w.permute(0, 1, 3, 2)))

        return x * att_h * att_w


class LandmarkCNN(nn.Module):
    def __init__(self):
        super().__init__()

        self.stem = nn.Sequential(
            nn.Conv2d(3, 64, 7, stride=2, padding=3, bias=False),
            nn.BatchNorm2d(64),
            nn.ReLU(inplace=True),
            nn.MaxPool2d(3, stride=2, padding=1),
        )

        self.layer1 = nn.Sequential(ResidualBlock(64, 64), ResidualBlock(64, 64))
        self.layer2 = nn.Sequential(ResidualBlock(64, 128, stride=2), ResidualBlock(128, 128))
        self.layer3 = nn.Sequential(ResidualBlock(128, 256, stride=2), ResidualBlock(256, 256))
        self.layer4 = nn.Sequential(ResidualBlock(256, 512, stride=2), ResidualBlock(512, 512))

        self.coord_att = CoordAttention(512)
        self.global_pool = nn.AdaptiveAvgPool2d(1)

        self.regressor = nn.Sequential(
            nn.Flatten(),
            nn.Linear(512, 1024),
            nn.ReLU(inplace=True),
            nn.Dropout(0.3),
            nn.Linear(1024, 1024),
            nn.ReLU(inplace=True),
            nn.Dropout(0.2),
            nn.Linear(1024, LANDMARK_DIM),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = self.stem(x)
        x = self.layer1(x)
        x = self.layer2(x)
        x = self.layer3(x)
        x = self.layer4(x)
        x = self.coord_att(x)
        x = self.global_pool(x)
        return self.regressor(x)


# =========================
# Geometry / preprocessing
# =========================
def preprocess_face(face_bgr: np.ndarray) -> torch.Tensor:
    face_rgb = cv2.cvtColor(face_bgr, cv2.COLOR_BGR2RGB)
    face_resized = cv2.resize(face_rgb, (IMAGE_SIZE, IMAGE_SIZE), interpolation=cv2.INTER_AREA)
    tensor = torch.from_numpy(face_resized).float().permute(2, 0, 1) / 255.0
    return tensor.unsqueeze(0)


def denormalize_xy_to_frame(pred_landmarks: np.ndarray, face_box: Tuple[int, int, int, int]) -> np.ndarray:
    x, y, w, h = face_box
    pts = pred_landmarks.copy()
    pts[:, 0] = pts[:, 0] * float(w) + float(x)
    pts[:, 1] = pts[:, 1] * float(h) + float(y)
    return pts


def expand_face_box(
    x: int, y: int, w: int, h: int,
    frame_w: int, frame_h: int, expand_ratio: float,
) -> Tuple[int, int, int, int]:
    cx = x + w / 2.0
    cy = y + h / 2.0
    side = max(float(w), float(h)) * float(expand_ratio)
    half = side / 2.0

    x1 = max(0, int(round(cx - half)))
    y1 = max(0, int(round(cy - half)))
    x2 = min(frame_w, int(round(cx + half)))
    y2 = min(frame_h, int(round(cy + half)))
    return x1, y1, max(1, x2 - x1), max(1, y2 - y1)


def euclidean(p1: np.ndarray, p2: np.ndarray) -> float:
    return float(np.linalg.norm(p1 - p2))


def compute_ear(landmarks_xy: np.ndarray) -> float:
    if landmarks_xy.shape[0] <= 387:
        return 0.0

    left_idx = [33, 160, 158, 133, 153, 144]
    right_idx = [362, 385, 387, 263, 373, 380]

    def eye_ear(idxs):
        p1, p2, p3, p4, p5, p6 = [landmarks_xy[i] for i in idxs]
        denom = 2.0 * euclidean(p1, p4)
        if denom < 1e-6:
            return 0.0
        return (euclidean(p2, p6) + euclidean(p3, p5)) / denom

    return (eye_ear(left_idx) + eye_ear(right_idx)) / 2.0


def compute_mar(landmarks_xy: np.ndarray) -> float:
    if landmarks_xy.shape[0] <= 317:
        return 0.0

    left_corner = landmarks_xy[78]
    right_corner = landmarks_xy[308]
    upper_mid = landmarks_xy[13]
    lower_mid = landmarks_xy[14]
    upper_left = landmarks_xy[82]
    lower_left = landmarks_xy[87]
    upper_right = landmarks_xy[312]
    lower_right = landmarks_xy[317]

    horizontal = euclidean(left_corner, right_corner)
    if horizontal < 1e-6:
        return 0.0

    v1 = euclidean(upper_mid, lower_mid)
    v2 = euclidean(upper_left, lower_left)
    v3 = euclidean(upper_right, lower_right)
    return (v1 + v2 + v3) / (3.0 * horizontal)


# =========================
# Drawing (no MediaPipe)
# =========================
def _clip_pt(x: float, y: float, w: int, h: int) -> Optional[Tuple[int, int]]:
    ix, iy = int(round(x)), int(round(y))
    if 0 <= ix < w and 0 <= iy < h:
        return ix, iy
    return None


def draw_polyline_indices(frame: np.ndarray, pts_xy: np.ndarray, indices, color, closed: bool, thickness: int = 1):
    h, w = frame.shape[:2]
    pts = []
    for i in indices:
        if i >= len(pts_xy):
            continue
        p = _clip_pt(float(pts_xy[i][0]), float(pts_xy[i][1]), w, h)
        if p is not None:
            pts.append(p)
    if len(pts) < 2:
        return
    cv2.polylines(
        frame,
        [np.array(pts, dtype=np.int32)],
        isClosed=closed,
        color=color,
        thickness=thickness,
        lineType=cv2.LINE_AA,
    )


def draw_feature_style_overlay(frame: np.ndarray, pts_xy: np.ndarray, num_landmarks: int):
    max_idx = num_landmarks - 1

    LEFT_EYE = [33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246, 33]
    RIGHT_EYE = [362, 382, 381, 380, 374, 373, 390, 249, 263, 466, 388, 387, 386, 385, 384, 398, 362]

    LEFT_BROW = [70, 63, 105, 66, 107, 55, 65, 52, 53, 46]
    RIGHT_BROW = [300, 293, 334, 296, 336, 285, 295, 282, 283, 276]

    OUTER_LIP = [
        61, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291, 308, 324, 318, 402, 317, 14, 87, 178, 88,
        95, 185, 40, 39, 37, 0, 267, 269, 270, 409, 415, 310, 311, 312, 13, 82, 81, 42, 183, 78, 61,
    ]
    INNER_LIP = [78, 191, 80, 81, 82, 13, 312, 311, 310, 415, 308, 324, 318, 402, 317, 14, 87, 178, 88, 95, 78]

    FACE_OVAL = [
        10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377, 152, 148,
        176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109, 10,
    ]

    NOSE = [168, 6, 197, 195, 5, 4, 1, 19, 94, 2]

    def ok(seq):
        return all(0 <= i <= max_idx for i in seq)

    if ok(LEFT_EYE):
        draw_polyline_indices(frame, pts_xy, LEFT_EYE, (0, 200, 0), closed=True, thickness=1)
    if ok(RIGHT_EYE):
        draw_polyline_indices(frame, pts_xy, RIGHT_EYE, (0, 200, 0), closed=True, thickness=1)

    if ok(LEFT_BROW):
        draw_polyline_indices(frame, pts_xy, LEFT_BROW, (255, 120, 0), closed=False, thickness=1)
    if ok(RIGHT_BROW):
        draw_polyline_indices(frame, pts_xy, RIGHT_BROW, (255, 120, 0), closed=False, thickness=1)

    if ok(OUTER_LIP):
        draw_polyline_indices(frame, pts_xy, OUTER_LIP, (0, 140, 255), closed=True, thickness=1)
    if ok(INNER_LIP):
        draw_polyline_indices(frame, pts_xy, INNER_LIP, (0, 120, 255), closed=True, thickness=1)

    if ok(FACE_OVAL):
        draw_polyline_indices(frame, pts_xy, FACE_OVAL, (160, 160, 160), closed=True, thickness=1)

    if ok(NOSE):
        draw_polyline_indices(frame, pts_xy, NOSE, (255, 255, 0), closed=False, thickness=1)


def draw_dense_mesh_delaunay(frame: np.ndarray, pts_xy: np.ndarray, num_landmarks: int):
    if not _HAS_SCIPY:
        return

    h, w = frame.shape[:2]

    idxs = [
        10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377, 152, 148,
        176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109,
        70, 63, 105, 66, 107, 55, 65, 52, 53, 46,
        300, 293, 334, 296, 336, 285, 295, 282, 283, 276,
        1, 2, 3, 4, 5, 6, 168, 197, 195, 19, 94,
        33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246,
        362, 382, 381, 380, 374, 373, 390, 249, 263, 466, 388, 387, 386, 385, 384, 398,
        61, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291, 308, 324, 318, 402, 317, 14, 87, 178, 88,
        95, 185, 40, 39, 37, 0, 267, 269, 270, 409, 415, 310, 311, 312, 13, 82, 81, 42, 183, 78,
        78, 191, 80, 81, 82, 13, 312, 311, 310, 415, 308, 324, 318, 402, 317, 14, 87, 178, 88, 95,
        123, 147, 187, 207, 205, 36, 116, 117, 118, 119, 120, 121, 128, 127,
        352, 376, 411, 427, 425, 266, 345, 346, 347, 348, 349, 350, 357, 356,
    ]

    uniq = []
    seen = set()

    for i in idxs:
        if i < 0 or i >= num_landmarks:
            continue
        if i in seen:
            continue
        seen.add(i)
        uniq.append(i)

    if len(uniq) < 8:
        return

    P = np.stack([pts_xy[i][:2] for i in uniq], axis=0).astype(np.float64)
    tri = Delaunay(P)

    mesh_color = (80, 220, 80)

    for ia, ib, ic in tri.simplices:
        a = uniq[int(ia)]
        b = uniq[int(ib)]
        c = uniq[int(ic)]

        p0 = _clip_pt(float(pts_xy[a][0]), float(pts_xy[a][1]), w, h)
        p1 = _clip_pt(float(pts_xy[b][0]), float(pts_xy[b][1]), w, h)
        p2 = _clip_pt(float(pts_xy[c][0]), float(pts_xy[c][1]), w, h)

        if p0 and p1:
            cv2.line(frame, p0, p1, mesh_color, 1, cv2.LINE_AA)
        if p1 and p2:
            cv2.line(frame, p1, p2, mesh_color, 1, cv2.LINE_AA)
        if p2 and p0:
            cv2.line(frame, p2, p0, mesh_color, 1, cv2.LINE_AA)


def draw_landmark_dots(frame: np.ndarray, pts_xy: np.ndarray, num_landmarks: int):
    h, w = frame.shape[:2]
    for i in range(num_landmarks):
        ix, iy = int(round(pts_xy[i][0])), int(round(pts_xy[i][1]))
        if 0 <= ix < w and 0 <= iy < h:
            cv2.circle(frame, (ix, iy), 1, (0, 255, 0), -1, lineType=cv2.LINE_AA)


# =========================
# Temporal smoothing tracker
# =========================
@dataclass
class FaceTracker:
    prev_box: Optional[np.ndarray] = None
    prev_landmarks: Optional[np.ndarray] = None
    lost_frames: int = 0

    def smooth_box(self, box: np.ndarray) -> np.ndarray:
        arr = box.astype(np.float64)
        if self.prev_box is None:
            self.prev_box = arr
            return arr.astype(int)

        smoothed = FACE_BOX_SMOOTH_ALPHA * arr + (1.0 - FACE_BOX_SMOOTH_ALPHA) * self.prev_box
        self.prev_box = smoothed
        return smoothed.astype(int)

    def smooth_landmarks(self, landmarks_3d: np.ndarray) -> np.ndarray:
        if self.prev_landmarks is None:
            self.prev_landmarks = landmarks_3d.copy()
            return landmarks_3d

        smoothed = LANDMARK_SMOOTH_ALPHA * landmarks_3d + (1.0 - LANDMARK_SMOOTH_ALPHA) * self.prev_landmarks
        self.prev_landmarks = smoothed.copy()
        return smoothed

    def mark_lost(self) -> bool:
        self.lost_frames += 1
        if self.lost_frames >= MAX_LOST_FRAMES:
            self.reset()
            return True
        return False

    def mark_found(self) -> None:
        self.lost_frames = 0

    def reset(self) -> None:
        self.prev_box = None
        self.prev_landmarks = None
        self.lost_frames = 0


@dataclass
class AdaptiveEARState:
    baseline: Optional[float] = None
    is_closed: bool = False
    closed_since: Optional[float] = None
    closure_duration: float = 0.0

    def reset(self) -> None:
        self.baseline = None
        self.is_closed = False
        self.closed_since = None
        self.closure_duration = 0.0

    def update(self, ear: float, now_t: float) -> dict:
        if not (EAR_VALID_MIN <= ear <= EAR_VALID_MAX):
            return {
                "baseline": self.baseline,
                "threshold": None,
                "drop_ratio": 0.0,
                "is_closed": self.is_closed,
                "closure_duration": self.closure_duration,
                "alert_active": False,
            }

        if self.baseline is None:
            self.baseline = ear

        assert self.baseline is not None
        baseline = max(self.baseline, 1e-6)
        drop_ratio = max(0.0, (baseline - ear) / baseline)
        abs_drop = baseline - ear
        dynamic_threshold = baseline * (1.0 - EAR_CLOSE_REL_DROP)

        close_candidate = drop_ratio >= EAR_CLOSE_REL_DROP and abs_drop >= EAR_CLOSE_MIN_DROP
        reopen_candidate = drop_ratio <= EAR_REOPEN_REL_DROP

        if close_candidate:
            if not self.is_closed:
                self.closed_since = now_t
            self.is_closed = True
        elif reopen_candidate:
            self.is_closed = False
            self.closed_since = None
            self.closure_duration = 0.0

        if self.is_closed and self.closed_since is not None:
            self.closure_duration = max(0.0, now_t - self.closed_since)

        if (not self.is_closed) and (drop_ratio <= EAR_BASELINE_UPDATE_MAX_DROP):
            self.baseline = (1.0 - EAR_BASELINE_ALPHA) * baseline + EAR_BASELINE_ALPHA * ear
            baseline = self.baseline
            dynamic_threshold = baseline * (1.0 - EAR_CLOSE_REL_DROP)

        alert_active = self.is_closed and (self.closure_duration >= EYE_CLOSED_CONFIRM_SEC)

        return {
            "baseline": baseline,
            "threshold": dynamic_threshold,
            "drop_ratio": drop_ratio,
            "is_closed": self.is_closed,
            "closure_duration": self.closure_duration,
            "alert_active": alert_active,
        }


@dataclass
class AdaptiveMARState:
    baseline: Optional[float] = None
    is_yawning: bool = False
    yawn_since: Optional[float] = None
    yawn_duration: float = 0.0
    consecutive_events: int = 0
    last_event_time: Optional[float] = None

    def reset(self) -> None:
        self.baseline = None
        self.is_yawning = False
        self.yawn_since = None
        self.yawn_duration = 0.0
        self.consecutive_events = 0
        self.last_event_time = None

    def update(self, mar: float, now_t: float) -> dict:
        if not (MAR_VALID_MIN <= mar <= MAR_VALID_MAX):
            return {
                "baseline": self.baseline,
                "threshold_high": None,
                "ratio": 0.0,
                "rise_ratio": 0.0,
                "is_yawning": self.is_yawning,
                "yawn_duration": self.yawn_duration,
                "long_yawn": False,
                "consecutive_events": self.consecutive_events,
                "drowsy_by_yawn": False,
            }

        if self.baseline is None:
            self.baseline = mar

        assert self.baseline is not None
        baseline = max(self.baseline, 1e-6)
        yawn_threshold_high = max(
            baseline * (1.0 + MAR_DROWSY_REL_INCREASE),
            baseline + MAR_DROWSY_MIN_ABS_INC,
        )
        ratio = mar / baseline
        rise_ratio = max(0.0, (mar - baseline) / baseline)
        start_yawn = mar >= yawn_threshold_high
        stop_yawn = rise_ratio <= MAR_REOPEN_REL_INCREASE

        if not self.is_yawning and start_yawn:
            self.yawn_since = now_t
            self.is_yawning = True
        elif self.is_yawning and stop_yawn:
            event_duration = max(0.0, now_t - (self.yawn_since or now_t))
            if event_duration >= MAR_EVENT_MIN_SEC:
                if self.last_event_time is not None and (now_t - self.last_event_time) <= MAR_CONSECUTIVE_GAP_SEC:
                    self.consecutive_events += 1
                else:
                    self.consecutive_events = 1
                self.last_event_time = now_t
            self.is_yawning = False
            self.yawn_since = None
            self.yawn_duration = 0.0

        if self.is_yawning and self.yawn_since is not None:
            self.yawn_duration = max(0.0, now_t - self.yawn_since)

        # Update baseline only when mouth is around closed/neutral range.
        if not self.is_yawning and rise_ratio <= MAR_REOPEN_REL_INCREASE:
            self.baseline = (1.0 - MAR_BASELINE_ALPHA) * baseline + MAR_BASELINE_ALPHA * mar
            baseline = self.baseline
            yawn_threshold_high = max(
                baseline * (1.0 + MAR_DROWSY_REL_INCREASE),
                baseline + MAR_DROWSY_MIN_ABS_INC,
            )

        long_yawn = self.is_yawning and (self.yawn_duration >= MAR_LONG_YAWN_SEC)
        drowsy_by_yawn = (
            long_yawn
            or (self.consecutive_events >= MAR_CONSECUTIVE_EVENTS_FOR_DROWSY)
        )

        return {
            "baseline": baseline,
            "threshold_high": yawn_threshold_high,
            "ratio": ratio,
            "rise_ratio": rise_ratio,
            "is_yawning": self.is_yawning,
            "yawn_duration": self.yawn_duration,
            "long_yawn": long_yawn,
            "consecutive_events": self.consecutive_events,
            "drowsy_by_yawn": drowsy_by_yawn,
        }


def load_model(model_path: str, device: torch.device) -> nn.Module:
    model = LandmarkCNN().to(device)
    state = torch.load(model_path, map_location=device)
    model.load_state_dict(state)
    model.eval()
    return model


def main() -> None:
    if not _HAS_SCIPY:
        print("WARNING: scipy not installed -> mesh web will be disabled.")
        print("Install with: pip install scipy")

    print(f"Using device: {DEVICE}")
    print(f"Loading model: {MODEL_PATH}")
    model = load_model(MODEL_PATH, DEVICE)

    face_detector = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_frontalface_default.xml")
    if face_detector.empty():
        raise RuntimeError("Failed to load Haar Cascade.")

    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        raise RuntimeError("Cannot open webcam.")

    tracker = FaceTracker()
    ear_state = AdaptiveEARState()
    mar_state = AdaptiveMARState()
    last_log_t = 0.0
    drowsy_event_count = 0
    prev_drowsy_eye = False
    prev_drowsy_yawn = False
    window_name = "Drowsiness Detector"

    prev_t = time.time()

    while True:
        ok, frame = cap.read()
        if not ok:
            break

        frame_h, frame_w = frame.shape[:2]
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        gray = cv2.equalizeHist(gray)

        faces = face_detector.detectMultiScale(
            gray, scaleFactor=1.15, minNeighbors=5, minSize=(80, 80)
        )

        detected = len(faces) > 0

        if detected:
            tracker.mark_found()
            raw_box = max(faces, key=lambda b: int(b[2]) * int(b[3]))
            raw_box = np.array([int(v) for v in raw_box], dtype=np.int32)
            smoothed_box = tracker.smooth_box(raw_box)
            bx, by, bw, bh = int(smoothed_box[0]), int(smoothed_box[1]), int(smoothed_box[2]), int(smoothed_box[3])

        elif tracker.prev_box is not None and not tracker.mark_lost():
            bx, by, bw, bh = tracker.prev_box.astype(int)
            detected = True

        else:
            ear_state.reset()
            mar_state.reset()
            cv2.imshow(window_name, frame)
            if cv2.waitKey(1) & 0xFF == ord("q"):
                break
            continue

        ex, ey, ew, eh = expand_face_box(bx, by, bw, bh, frame_w, frame_h, CROP_EXPAND_RATIO)

        x2 = min(frame_w, ex + ew)
        y2 = min(frame_h, ey + eh)

        face_roi = frame[ey:y2, ex:x2]

        if face_roi.size == 0:
            cv2.imshow(window_name, frame)
            if cv2.waitKey(1) & 0xFF == ord("q"):
                break
            continue

        inp = preprocess_face(face_roi).to(DEVICE)

        with torch.no_grad():
            pred = model(inp).squeeze(0).detach().cpu().numpy()

        if pred.size != LANDMARK_DIM:
            continue

        pred = pred.reshape(NUM_LANDMARKS, 3).astype(np.float32)
        pred = denormalize_xy_to_frame(pred, (ex, ey, x2 - ex, y2 - ey))
        pred = tracker.smooth_landmarks(pred)

        pts_xy = pred[:, :2]

        draw_dense_mesh_delaunay(frame, pts_xy, NUM_LANDMARKS)
        draw_feature_style_overlay(frame, pts_xy, NUM_LANDMARKS)
        draw_landmark_dots(frame, pts_xy, NUM_LANDMARKS)

        ear = compute_ear(pts_xy)
        mar = compute_mar(pts_xy)
        now = time.time()
        ear_info = ear_state.update(ear, now)
        mar_info = mar_state.update(mar, now)

        fps = 1.0 / max(now - prev_t, 1e-6)
        prev_t = now

        drowsy_eye = bool(ear_info["alert_active"])
        drowsy_yawn = bool(mar_info["drowsy_by_yawn"])
        eye_closed_now = bool(ear_info["is_closed"])
        mouth_open_now = bool(mar_info["is_yawning"])

        if (drowsy_eye and not prev_drowsy_eye) or (drowsy_yawn and not prev_drowsy_yawn):
            drowsy_event_count += 1
        prev_drowsy_eye = drowsy_eye
        prev_drowsy_yawn = drowsy_yawn

        # -------- UI like requested reference --------
        GREEN = (40, 230, 40)
        ORANGE = (0, 165, 255)
        RED = (0, 60, 255)
        WHITE = (240, 240, 240)
        DARK = (28, 28, 28)

        header_h = 64
        overlay = frame.copy()
        cv2.rectangle(overlay, (0, 0), (frame_w, header_h), DARK, -1)
        cv2.addWeighted(overlay, 0.45, frame, 0.55, 0, frame)

        cv2.putText(frame, f"FPS: {int(round(fps))}", (16, 36), cv2.FONT_HERSHEY_SIMPLEX, 1.0, WHITE, 3, cv2.LINE_AA)
        cv2.putText(frame, "DROWSINESS DETECTOR", (frame_w // 2 - 210, 36), cv2.FONT_HERSHEY_SIMPLEX, 1.0, WHITE, 3, cv2.LINE_AA)

        ear_color = RED if eye_closed_now else GREEN
        mar_color = ORANGE if mouth_open_now else GREEN
        cv2.putText(frame, f"EAR: {ear:.3f}", (20, 110), cv2.FONT_HERSHEY_SIMPLEX, 1.1, ear_color, 3, cv2.LINE_AA)
        cv2.putText(frame, f"MAR: {mar:.3f}", (20, 152), cv2.FONT_HERSHEY_SIMPLEX, 1.1, mar_color, 3, cv2.LINE_AA)

        eye_status = "EYES CLOSED" if eye_closed_now else "EYES OPEN"
        mouth_status = "MOUTH OPEN" if mouth_open_now else "MOUTH NORMAL"
        cv2.putText(frame, eye_status, (20, 194), cv2.FONT_HERSHEY_SIMPLEX, 1.1, ear_color, 3, cv2.LINE_AA)
        cv2.putText(frame, mouth_status, (20, 236), cv2.FONT_HERSHEY_SIMPLEX, 1.1, mar_color, 3, cv2.LINE_AA)

        bar_w = 240
        eye_level = min(1.0, ear_info["drop_ratio"] / max(EAR_CLOSE_REL_DROP, 1e-6))
        mouth_level = min(1.0, mar_info["rise_ratio"] / max(MAR_DROWSY_REL_INCREASE, 1e-6))
        eye_fill = int(bar_w * eye_level)
        mouth_fill = int(bar_w * mouth_level)

        cv2.rectangle(frame, (20, 275), (20 + bar_w, 295), (80, 80, 80), -1)
        cv2.rectangle(frame, (20, 275), (20 + eye_fill, 295), RED if drowsy_eye else ORANGE, -1)
        cv2.putText(frame, "Drowsy", (270, 293), cv2.FONT_HERSHEY_SIMPLEX, 0.8, RED if drowsy_eye else ORANGE, 2, cv2.LINE_AA)

        cv2.rectangle(frame, (20, 315), (20 + bar_w, 335), (80, 80, 80), -1)
        cv2.rectangle(frame, (20, 315), (20 + mouth_fill, 335), ORANGE, -1)
        cv2.putText(frame, "Yawn", (270, 333), cv2.FONT_HERSHEY_SIMPLEX, 0.8, ORANGE, 2, cv2.LINE_AA)

        cv2.putText(frame, f"Yawns: {mar_info['consecutive_events']}", (20, frame_h - 84), cv2.FONT_HERSHEY_SIMPLEX, 1.0, WHITE, 3, cv2.LINE_AA)
        cv2.putText(frame, f"Drowsy: {drowsy_event_count}", (20, frame_h - 48), cv2.FONT_HERSHEY_SIMPLEX, 1.0, WHITE, 3, cv2.LINE_AA)

        if (now - last_log_t) >= TERMINAL_LOG_INTERVAL_SEC:
            ear_base = ear_info["baseline"]
            mar_base = mar_info["baseline"]
            print(
                "[READINGS] "
                f"EAR={ear:.3f} "
                f"EAR_BASE={(ear_base if ear_base is not None else float('nan')):.3f} "
                f"EAR_DROP={ear_info['drop_ratio'] * 100.0:.1f}% "
                f"EYE_CLOSED={ear_info['is_closed']} "
                f"EYE_CLOSED_SEC={ear_info['closure_duration']:.2f} "
                f"| "
                f"MAR={mar:.3f} "
                f"MAR_BASE={(mar_base if mar_base is not None else float('nan')):.3f} "
                f"MAR_RISE={mar_info['rise_ratio'] * 100.0:.1f}% "
                f"YAWNING={mar_info['is_yawning']} "
                f"YAWN_SEC={mar_info['yawn_duration']:.2f} "
                f"YAWN_COUNT={mar_info['consecutive_events']} "
                f"| DROWSY_EYE={drowsy_eye} DROWSY_YAWN={drowsy_yawn}",
                flush=True,
            )
            last_log_t = now

        if drowsy_eye:
            alert_overlay = frame.copy()
            cv2.rectangle(alert_overlay, (0, frame_h - 120), (frame_w, frame_h), (0, 0, 180), -1)
            cv2.addWeighted(alert_overlay, 0.42, frame, 0.58, 0, frame)
            cv2.putText(
                frame,
                f"!! DROWSY ??? Eyes closed {ear_info['closure_duration']:.1f}s !!",
                (30, frame_h - 34),
                cv2.FONT_HERSHEY_SIMPLEX,
                1.6,
                (255, 255, 255),
                4,
                cv2.LINE_AA,
            )
            play_beep(1500, 500)

        elif drowsy_yawn:
            alert_overlay = frame.copy()
            cv2.rectangle(alert_overlay, (0, frame_h - 120), (frame_w, frame_h), (0, 120, 220), -1)
            cv2.addWeighted(alert_overlay, 0.42, frame, 0.58, 0, frame)
            cv2.putText(
                frame,
                "!! YAWNING DETECTED ??? Stay Alert !!",
                (36, frame_h - 34),
                cv2.FONT_HERSHEY_SIMPLEX,
                1.5,
                (255, 255, 255),
                4,
                cv2.LINE_AA,
            )
            play_beep(950, 500)

        cv2.imshow(window_name, frame)

        if cv2.waitKey(1) & 0xFF == ord("q"):
            break

    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()