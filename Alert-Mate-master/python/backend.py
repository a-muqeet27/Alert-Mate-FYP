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
from io import BytesIO
from PIL import Image

app = FastAPI()

# Enable CORS for Flutter web
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Model configuration (match drowsiness_monitor_flutter.py)
IMG_SIZE = 256
HEATMAP_SIZE = 64
NUM_LANDMARKS = 68
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

# Detection thresholds and timing (same as CLI script)
EAR_THRESHOLD = 0.2
EAR_TIME_THRESHOLD = 0.5
MAR_THRESHOLD = 0.6
MAR_TIME_THRESHOLD = 2.5
DROWSY_FRAME_THRESHOLD = 15

# Model definitions
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
        hm = F.interpolate(hm, size=(HEATMAP_SIZE, HEATMAP_SIZE), mode='bilinear', align_corners=False)
        return hm

def heatmaps_to_landmarks(heatmaps, img_size):
    B, N, Hh, Wh = heatmaps.shape
    coords = torch.zeros((B, N, 2), device=heatmaps.device)
   
    for b in range(B):
        for k in range(N):
            hm = heatmaps[b, k]
            val, idx = torch.max(hm.view(-1), dim=0)
            y = (idx // Wh).float()
            x = (idx % Wh).float()
            coords[b, k, 0] = x * (img_size / Wh)
            coords[b, k, 1] = y * (img_size / Hh)
   
    return coords

# Load your models
print("Loading models...")
landmark_model = LandmarkNet().to(DEVICE)
landmark_model.load_state_dict(torch.load('landmark_detector.pth', map_location=DEVICE))
landmark_model.eval()

with open('drowsiness_classifier.pkl', 'rb') as f:
    drowsy_data = pickle.load(f)
    # Handle both dict format and direct model format
    if isinstance(drowsy_data, dict) and 'model' in drowsy_data:
        drowsiness_model = drowsy_data['model']
    else:
        drowsiness_model = drowsy_data

print("✅ Models loaded!")

def calculate_ear(eye_points):
    """Calculate Eye Aspect Ratio"""
    # Vertical distances
    A = np.linalg.norm(eye_points[1] - eye_points[5])
    B = np.linalg.norm(eye_points[2] - eye_points[4])
    # Horizontal distance
    C = np.linalg.norm(eye_points[0] - eye_points[3])
    if C < 1e-6:
        return 0.0
    ear = (A + B) / (2.0 * C)
    return ear

def calculate_mar(mouth_points):
    """Calculate Mouth Aspect Ratio"""
    # Vertical distances
    A = np.linalg.norm(mouth_points[2] - mouth_points[10])
    B = np.linalg.norm(mouth_points[4] - mouth_points[8])
    # Horizontal distance
    C = np.linalg.norm(mouth_points[0] - mouth_points[6])
    if C < 1e-6:
        return 0.0
    mar = (A + B) / (2.0 * C)
    return mar

@app.get("/")
async def root():
    return {"status": "FastAPI Drowsiness Detection Server Running"}

@app.websocket("/ws/monitor")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    print("✅ Client connected")
    
    # Open camera
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        await websocket.send_json({"error": "Could not open camera"})
        await websocket.close()
        return
    
    print("✅ Camera opened")

    # State for drowsiness logic (match CLI script)
    drowsy_counter = 0
    alert_counter = 0
    ear_low_start = None
    mar_high_start = None
    last_output_time = 0.0  # for throttling UI updates
    # Image preprocessing transform
    to_tensor = transforms.Compose([
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
    ])
    
    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                await websocket.send_json({"error": "Failed to read frame"})
                break
            
            h, w = frame.shape[:2]
            
            # Convert frame to RGB
            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            
            # Resize for model input
            resized = cv2.resize(rgb_frame, (IMG_SIZE, IMG_SIZE))
            
            # Convert to PIL Image and apply transforms
            pil_image = Image.fromarray(resized)
            img_tensor = to_tensor(pil_image).unsqueeze(0).to(DEVICE)
            
            # Get landmarks from heatmaps
            with torch.no_grad():
                heatmaps = landmark_model(img_tensor)
                coords = heatmaps_to_landmarks(heatmaps, IMG_SIZE)
                landmarks = coords[0].cpu().numpy()
                # Scale landmarks back to original frame size
                landmarks[:, 0] = landmarks[:, 0] * (w / IMG_SIZE)
                landmarks[:, 1] = landmarks[:, 1] * (h / IMG_SIZE)
            
            # Calculate EAR and MAR (adjust indices based on your model)
            # These are example indices - adjust for your landmark model
            left_eye_indices = [36, 37, 38, 39, 40, 41]
            right_eye_indices = [42, 43, 44, 45, 46, 47]
            mouth_indices = list(range(48, 68))
            
            if len(landmarks) > max(left_eye_indices + right_eye_indices + mouth_indices):
                left_eye = landmarks[left_eye_indices]
                right_eye = landmarks[right_eye_indices]
                mouth = landmarks[mouth_indices]
                
                left_ear = calculate_ear(left_eye)
                right_ear = calculate_ear(right_eye)
                avg_ear = (left_ear + right_ear) / 2.0
                mar = calculate_mar(mouth)

                # --- Drowsiness logic: copy of drowsiness_monitor_flutter.py ---
                current_time = asyncio.get_event_loop().time()
                
                # Initialize drowsiness reason at start of each loop
                drowsiness_reason = "alert"

                # Check EAR condition (eyes closed)
                if avg_ear < EAR_THRESHOLD:
                    if ear_low_start is None:
                        ear_low_start = current_time
                    ear_duration = current_time - ear_low_start

                    if ear_duration >= EAR_TIME_THRESHOLD:
                        drowsy_counter += 1
                        alert_counter = 0
                        drowsiness_reason = "eyes_closed"
                else:
                    ear_low_start = None

                # Check MAR condition (yawning)
                if mar > MAR_THRESHOLD:
                    if mar_high_start is None:
                        mar_high_start = current_time
                    mar_duration = current_time - mar_high_start

                    if mar_duration >= MAR_TIME_THRESHOLD:
                        drowsy_counter += 1
                        alert_counter = 0
                        drowsiness_reason = "yawning"
                else:
                    mar_high_start = None

                # If neither condition met
                if avg_ear >= EAR_THRESHOLD and mar <= MAR_THRESHOLD:
                    alert_counter += 1
                    drowsy_counter = 0
                    drowsiness_reason = "alert"

                # Calculate alertness percentage (0-100)
                ear_score = min(100, (avg_ear / 0.3) * 100)  # 0.3 is wide awake
                mar_score = max(0, 100 - (mar / MAR_THRESHOLD) * 100)
                alertness = (ear_score * 0.7 + mar_score * 0.3)

                # Reduce alertness if drowsy
                if drowsy_counter > 0:
                    alertness = max(0, alertness - (drowsy_counter * 2))

                # Calculate eye closure percentage
                eye_closure = max(0, min(100, (1 - (avg_ear / 0.3)) * 100))

                # Decide if drowsy based on frame counter
                is_drowsy = drowsy_counter > DROWSY_FRAME_THRESHOLD

                # Throttle sends: every 1.0s or immediately if drowsy (smoother, less flicker)
                if (current_time - last_output_time >= 1.0) or is_drowsy:
                    last_output_time = current_time

                    # Encode frame as base64 for display
                    _, buffer = cv2.imencode(".jpg", frame)
                    frame_base64 = base64.b64encode(buffer).decode("utf-8")

                    data = {
                        "alertness": float(round(alertness, 2)),
                        "ear": float(round(avg_ear, 3)),
                        "mar": float(round(mar, 3)),
                        "eyeClosure": float(round(eye_closure, 2)),
                        "isDrowsy": bool(is_drowsy),
                        "reason": drowsiness_reason,
                        "drowsyCounter": int(drowsy_counter),
                    }

                    # Add frame for UI
                    data["frame"] = frame_base64

                    await websocket.send_json(data)

            # Small delay to avoid busy-looping the CPU
            await asyncio.sleep(0.01)
            
    except WebSocketDisconnect:
        print("❌ Client disconnected")
    except Exception as e:
        print(f"❌ Error: {e}")
        await websocket.send_json({"error": str(e)})
    finally:
        cap.release()
        print("🛑 Camera released")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)