from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
import cv2
import torch
import torch.nn as nn
import torch.nn.functional as F
from torchvision import models, transforms
import pickle
import numpy as np
import json
import asyncio
import base64
from pathlib import Path
import os
import zipfile
import urllib.request
from PIL import Image
import Testing as custom_testing

app = FastAPI()
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

IMG_SIZE = 256
HEATMAP_SIZE = 64
NUM_LANDMARKS = 68
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
EAR_THRESHOLD = 0.2
EAR_TIME_THRESHOLD = 0.5
MAR_THRESHOLD = 0.6
MAR_TIME_THRESHOLD = 2.5
DROWSY_FRAME_THRESHOLD = 15


class HeatmapHead(nn.Module):
    def __init__(self, in_channels, num_landmarks):
        super().__init__()
        self.conv1 = nn.Conv2d(in_channels, 256, 3, padding=1)
        self.bn1 = nn.BatchNorm2d(256)
        self.up1 = nn.ConvTranspose2d(256, 128, 4, stride=2, padding=1)
        self.bn2 = nn.BatchNorm2d(128)
        self.up2 = nn.ConvTranspose2d(128, 64, 4, stride=2, padding=1)
        self.bn3 = nn.BatchNorm2d(64)
        self.out = nn.Conv2d(64, num_landmarks, 1)

    def forward(self, x):
        x = F.relu(self.bn1(self.conv1(x)))
        x = F.relu(self.bn2(self.up1(x)))
        x = F.relu(self.bn3(self.up2(x)))
        return self.out(x)


class LandmarkNet(nn.Module):
    def __init__(self, num_landmarks=NUM_LANDMARKS):
        super().__init__()
        res = models.resnet18(pretrained=False)
        self.conv1 = res.conv1
        self.bn1 = res.bn1
        self.relu = res.relu
        self.maxpool = res.maxpool
        self.layer1 = res.layer1
        self.layer2 = res.layer2
        self.layer3 = res.layer3
        self.layer4 = res.layer4
        self.head = HeatmapHead(512, num_landmarks)

    def forward(self, x):
        x = self.conv1(x)
        x = self.bn1(x)
        x = self.relu(x)
        x = self.maxpool(x)
        x = self.layer1(x)
        x = self.layer2(x)
        x = self.layer3(x)
        x = self.layer4(x)
        hm = self.head(x)
        hm = F.interpolate(hm, size=(HEATMAP_SIZE, HEATMAP_SIZE), mode="bilinear", align_corners=False)
        return hm


