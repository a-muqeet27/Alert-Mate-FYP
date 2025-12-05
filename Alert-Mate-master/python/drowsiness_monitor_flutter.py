#!/usr/bin/env python3
"""
Real-time Drowsiness Detection - Flutter Integration
Outputs JSON stats to stdout for Flutter to read
"""

import cv2
import numpy as np
import pickle
import torch
import torch.nn as nn
import torch.nn.functional as F
from torchvision import models, transforms
import time
import json
import sys
import argparse

# ============================================================================
# CONFIGURATION
# ============================================================================
IMG_SIZE = 256
HEATMAP_SIZE = 64
NUM_LANDMARKS = 68

# Detection thresholds and timing
EAR_THRESHOLD = 0.2
EAR_TIME_THRESHOLD = 0.5
MAR_THRESHOLD = 0.6
MAR_TIME_THRESHOLD = 2.5
DROWSY_FRAME_THRESHOLD = 15

# Device
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

# ============================================================================
# MODEL DEFINITIONS
# ============================================================================

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

# ============================================================================
# FEATURE EXTRACTION
# ============================================================================

def eye_aspect_ratio(eye_landmarks):
    A = np.linalg.norm(eye_landmarks[1] - eye_landmarks[5])
    B = np.linalg.norm(eye_landmarks[2] - eye_landmarks[4])
    C = np.linalg.norm(eye_landmarks[0] - eye_landmarks[3])
    if C < 1e-6:
        return 0.0
    return (A + B) / (2.0 * C)

def mouth_aspect_ratio(mouth_landmarks):
    A = np.linalg.norm(mouth_landmarks[2] - mouth_landmarks[10])
    B = np.linalg.norm(mouth_landmarks[4] - mouth_landmarks[8])
    C = np.linalg.norm(mouth_landmarks[0] - mouth_landmarks[6])
    if C < 1e-6:
        return 0.0
    return (A + B) / (2.0 * C)

def extract_features(landmarks):
    left_eye = landmarks[36:42]
    right_eye = landmarks[42:48]
    mouth = landmarks[48:68]
   
    left_ear = eye_aspect_ratio(left_eye)
    right_ear = eye_aspect_ratio(right_eye)
    avg_ear = (left_ear + right_ear) / 2.0
    mar = mouth_aspect_ratio(mouth)
   
    return [avg_ear, left_ear, right_ear, mar]

# ============================================================================
# LANDMARK DETECTION
# ============================================================================

def predict_landmarks(model, frame):
    h, w = frame.shape[:2]
   
    img_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    img_resized = cv2.resize(img_rgb, (IMG_SIZE, IMG_SIZE))
   
    to_tensor = transforms.Compose([
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
    ])
   
    img_tensor = to_tensor(img_resized).unsqueeze(0).to(DEVICE)
   
    model.eval()
    with torch.no_grad():
        heatmaps = model(img_tensor)
        coords = heatmaps_to_landmarks(heatmaps, IMG_SIZE)
   
    landmarks = coords[0].cpu().numpy()
    landmarks[:, 0] = landmarks[:, 0] * (w / IMG_SIZE)
    landmarks[:, 1] = landmarks[:, 1] * (h / IMG_SIZE)
   
    return landmarks

# ============================================================================
# MAIN DETECTION FUNCTION
# ============================================================================

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--landmark-model', default='landmark_detector.pth', help='Path to landmark model')
    parser.add_argument('--drowsy-model', default='drowsiness_classifier.pkl', help='Path to drowsiness classifier')
    parser.add_argument('--camera', type=int, default=0, help='Camera index')
    args = parser.parse_args()
    
    # Print startup message to stderr (not captured by Flutter)
    print(json.dumps({"status": "initializing"}), flush=True)
    
    try:
        # Load models
        landmark_model = LandmarkNet().to(DEVICE)
        landmark_model.load_state_dict(torch.load(args.landmark_model, map_location=DEVICE))
        landmark_model.eval()
        
        with open(args.drowsy_model, 'rb') as f:
            drowsy_data = pickle.load(f)
        drowsy_model = drowsy_data['model']
        
        ear_threshold = drowsy_data.get('ear_threshold', EAR_THRESHOLD)
        mar_threshold = drowsy_data.get('mar_threshold', MAR_THRESHOLD)
        
        print(json.dumps({"status": "models_loaded"}), flush=True)
        
        # Initialize webcam
        cap = cv2.VideoCapture(args.camera)
        
        if not cap.isOpened():
            print(json.dumps({"error": "Cannot open camera"}), flush=True)
            return
        
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
        cap.set(cv2.CAP_PROP_FPS, 30)
        
        print(json.dumps({"status": "camera_ready"}), flush=True)
        
        # Counters and timing
        drowsy_counter = 0
        alert_counter = 0
        frame_count = 0
        
        # Time tracking
        ear_low_start = None
        mar_high_start = None
        last_output_time = time.time()
        
        while True:
            ret, frame = cap.read()
            
            if not ret:
                break

   
            cv2.imshow("Camera Preview", frame)
            if cv2.waitKey(1) & 0xFF == ord('q'):
                 break
    

            
            frame_count += 1
            current_time = time.time()
            
            try:
                # Initialize drowsiness reason at start of each loop
                drowsiness_reason = "alert"
                
                # Predict landmarks
                landmarks = predict_landmarks(landmark_model, frame)
                
                # Extract features
                features = extract_features(landmarks)
                avg_ear, left_ear, right_ear, mar = features
                
                # Check EAR condition (eyes closed)
                if avg_ear < ear_threshold:
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
                if mar > mar_threshold:
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
                if avg_ear >= ear_threshold and mar <= mar_threshold:
                    alert_counter += 1
                    drowsy_counter = 0
                    drowsiness_reason = "alert"
                
                # Calculate alertness percentage (0-100)
                # Higher EAR = more alert, lower MAR = more alert
                ear_score = min(100, (avg_ear / 0.3) * 100)  # 0.3 is wide awake
                mar_score = max(0, 100 - (mar / mar_threshold) * 100)
                alertness = (ear_score * 0.7 + mar_score * 0.3)  # Weight EAR more
                
                # Reduce alertness if drowsy
                if drowsy_counter > 0:
                    alertness = max(0, alertness - (drowsy_counter * 2))
                
                # Calculate eye closure percentage
                eye_closure = max(0, min(100, (1 - (avg_ear / 0.3)) * 100))
                
                # Output JSON stats every 0.5 seconds (or immediately if drowsy)
                is_drowsy = drowsy_counter > DROWSY_FRAME_THRESHOLD
                
                if (current_time - last_output_time >= 0.5) or is_drowsy:
                    output = {
                        "alertness": float(round(alertness, 2)),
                        "ear": float(round(avg_ear, 3)),
                        "mar": float(round(mar, 3)),
                        "eyeClosure": float(round(eye_closure, 2)),
                        "isDrowsy": bool(is_drowsy),
                        "reason": drowsiness_reason,
                        "drowsyCounter": int(drowsy_counter),
                        "timestamp": int(current_time * 1000)
                    }
                    print(json.dumps(output), flush=True)
                    last_output_time = current_time
                
            except Exception as e:
                print(json.dumps({"error": str(e)}), flush=True)
        
        cap.release()
        print(json.dumps({"status": "stopped"}), flush=True)
        
    except Exception as e:
        print(json.dumps({"error": str(e)}), flush=True)
        sys.exit(1)

if __name__ == "__main__":
    main()