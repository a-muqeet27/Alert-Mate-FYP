"""
Drowsiness Detection System (standalone webcam preview)

Detects drowsiness via:
  - Eye closure using Eye Aspect Ratio (EAR)
  - Yawning using Mouth Aspect Ratio (MAR)

Requirements:
    pip install opencv-python mediapipe numpy pygame

Run:
    python detector.py
"""

import cv2
import numpy as np
import time

from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision
from mediapipe import Image, ImageFormat

try:
    import pygame
    pygame.mixer.init()
    SOUND_AVAILABLE = True
except Exception:
    SOUND_AVAILABLE = False


def play_beep():
    if not SOUND_AVAILABLE:
        return
    try:
        sr = 44100
        dur = 0.4
        freq = 880
        t = np.linspace(0, dur, int(sr * dur), endpoint=False)
        wave = (np.sin(2 * np.pi * freq * t) * 32767).astype(np.int16)
        stereo = np.column_stack([wave, wave])
        pygame.sndarray.make_sound(stereo).play()
    except Exception:
        pass


LEFT_EYE = [362, 385, 387, 263, 373, 380]
RIGHT_EYE = [33, 160, 158, 133, 153, 144]
MOUTH_TOP = 13
MOUTH_BOTTOM = 14
MOUTH_LEFT = 78
MOUTH_RIGHT = 308
MOUTH_TOP2 = 312
MOUTH_BOT2 = 317

EAR_THRESHOLD = 0.21
MAR_THRESHOLD = 0.50
EYE_CLOSED_SECONDS = 0.1
YAWN_FRAME_LIMIT = 10
ALERT_COOLDOWN = 3.0


def euclidean(p1, p2):
    return np.linalg.norm(np.array(p1) - np.array(p2))


def eye_aspect_ratio(landmarks, indices, w, h):
    pts = [(landmarks[i].x * w, landmarks[i].y * h) for i in indices]
    a = euclidean(pts[1], pts[5])
    b = euclidean(pts[2], pts[4])
    c = euclidean(pts[0], pts[3])
    return (a + b) / (2.0 * c) if c > 0 else 0.0


def mouth_aspect_ratio(landmarks, w, h):
    def pt(i):
        return (landmarks[i].x * w, landmarks[i].y * h)
    vert = (euclidean(pt(MOUTH_TOP), pt(MOUTH_BOTTOM)) +
            euclidean(pt(MOUTH_TOP2), pt(MOUTH_BOT2))) / 2.0
    horiz = euclidean(pt(MOUTH_LEFT), pt(MOUTH_RIGHT))
    return vert / horiz if horiz > 0 else 0.0


def draw_eye(frame, landmarks, indices, w, h, color):
    pts = np.array([(int(landmarks[i].x * w), int(landmarks[i].y * h)) for i in indices])
    hull = cv2.convexHull(pts)
    cv2.polylines(frame, [hull], True, color, 1)


def draw_mouth(frame, landmarks, w, h, color):
    indices = [MOUTH_TOP, MOUTH_BOTTOM, MOUTH_LEFT, MOUTH_RIGHT, MOUTH_TOP2, MOUTH_BOT2]
    pts = np.array([(int(landmarks[i].x * w), int(landmarks[i].y * h)) for i in indices])
    hull = cv2.convexHull(pts)
    cv2.polylines(frame, [hull], True, color, 1)


def put_text(frame, text, pos, scale=0.6, color=(255, 255, 255), thickness=2):
    cv2.putText(frame, text, pos, cv2.FONT_HERSHEY_SIMPLEX, scale, (0, 0, 0), thickness + 2)
    cv2.putText(frame, text, pos, cv2.FONT_HERSHEY_SIMPLEX, scale, color, thickness)