def heatmaps_to_landmarks(heatmaps, img_size):
    b, n, hh, wh = heatmaps.shape
    coords = torch.zeros((b, n, 2), device=heatmaps.device)
    for i in range(b):
        for k in range(n):
            hm = heatmaps[i, k]
            _, idx = torch.max(hm.view(-1), dim=0)
            y = (idx // wh).float()
            x = (idx % wh).float()
            coords[i, k, 0] = x * (img_size / wh)
            coords[i, k, 1] = y * (img_size / hh)
    return coords


def calculate_ear(eye_points):
    a = np.linalg.norm(eye_points[1] - eye_points[5])
    b = np.linalg.norm(eye_points[2] - eye_points[4])
    c = np.linalg.norm(eye_points[0] - eye_points[3])
    if c < 1e-6:
        return 0.0
    return (a + b) / (2.0 * c)


def calculate_mar(mouth_points):
    a = np.linalg.norm(mouth_points[2] - mouth_points[10])
    b = np.linalg.norm(mouth_points[4] - mouth_points[8])
    c = np.linalg.norm(mouth_points[0] - mouth_points[6])
    if c < 1e-6:
        return 0.0
    return (a + b) / (2.0 * c)


def _resolve_model_path(path_value: str) -> str:
    model_path = Path(path_value)
    if model_path.suffix.lower() != ".zip":
        return str(model_path)
    with zipfile.ZipFile(model_path, "r") as zf:
        # Torch checkpoints can themselves be zip containers (data.pkl + data/*).
        # If this structure exists, torch.load can read the .zip file directly.
        names = zf.namelist()
        if any(name.endswith("/data.pkl") for name in names):
            return str(model_path)
        pth_members = [n for n in zf.namelist() if n.lower().endswith(".pth")]
        if not pth_members:
            raise RuntimeError(f"No .pth model found in {model_path}")
        member = pth_members[0]
        extracted = model_path.parent / Path(member).name
        if not extracted.exists():
            print(f"Extracting {member} from {model_path.name}...")
            zf.extract(member, path=model_path.parent)
            original = model_path.parent / member
            if original != extracted:
                original.replace(extracted)
        return str(extracted)


class CustomDetectorAdapter:
    def __init__(self, model_path: str):
        self.model = custom_testing.LandmarkCNN().to(DEVICE)
        state = torch.load(model_path, map_location=DEVICE)
        self.model.load_state_dict(state)
        self.model.eval()
        self.face_detector = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_frontalface_default.xml")
        self.tracker = custom_testing.FaceTracker()
        self.ear_state = custom_testing.AdaptiveEARState()
        self.mar_state = custom_testing.AdaptiveMARState()
        self.drowsy_event_count = 0
        self.prev_drowsy_eye = False
        self.prev_drowsy_yawn = False

    def process_frame(self, frame: np.ndarray) -> dict:
        frame_h, frame_w = frame.shape[:2]
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        gray = cv2.equalizeHist(gray)
        faces = self.face_detector.detectMultiScale(gray, scaleFactor=1.15, minNeighbors=5, minSize=(80, 80))

        if len(faces) > 0:
            self.tracker.mark_found()
            raw_box = max(faces, key=lambda b: int(b[2]) * int(b[3]))
            raw_box = np.array([int(v) for v in raw_box], dtype=np.int32)
            bx, by, bw, bh = map(int, self.tracker.smooth_box(raw_box))
        elif self.tracker.prev_box is not None and not self.tracker.mark_lost():
            bx, by, bw, bh = self.tracker.prev_box.astype(int)
        else:
            self.ear_state.reset()
            self.mar_state.reset()
            return {"alertness": 100.0, "ear": 0.0, "mar": 0.0, "eyeClosure": 0.0, "isDrowsy": False, "reason": "no_face", "drowsyCounter": self.drowsy_event_count, "frame": frame}

        ex, ey, ew, eh = custom_testing.expand_face_box(bx, by, bw, bh, frame_w, frame_h, custom_testing.CROP_EXPAND_RATIO)
        x2 = min(frame_w, ex + ew)
        y2 = min(frame_h, ey + eh)
        face_roi = frame[ey:y2, ex:x2]
        if face_roi.size == 0:
            return {"alertness": 100.0, "ear": 0.0, "mar": 0.0, "eyeClosure": 0.0, "isDrowsy": False, "reason": "invalid_face_roi", "drowsyCounter": self.drowsy_event_count, "frame": frame}

        inp = custom_testing.preprocess_face(face_roi).to(DEVICE)
        with torch.no_grad():
            pred = self.model(inp).squeeze(0).detach().cpu().numpy()
        if pred.size != custom_testing.LANDMARK_DIM:
            return {"alertness": 100.0, "ear": 0.0, "mar": 0.0, "eyeClosure": 0.0, "isDrowsy": False, "reason": "invalid_landmarks", "drowsyCounter": self.drowsy_event_count, "frame": frame}

        pred = pred.reshape(custom_testing.NUM_LANDMARKS, 3).astype(np.float32)
        pred = custom_testing.denormalize_xy_to_frame(pred, (ex, ey, x2 - ex, y2 - ey))
        pred = self.tracker.smooth_landmarks(pred)
        pts_xy = pred[:, :2]

        # Draw face landmark mesh/pattern on outgoing frame, similar to Testing.py preview.
        custom_testing.draw_dense_mesh_delaunay(frame, pts_xy, custom_testing.NUM_LANDMARKS)
        custom_testing.draw_feature_style_overlay(frame, pts_xy, custom_testing.NUM_LANDMARKS)
        custom_testing.draw_landmark_dots(frame, pts_xy, custom_testing.NUM_LANDMARKS)

        ear = custom_testing.compute_ear(pts_xy)
        mar = custom_testing.compute_mar(pts_xy)
        now = asyncio.get_event_loop().time()
        ear_info = self.ear_state.update(ear, now)
        mar_info = self.mar_state.update(mar, now)
        drowsy_eye = bool(ear_info["alert_active"])
        drowsy_yawn = bool(mar_info["drowsy_by_yawn"])
        if (drowsy_eye and not self.prev_drowsy_eye) or (drowsy_yawn and not self.prev_drowsy_yawn):
            self.drowsy_event_count += 1
        self.prev_drowsy_eye = drowsy_eye
        self.prev_drowsy_yawn = drowsy_yawn

        eye_closure = max(0.0, min(100.0, ear_info["drop_ratio"] * 100.0))
        alertness = max(0.0, 100.0 - eye_closure - (mar_info["rise_ratio"] * 30.0))
        reason = "eyes_closed" if drowsy_eye else ("yawning" if drowsy_yawn else "alert")
        return {
            "alertness": float(round(alertness, 2)),
            "ear": float(round(ear, 3)),
            "mar": float(round(mar, 3)),
            "eyeClosure": float(round(eye_closure, 2)),
            "isDrowsy": bool(drowsy_eye or drowsy_yawn),
            "reason": reason,
            "drowsyCounter": int(self.drowsy_event_count),
            "frame": frame,
        }


DROWSINESS_MODE = os.getenv("DROWSINESS_MODE", "custom").strip().lower()
CUSTOM_MODEL_PATH = os.getenv("CUSTOM_MODEL_PATH", str(Path(__file__).resolve().parent / "drowsiness_model.pth.zip"))
MEDIAPIPE_MODEL_PATH = os.getenv("MEDIAPIPE_MODEL_PATH", str(Path(__file__).resolve().parent / "face_landmarker.task"))
custom_detector = None
mediapipe_detector = None
landmark_model = None

LEFT_EYE_MP = [362, 385, 387, 263, 373, 380]
RIGHT_EYE_MP = [33, 160, 158, 133, 153, 144]
MOUTH_TOP = 13
MOUTH_BOTTOM = 14
MOUTH_LEFT = 78
MOUTH_RIGHT = 308
MOUTH_TOP2 = 312
MOUTH_BOT2 = 317

MP_EAR_THRESHOLD = 0.21
MP_MAR_THRESHOLD = 0.50
MP_EYE_CLOSED_SECONDS = 0.1
MP_YAWN_FRAME_LIMIT = 10


def _euclidean(p1, p2):
    return np.linalg.norm(np.array(p1) - np.array(p2))


def _eye_aspect_ratio_mp(landmarks, indices, w, h):
    pts = [(landmarks[i].x * w, landmarks[i].y * h) for i in indices]
    a = _euclidean(pts[1], pts[5])
    b = _euclidean(pts[2], pts[4])
    c = _euclidean(pts[0], pts[3])
    return (a + b) / (2.0 * c) if c > 0 else 0.0


def _mouth_aspect_ratio_mp(landmarks, w, h):
    def pt(i):
        return (landmarks[i].x * w, landmarks[i].y * h)
    vert = (_euclidean(pt(MOUTH_TOP), pt(MOUTH_BOTTOM)) + _euclidean(pt(MOUTH_TOP2), pt(MOUTH_BOT2))) / 2.0
    horiz = _euclidean(pt(MOUTH_LEFT), pt(MOUTH_RIGHT))
    return vert / horiz if horiz > 0 else 0.0


def _ensure_mediapipe_model(path="face_landmarker.task"):
    model_path = Path(path)
    if model_path.exists():
        return str(model_path)
    url = (
        "https://storage.googleapis.com/mediapipe-models/"
        "face_landmarker/face_landmarker/float16/1/face_landmarker.task"
    )
    print(f"[mediapipe] Downloading face landmarker model to {model_path} ...")
    urllib.request.urlretrieve(url, str(model_path))
    print("[mediapipe] Model download complete.")
    return str(model_path)


class MediaPipeDetectorAdapter:
    def __init__(self, model_path: str):
        from mediapipe.tasks import python as mp_python
        from mediapipe.tasks.python import vision

        resolved_path = _ensure_mediapipe_model(model_path)
        base_opts = mp_python.BaseOptions(model_asset_path=resolved_path)
        opts = vision.FaceLandmarkerOptions(
            base_options=base_opts,
            output_face_blendshapes=False,
            output_facial_transformation_matrixes=False,
            num_faces=1,
            min_face_detection_confidence=0.5,
            min_face_presence_confidence=0.5,
            min_tracking_confidence=0.5,
        )
        self.detector = vision.FaceLandmarker.create_from_options(opts)
        self.mp_image_cls = __import__("mediapipe").Image
        self.mp_image_format = __import__("mediapipe").ImageFormat

        self.eye_closed_start = None
        self.yawn_frames = 0
        self.drowsy_event_count = 0
        self.prev_drowsy = False

    def process_frame(self, frame: np.ndarray, current_time: float) -> dict:
        h, w = frame.shape[:2]
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_image = self.mp_image_cls(image_format=self.mp_image_format.SRGB, data=rgb)
        result = self.detector.detect(mp_image)

        ear = 0.0
        mar = 0.0
        reason = "no_face"
        is_drowsy = False
        eye_closure = 0.0

        if result.face_landmarks:
            lm = result.face_landmarks[0]
            ear = (_eye_aspect_ratio_mp(lm, LEFT_EYE_MP, w, h) + _eye_aspect_ratio_mp(lm, RIGHT_EYE_MP, w, h)) / 2.0
            mar = _mouth_aspect_ratio_mp(lm, w, h)

            drowsy_eye = False
            drowsy_yawn = False

            if ear < MP_EAR_THRESHOLD:
                if self.eye_closed_start is None:
                    self.eye_closed_start = current_time
                if (current_time - self.eye_closed_start) >= MP_EYE_CLOSED_SECONDS:
                    drowsy_eye = True
                    reason = "eyes_closed"
            else:
                self.eye_closed_start = None

            if mar >= MP_MAR_THRESHOLD:
                self.yawn_frames += 1
                if self.yawn_frames >= MP_YAWN_FRAME_LIMIT:
                    drowsy_yawn = True
                    reason = "yawning"
            else:
                self.yawn_frames = 0

            is_drowsy = drowsy_eye or drowsy_yawn
            if not is_drowsy:
                reason = "alert"

            if is_drowsy and not self.prev_drowsy:
                self.drowsy_event_count += 1
            self.prev_drowsy = is_drowsy

            eye_closure = max(0.0, min(100.0, (1.0 - (ear / max(MP_EAR_THRESHOLD, 1e-6))) * 100.0))
            alertness = 0.0 if is_drowsy else 98.0
        else:
            self.eye_closed_start = None
            self.yawn_frames = 0
            self.prev_drowsy = False
            alertness = 100.0

        return {
            "alertness": float(round(alertness, 2)),
            "ear": float(round(ear, 3)),
            "mar": float(round(mar, 3)),
            "eyeClosure": float(round(eye_closure, 2)),
            "isDrowsy": bool(is_drowsy),
            "reason": reason,
            "drowsyCounter": int(self.drowsy_event_count),
            "frame": frame,
        }

    def close(self):
        try:
            self.detector.close()
        except Exception:
            pass


if DROWSINESS_MODE == "custom":
    resolved_model = _resolve_model_path(CUSTOM_MODEL_PATH)
    custom_detector = CustomDetectorAdapter(resolved_model)
    print(f"Custom model loaded from: {resolved_model}")
elif DROWSINESS_MODE == "mediapipe":
    try:
        mediapipe_detector = MediaPipeDetectorAdapter(MEDIAPIPE_MODEL_PATH)
        print(f"MediaPipe detector loaded from: {MEDIAPIPE_MODEL_PATH}")
    except Exception as e:
        raise RuntimeError(
            "Failed to initialize MediaPipe mode. Install dependencies with: "
            "pip install mediapipe opencv-python numpy"
        ) from e
else:
    print("Loading pretrained models...")
    landmark_model = LandmarkNet().to(DEVICE)
    landmark_model.load_state_dict(torch.load("landmark_detector.pth", map_location=DEVICE))
    landmark_model.eval()
    with open("drowsiness_classifier.pkl", "rb") as f:
        drowsy_data = pickle.load(f)
        _ = drowsy_data["model"] if isinstance(drowsy_data, dict) and "model" in drowsy_data else drowsy_data
    print("Pretrained models loaded!")


@app.get("/")
async def root():
    return {"status": "FastAPI Drowsiness Detection Server Running", "mode": DROWSINESS_MODE}


@app.websocket("/ws/monitor")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    await websocket.send_json({"status": "connected", "mode": DROWSINESS_MODE, "message": "Server ready to receive frames"})

    drowsy_counter = 0
    alert_counter = 0
    ear_low_start = None
    mar_high_start = None
    last_output_time = 0.0
    to_tensor = transforms.Compose([
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
    ])

    try:
        while True:
            try:
                raw = await websocket.receive_text()
                message = json.loads(raw)
                if "frame" not in message:
                    continue
                frame_bytes = base64.b64decode(message["frame"])
                frame = cv2.imdecode(np.frombuffer(frame_bytes, np.uint8), cv2.IMREAD_COLOR)
                if frame is None:
                    continue

                current_time = asyncio.get_event_loop().time()

                if DROWSINESS_MODE == "custom":
                    if custom_detector is None:
                        raise RuntimeError("Custom mode enabled but model not initialized.")
                    result = custom_detector.process_frame(frame)
                    is_drowsy = bool(result["isDrowsy"])
                    if (current_time - last_output_time >= 1.0) or is_drowsy:
                        last_output_time = current_time
                        _, buffer = cv2.imencode(".jpg", result["frame"])
                        payload = {
                            "alertness": result["alertness"],
                            "ear": result["ear"],
                            "mar": result["mar"],
                            "eyeClosure": result["eyeClosure"],
                            "isDrowsy": is_drowsy,
                            "reason": result["reason"],
                            "drowsyCounter": int(result["drowsyCounter"]),
                            "frame": base64.b64encode(buffer).decode("utf-8"),
                        }
                        await websocket.send_json(payload)
                    await asyncio.sleep(0.01)
                    continue

                if DROWSINESS_MODE == "mediapipe":
                    if mediapipe_detector is None:
                        raise RuntimeError("MediaPipe mode enabled but detector not initialized.")
                    result = mediapipe_detector.process_frame(frame, current_time)
                    is_drowsy = bool(result["isDrowsy"])
                    if (current_time - last_output_time >= 1.0) or is_drowsy:
                        last_output_time = current_time
                        _, buffer = cv2.imencode(".jpg", result["frame"])
                        payload = {
                            "alertness": result["alertness"],
                            "ear": result["ear"],
                            "mar": result["mar"],
                            "eyeClosure": result["eyeClosure"],
                            "isDrowsy": is_drowsy,
                            "reason": result["reason"],
                            "drowsyCounter": int(result["drowsyCounter"]),
                            "frame": base64.b64encode(buffer).decode("utf-8"),
                        }
                        await websocket.send_json(payload)
                    await asyncio.sleep(0.01)
                    continue

                h, w = frame.shape[:2]
                rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                resized = cv2.resize(rgb_frame, (IMG_SIZE, IMG_SIZE))
                pil_image = Image.fromarray(resized)
                img_tensor = to_tensor(pil_image).unsqueeze(0).to(DEVICE)
                with torch.no_grad():
                    heatmaps = landmark_model(img_tensor)
                    coords = heatmaps_to_landmarks(heatmaps, IMG_SIZE)
                    landmarks = coords[0].cpu().numpy()
                    landmarks[:, 0] = landmarks[:, 0] * (w / IMG_SIZE)
                    landmarks[:, 1] = landmarks[:, 1] * (h / IMG_SIZE)

                left_eye_indices = [36, 37, 38, 39, 40, 41]
                right_eye_indices = [42, 43, 44, 45, 46, 47]
                mouth_indices = list(range(48, 68))
                if len(landmarks) <= max(left_eye_indices + right_eye_indices + mouth_indices):
                    await asyncio.sleep(0.01)
                    continue

                left_eye = landmarks[left_eye_indices]
                right_eye = landmarks[right_eye_indices]
                mouth = landmarks[mouth_indices]
                avg_ear = (calculate_ear(left_eye) + calculate_ear(right_eye)) / 2.0
                mar = calculate_mar(mouth)
                drowsiness_reason = "alert"

                if avg_ear < EAR_THRESHOLD:
                    if ear_low_start is None:
                        ear_low_start = current_time
                    if current_time - ear_low_start >= EAR_TIME_THRESHOLD:
                        drowsy_counter += 1
                        alert_counter = 0
                        drowsiness_reason = "eyes_closed"
                else:
                    ear_low_start = None

                if mar > MAR_THRESHOLD:
                    if mar_high_start is None:
                        mar_high_start = current_time
                    if current_time - mar_high_start >= MAR_TIME_THRESHOLD:
                        drowsy_counter += 1
                        alert_counter = 0
                        drowsiness_reason = "yawning"
                else:
                    mar_high_start = None

                if avg_ear >= EAR_THRESHOLD and mar <= MAR_THRESHOLD:
                    alert_counter += 1
                    drowsy_counter = 0
                    drowsiness_reason = "alert"

                ear_score = min(100, (avg_ear / 0.3) * 100)
                mar_score = max(0, 100 - (mar / MAR_THRESHOLD) * 100)
                alertness = (ear_score * 0.7 + mar_score * 0.3)
                if drowsy_counter > 0:
                    alertness = max(0, alertness - (drowsy_counter * 2))
                eye_closure = max(0, min(100, (1 - (avg_ear / 0.3)) * 100))
                is_drowsy = drowsy_counter > DROWSY_FRAME_THRESHOLD

                if (current_time - last_output_time >= 1.0) or is_drowsy:
                    last_output_time = current_time
                    _, buffer = cv2.imencode(".jpg", frame)
                    payload = {
                        "alertness": float(round(alertness, 2)),
                        "ear": float(round(avg_ear, 3)),
                        "mar": float(round(mar, 3)),
                        "eyeClosure": float(round(eye_closure, 2)),
                        "isDrowsy": bool(is_drowsy),
                        "reason": drowsiness_reason,
                        "drowsyCounter": int(drowsy_counter),
                        "frame": base64.b64encode(buffer).decode("utf-8"),
                    }
                    await websocket.send_json(payload)
            except WebSocketDisconnect:
                # Normal path when user presses Stop Monitoring.
                raise
            except Exception as e:
                print(f"Error processing frame: {e}")
                continue

            await asyncio.sleep(0.01)
    except WebSocketDisconnect:
        print("Client disconnected")
    except Exception as e:
        print(f"Error: {e}")
        try:
            await websocket.send_json({"error": str(e)})
        except Exception:
            pass
    finally:
        print("Monitoring stopped")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)