def alert_banner(frame, msg, color):
    h, w = frame.shape[:2]
    ov = frame.copy()
    cv2.rectangle(ov, (0, h - 80), (w, h), color, -1)
    cv2.addWeighted(ov, 0.6, frame, 0.4, 0, frame)
    tw = cv2.getTextSize(msg, cv2.FONT_HERSHEY_DUPLEX, 0.95, 2)[0][0]
    cv2.putText(frame, msg, ((w - tw) // 2, h - 22),
                cv2.FONT_HERSHEY_DUPLEX, 0.95, (255, 255, 255), 2)


def ensure_model(path="face_landmarker.task"):
    import os
    import urllib.request
    if not os.path.exists(path):
        url = ("https://storage.googleapis.com/mediapipe-models/"
               "face_landmarker/face_landmarker/float16/1/face_landmarker.task")
        print(f"[INFO] Downloading face landmarker model -> {path} ...")
        urllib.request.urlretrieve(url, path)
        print("[INFO] Download complete.")
    return path


def main():
    model_path = ensure_model()

    base_opts = mp_python.BaseOptions(model_asset_path=model_path)
    opts = vision.FaceLandmarkerOptions(
        base_options=base_opts,
        output_face_blendshapes=False,
        output_facial_transformation_matrixes=False,
        num_faces=1,
        min_face_detection_confidence=0.5,
        min_face_presence_confidence=0.5,
        min_tracking_confidence=0.5,
    )
    detector = vision.FaceLandmarker.create_from_options(opts)

    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("[ERROR] Cannot open webcam.")
        return

    print("[INFO] Drowsiness detector running. Press Q to quit.")
    eye_closed_start = None
    yawn_frames = 0
    last_alert_time = 0.0

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        frame = cv2.flip(frame, 1)
        h, w = frame.shape[:2]
        now = time.time()

        rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_image = Image(image_format=ImageFormat.SRGB, data=rgb_frame)
        result = detector.detect(mp_image)

        alert_active = False
        alert_msg = ""
        alert_col = (0, 0, 180)

        if result.face_landmarks:
            lm = result.face_landmarks[0]
            ear = (eye_aspect_ratio(lm, LEFT_EYE, w, h) +
                   eye_aspect_ratio(lm, RIGHT_EYE, w, h)) / 2.0
            mar = mouth_aspect_ratio(lm, w, h)

            eye_col = (0, 220, 80) if ear >= EAR_THRESHOLD else (0, 60, 255)
            mouth_col = (0, 220, 80) if mar < MAR_THRESHOLD else (0, 140, 255)
            draw_eye(frame, lm, LEFT_EYE, w, h, eye_col)
            draw_eye(frame, lm, RIGHT_EYE, w, h, eye_col)
            draw_mouth(frame, lm, w, h, mouth_col)
            put_text(frame, f"EAR: {ear:.3f}", (10, 40), color=eye_col)
            put_text(frame, f"MAR: {mar:.3f}", (10, 68), color=mouth_col)

            if ear < EAR_THRESHOLD:
                if eye_closed_start is None:
                    eye_closed_start = now
                dur = now - eye_closed_start
                if dur >= EYE_CLOSED_SECONDS:
                    alert_active = True
                    alert_msg = f"!! DROWSY - Eyes closed {dur:.1f}s !!"
            else:
                eye_closed_start = None

            if mar >= MAR_THRESHOLD:
                yawn_frames += 1
                if yawn_frames >= YAWN_FRAME_LIMIT:
                    alert_active = True
                    alert_msg = "!! YAWNING DETECTED - Stay Alert !!"
                    alert_col = (0, 80, 200)
            else:
                yawn_frames = 0

            if alert_active and (now - last_alert_time) > ALERT_COOLDOWN:
                last_alert_time = now
                play_beep()
        else:
            put_text(frame, "No face detected", (10, 40), color=(80, 80, 255))

        if alert_active:
            alert_banner(frame, alert_msg, alert_col)

        cv2.imshow("Drowsiness Detector", frame)
        if cv2.waitKey(1) & 0xFF == ord("q"):
            break

    cap.release()
    cv2.destroyAllWindows()
    detector.close()


if __name__ == "__main__":
    main()
