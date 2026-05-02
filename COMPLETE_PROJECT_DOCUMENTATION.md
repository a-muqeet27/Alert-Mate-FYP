# Alert-Mate: Complete Project Documentation

> **Purpose**: This document provides comprehensive documentation for the Alert-Mate drowsiness detection system. It's designed for AI agents or developers with zero context about the project.

---

## Table of Contents
1. [Project Overview](#project-overview)
2. [Technology Stack](#technology-stack)
3. [System Architecture](#system-architecture)
4. [Database Schema](#database-schema)
5. [API Routes & Endpoints](#api-routes--endpoints)
6. [User Roles & Permissions](#user-roles--permissions)
7. [Application Flow](#application-flow)
8. [Machine Learning Pipeline](#machine-learning-pipeline)
9. [Real-time Data Synchronization](#real-time-data-synchronization)
10. [File Structure](#file-structure)
11. [Setup & Configuration](#setup--configuration)

---

## 1. Project Overview

**Alert-Mate** is a comprehensive driver drowsiness detection and fleet management system designed to enhance road safety through real-time monitoring and alerting.

### Core Purpose
- **Primary**: Detect driver drowsiness in real-time using computer vision and facial landmark detection
- **Secondary**: Provide fleet management capabilities for vehicle owners
- **Tertiary**: Enable passengers to track their rides and admins to oversee the entire system

### Key Features
- Real-time facial landmark detection (478 landmarks)
- Eye Aspect Ratio (EAR) and Mouth Aspect Ratio (MAR) calculation
- Adaptive drowsiness thresholds with personalized baselines
- Live GPS tracking and location sharing
- Multi-role dashboard system (Driver, Passenger, Owner, Admin)
- Emergency contact management
- Historical trip analytics
- Document verification workflow


---

## 2. Technology Stack

### Frontend (Mobile Application)
- **Framework**: Flutter 3.9.2+ (Dart)
- **UI**: Material Design 3
- **State Management**: StatefulWidget with StreamBuilder for real-time updates

### Backend Services
- **Authentication**: Firebase Authentication (Email/Password)
- **Database**: 
  - **Cloud Firestore**: Persistent data (users, vehicles, documents)
  - **Firebase Realtime Database**: High-frequency updates (GPS, monitoring stats)
- **Storage**: 
  - Firebase Storage (primary)
  - Cloudinary (document images)

### Machine Learning Backend
- **Framework**: FastAPI (Python)
- **Communication**: WebSocket (real-time bidirectional)
- **Computer Vision**: 
  - PyTorch (deep learning)
  - OpenCV (image processing)
  - MediaPipe (alternative landmark detection)
- **Models**:
  - Custom CNN for facial landmark detection (478 landmarks)
  - ResNet18-based architecture with SE blocks and Coordinate Attention

### Key Dependencies

#### Flutter (pubspec.yaml)
```yaml
dependencies:
  firebase_core: ^3.6.0
  firebase_auth: ^5.3.1
  cloud_firestore: ^5.4.4
  firebase_database: ^11.1.4
  firebase_storage: ^12.3.4
  camera: ^0.11.0+2
  web_socket_channel: ^2.4.0
  geolocator: ^13.0.2
  flutter_map: ^7.0.2
  latlong2: ^0.9.1
  image_picker: 1.1.2
  permission_handler: ^11.3.1
  flutter_ringtone_player: ^4.0.0+4
  country_picker: ^2.0.25
  pin_code_fields: ^8.0.1
```

#### Python (backend.py)
```python
fastapi
uvicorn
opencv-python
torch
torchvision
numpy
scipy
mediapipe (optional)
```


---

## 3. System Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Flutter Mobile App                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐       │
│  │  Driver  │  │Passenger │  │  Owner   │  │  Admin   │       │
│  │Dashboard │  │Dashboard │  │Dashboard │  │Dashboard │       │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘       │
│       │             │              │              │              │
└───────┼─────────────┼──────────────┼──────────────┼─────────────┘
        │             │              │              │
        ├─────────────┴──────────────┴──────────────┤
        │                                            │
┌───────▼────────────────────────────────────────────▼───────────┐
│                    Firebase Services                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │   Firebase   │  │   Firestore  │  │   Realtime   │         │
│  │     Auth     │  │   Database   │  │   Database   │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
│  ┌──────────────┐  ┌──────────────┐                            │
│  │   Firebase   │  │  Cloudinary  │                            │
│  │   Storage    │  │   (Images)   │                            │
│  └──────────────┘  └──────────────┘                            │
└─────────────────────────────────────────────────────────────────┘
        │
        │ WebSocket Connection (ws://backend:8000/ws/monitor)
        │
┌───────▼─────────────────────────────────────────────────────────┐
│              Python FastAPI Backend (Port 8000)                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  WebSocket Handler (/ws/monitor)                         │  │
│  │  - Receives base64 frames from Flutter                   │  │
│  │  - Processes through ML pipeline                         │  │
│  │  - Returns drowsiness metrics (EAR, MAR, alertness)      │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  ML Pipeline                                              │  │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐         │  │
│  │  │   Haar     │→ │  Landmark  │→ │ Drowsiness │         │  │
│  │  │  Cascade   │  │  Detector  │  │ Classifier │         │  │
│  │  └────────────┘  └────────────┘  └────────────┘         │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow

#### 1. Authentication Flow
```
User → AuthScreen → FirebaseAuth → Firestore (users collection) → Role-based Dashboard
```

#### 2. Drowsiness Detection Flow
```
Driver Dashboard → Camera → Capture Frame (500ms interval) 
    → Base64 Encode → WebSocket → Python Backend
    → Face Detection → Landmark Detection → EAR/MAR Calculation
    → Drowsiness Classification → JSON Response
    → Flutter App → Update UI + Play Alert + Save to Realtime DB
```

#### 3. Location Tracking Flow
```
Driver Dashboard → GPS Service (Geolocator) 
    → Firestore (drivers collection) → Real-time Stream
    → Owner/Admin Dashboard → Map Display
```


---

## 4. Database Schema

### 4.1 Cloud Firestore Collections

#### Collection: `users`
Stores user profile information for all roles.

```typescript
{
  id: string,                    // Firebase UID
  firstName: string,
  lastName: string,
  email: string,
  phone: string,                 // Format: "+1 1234567890"
  role: string,                  // Primary role: 'driver' | 'passenger' | 'owner' | 'admin'
  roles: string[],               // All roles user has access to
  activeRole: string,            // Currently active role
  driverDocsApproved: boolean,   // Driver document verification status
  createdAt: Timestamp,
  updatedAt: Timestamp
}
```

**Access Rules**:
- Read: Any authenticated user
- Create: Authenticated user (own profile only)
- Update: Owner or Admin
- Delete: Owner or Admin

---

#### Collection: `vehicles`
Stores vehicle information and assignment status.

```typescript
{
  id: string,                    // Auto-generated document ID
  make: string,                  // e.g., "Toyota"
  model: string,                 // e.g., "Corolla"
  year: string,                  // e.g., "2020"
  licensePlate: string,          // Unique identifier
  type: string,                  // 'Car' | 'Bus' | 'Van' | 'Truck' | 'Rickshaw'
  ownerId: string,               // User ID of vehicle owner
  ownerEmail: string,
  assignedDriverId: string?,     // User ID of assigned driver (nullable)
  assignedDriverEmail: string?,
  driverName: string?,
  status: string,                // 'Active' | 'Break' | 'Critical' | 'Offline'
  alertness: number,             // 0-100
  location: string?,             // Human-readable location
  lastUpdate: string?,           // ISO timestamp
  pendingAssignment: boolean,    // Waiting for any driver
  pendingOwnerAssignment: boolean, // Waiting for owner to become driver
  createdAt: Timestamp,
  updatedAt: Timestamp
}
```

**Access Rules**:
- Read: Any authenticated user
- Write: Any authenticated user (with business logic validation)

---

#### Collection: `drivers`
Stores live GPS location and status for active drivers.

```typescript
{
  id: string,                    // Driver's user ID
  name: string,                  // Driver's full name
  lat: number,                   // Latitude
  lng: number,                   // Longitude
  status: string,                // 'on_trip' | 'idle' | 'offline'
  drowsinessAlert: boolean,      // Current drowsiness state
  updatedAt: Timestamp
}
```

**Access Rules**:
- Read: Any authenticated user
- Write: Owner only (driver can only update their own document)

---

#### Collection: `emergencyContacts`
Stores emergency contact information for drivers.

```typescript
{
  id: string,
  userId: string,                // Driver's user ID
  userRole: string,              // 'driver'
  name: string,
  relationship: string,          // e.g., "Spouse", "Parent"
  phone: string,
  email: string,
  priority: string,              // 'primary' | 'secondary'
  methods: string[],             // ['call', 'sms', 'email']
  enabled: boolean,
  createdAt: Timestamp,
  updatedAt: Timestamp
}
```

---

#### Collection: `driver_document_submissions`
Stores driver document verification submissions (CNIC, License).

```typescript
{
  id: string,
  driverId: string,
  driverEmail: string,
  driverName: string,
  cnicImageUrl: string,          // Cloudinary URL
  licenseImageUrl: string,       // Cloudinary URL
  status: string,                // 'pending' | 'approved' | 'rejected'
  submittedAt: Timestamp,
  reviewedAt: Timestamp?,
  reviewedBy: string?,           // Admin user ID
  rejectionReason: string?
}
```

---

#### Collection: `owner_vehicle_submissions`
Stores vehicle registration document submissions from owners.

```typescript
{
  id: string,
  ownerId: string,
  ownerEmail: string,
  vehicleId: string,
  make: string,
  model: string,
  year: string,
  licensePlate: string,
  type: string,
  registrationImageUrl: string,  // Cloudinary URL
  status: string,                // 'pending' | 'approved' | 'rejected'
  submittedAt: Timestamp,
  reviewedAt: Timestamp?,
  reviewedBy: string?,
  rejectionReason: string?
}
```

---

#### Collection: `vehicleAssignments`
Tracks vehicle-driver assignment history.

```typescript
{
  id: string,
  vehicleId: string,
  driverId: string,
  ownerId: string,
  assignedAt: Timestamp,
  unassignedAt: Timestamp?,
  status: string                 // 'active' | 'completed'
}
```


### 4.2 Firebase Realtime Database Structure

Used for high-frequency, low-latency updates (monitoring stats, GPS).

```json
{
  "drivers": {
    "{driverId}": {
      "monitoring_sessions": {
        "{sessionId}": {
          "startTime": 1234567890000,
          "endTime": 1234567890000,
          "status": "active | completed",
          "duration_minutes": 45,
          "average_alertness": 85.5,
          "drowsiness_events": 3,
          "data_points": 540,
          "stats": {
            "{statId}": {
              "timestamp": 1234567890000,
              "alertness": 85.5,
              "ear": 0.25,
              "mar": 0.35,
              "eyeClosure": 15.0,
              "drowsinessDetected": false
            }
          }
        }
      },
      "current_stats": {
        "alertness": 85.5,
        "ear": 0.25,
        "mar": 0.35,
        "eyeClosure": 15.0,
        "drowsinessDetected": false,
        "lastUpdate": 1234567890000
      },
      "history": {
        "totalSessions": 10,
        "totalDrivingMinutes": 450,
        "totalDrowsinessEvents": 15,
        "averageAlertness": 82.3,
        "lastSession": 1234567890000
      }
    }
  }
}
```

**Access Rules** (database.rules.json):
```json
{
  "rules": {
    "drivers": {
      "$driverId": {
        ".read": "auth != null",
        ".write": "auth != null && auth.uid === $driverId"
      }
    }
  }
}
```


---

## 5. API Routes & Endpoints

### 5.1 Python FastAPI Backend

**Base URL**: `http://localhost:8000` (or ngrok tunnel in development)

#### GET `/`
Health check endpoint.

**Response**:
```json
{
  "status": "FastAPI Drowsiness Detection Server Running",
  "mode": "custom | mediapipe | pretrained"
}
```

---

#### WebSocket `/ws/monitor`
Real-time drowsiness monitoring endpoint.

**Connection Flow**:
1. Client connects to WebSocket
2. Server sends connection confirmation
3. Client sends frames continuously
4. Server processes and responds with metrics

**Client → Server Message**:
```json
{
  "frame": "base64_encoded_image_string"
}
```

**Server → Client Response**:
```json
{
  "alertness": 85.5,
  "ear": 0.25,
  "mar": 0.35,
  "eyeClosure": 15.0,
  "isDrowsy": false,
  "reason": "alert | eyes_closed | yawning | no_face",
  "drowsyCounter": 3,
  "frame": "base64_encoded_processed_frame"
}
```

**Detection Modes**:

1. **Custom Mode** (default):
   - Uses custom-trained CNN model
   - 478 facial landmarks
   - Adaptive EAR/MAR thresholds
   - Configuration:
     ```python
     DROWSINESS_MODE = "custom"
     CUSTOM_MODEL_PATH = "drowsiness_model.pth.zip"
     ```

2. **MediaPipe Mode**:
   - Uses Google MediaPipe Face Landmarker
   - 468 facial landmarks
   - Fixed thresholds
   - Configuration:
     ```python
     DROWSINESS_MODE = "mediapipe"
     MEDIAPIPE_MODEL_PATH = "face_landmarker.task"
     ```

3. **Pretrained Mode**:
   - Uses pretrained landmark detector + classifier
   - Legacy mode
   - Configuration:
     ```python
     DROWSINESS_MODE = "pretrained"
     ```

**Thresholds (Custom Mode)**:
```python
EAR_CLOSE_REL_DROP = 0.07          # 7% drop from baseline
EAR_REOPEN_REL_DROP = 0.04         # Hysteresis
EAR_CLOSE_MIN_DROP = 0.008         # Minimum absolute drop
EYE_CLOSED_CONFIRM_SEC = 0.45      # Blink rejection time

MAR_DROWSY_REL_INCREASE = 0.07     # 7% increase from baseline
MAR_DROWSY_MIN_ABS_INC = 0.02      # Minimum absolute increase
MAR_LONG_YAWN_SEC = 1.0            # Long yawn duration
MAR_EVENT_MIN_SEC = 0.35           # Minimum yawn duration
```


---

## 6. User Roles & Permissions

### 6.1 Role Hierarchy

```
Admin (Highest Authority)
  ├── Can approve/reject all documents
  ├── Can view all users, vehicles, drivers
  ├── Can manage system-wide settings
  └── Cannot self-register (credentials provided)

Vehicle Owner
  ├── Can add/manage vehicles
  ├── Can assign drivers to vehicles
  ├── Can view assigned driver locations
  ├── Can become a driver (dual role)
  └── Can view fleet analytics

Driver
  ├── Can start/stop monitoring sessions
  ├── Can submit verification documents
  ├── Can manage emergency contacts
  ├── Can view own history
  └── Must be approved by admin

Passenger
  ├── Can search vehicles by license plate
  ├── Can track assigned vehicle location
  ├── Can view driver status
  └── Limited access (read-only)
```

### 6.2 Role-Based Features

| Feature | Driver | Passenger | Owner | Admin |
|---------|--------|-----------|-------|-------|
| Drowsiness Monitoring | ✅ | ❌ | ✅* | ❌ |
| Document Upload | ✅ | ❌ | ✅ | ❌ |
| Document Approval | ❌ | ❌ | ❌ | ✅ |
| Vehicle Management | ❌ | ❌ | ✅ | ✅ |
| Driver Assignment | ❌ | ❌ | ✅ | ✅ |
| Live Tracking | ❌ | ✅ | ✅ | ✅ |
| Emergency Contacts | ✅ | ❌ | ✅* | ❌ |
| Trip History | ✅ | ❌ | ✅ | ✅ |
| System Analytics | ❌ | ❌ | ✅ | ✅ |

*Only if owner has driver role

### 6.3 Authentication Flow by Role

#### Driver Sign-Up Flow
```
1. Select "Driver" role
2. Enter: First Name, Last Name, Email, Phone, Password
3. Submit → Firebase Auth creates account
4. Email verification sent
5. User verifies email
6. Sign in → Redirected to Document Gate Screen
7. Upload CNIC + License images
8. Wait for admin approval
9. Once approved → Access Driver Dashboard
```

#### Owner Sign-Up Flow
```
1. Select "Vehicle Owner" role
2. Enter: First Name, Last Name, Email, Phone, Password
3. Submit → Firebase Auth creates account
4. Email verification sent
5. User verifies email
6. Sign in → Access Owner Dashboard
7. Add vehicles with registration documents
8. Wait for admin approval
9. Once approved → Can assign drivers
```

#### Passenger Sign-Up Flow
```
1. Select "Passenger" role
2. Enter: First Name, Last Name, Email, Phone, Password
3. Submit → Firebase Auth creates account
4. Email verification sent
5. User verifies email
6. Sign in → Access Passenger Dashboard immediately
```

#### Admin Sign-In Flow
```
1. Select "Admin" role
2. Enter: Email, Password (no sign-up option)
3. Submit → Firebase Auth validates
4. Access Admin Dashboard immediately (no email verification required)
```


---

## 7. Application Flow

### 7.1 Driver Monitoring Session Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. Driver Dashboard Loaded                                      │
│    - Check if documents approved                                │
│    - If not approved → Show Document Gate Screen                │
│    - If approved → Show Dashboard                               │
└────────────────────────┬────────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────────┐
│ 2. Start Monitoring Button Pressed                              │
│    - Request camera permission                                  │
│    - Request location permission                                │
│    - Initialize camera controller                               │
│    - Connect to WebSocket (ws://backend:8000/ws/monitor)        │
└────────────────────────┬────────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────────┐
│ 3. Monitoring Session Active                                    │
│    ┌──────────────────────────────────────────────────────┐    │
│    │ Every 500ms:                                         │    │
│    │  - Capture camera frame                              │    │
│    │  - Convert to base64                                 │    │
│    │  - Send via WebSocket                                │    │
│    └──────────────────────────────────────────────────────┘    │
│    ┌──────────────────────────────────────────────────────┐    │
│    │ Every 5 seconds:                                     │    │
│    │  - Get GPS coordinates                               │    │
│    │  - Update Firestore (drivers collection)            │    │
│    └──────────────────────────────────────────────────────┘    │
│    ┌──────────────────────────────────────────────────────┐    │
│    │ On WebSocket Response:                               │    │
│    │  - Parse JSON (alertness, ear, mar, isDrowsy)       │    │
│    │  - Update UI metrics                                 │    │
│    │  - Save to Realtime DB (current_stats)              │    │
│    │  - If isDrowsy → Play alert sound                   │    │
│    │  - If isDrowsy → Show warning overlay               │    │
│    └──────────────────────────────────────────────────────┘    │
└────────────────────────┬────────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────────┐
│ 4. Stop Monitoring Button Pressed                               │
│    - Close WebSocket connection                                 │
│    - Stop camera                                                │
│    - Calculate session statistics                               │
│    - Save to Realtime DB (monitoring_sessions)                  │
│    - Update driver history                                      │
│    - Show session summary                                       │
└─────────────────────────────────────────────────────────────────┘
```

### 7.2 Vehicle Assignment Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ Owner Dashboard → Add Vehicle                                    │
│  - Enter: Make, Model, Year, License Plate, Type               │
│  - Upload registration document                                 │
│  - Submit → Creates vehicle in Firestore                        │
│  - Status: Pending Admin Approval                               │
└────────────────────────┬────────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────────┐
│ Admin Dashboard → Review Vehicle Submission                      │
│  - View registration document                                   │
│  - Approve or Reject                                            │
│  - If approved → Vehicle status: Active                         │
└────────────────────────┬────────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────────┐
│ Owner Dashboard → Assign Driver                                  │
│  - Select vehicle                                               │
│  - Choose option:                                               │
│    A) "I will drive" → Owner becomes driver                     │
│    B) "Assign another driver" → Search for driver               │
└────────────────────────┬────────────────────────────────────────┘
                         │
                    ┌────┴────┐
                    │         │
        ┌───────────▼─┐   ┌───▼──────────┐
        │ Option A    │   │ Option B     │
        │ Owner→Driver│   │ Assign Driver│
        └───────┬─────┘   └───┬──────────┘
                │             │
                │             │
┌───────────────▼─────────────▼───────────────────────────────────┐
│ Vehicle Assignment Complete                                      │
│  - Update vehicle.assignedDriverId                              │
│  - Update vehicle.assignedDriverEmail                           │
│  - Create vehicleAssignments record                             │
│  - Driver can now start monitoring with this vehicle            │
└─────────────────────────────────────────────────────────────────┘
```

### 7.3 Document Verification Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ Driver → Upload Documents (CNIC + License)                       │
│  - Select CNIC image from gallery                               │
│  - Select License image from gallery                            │
│  - Upload to Cloudinary                                         │
│  - Create driver_document_submissions record                    │
│  - Status: Pending                                              │
└────────────────────────┬────────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────────┐
│ Admin Dashboard → Review Documents                               │
│  - View CNIC image                                              │
│  - View License image                                           │
│  - Verify authenticity                                          │
│  - Decision:                                                    │
│    ✅ Approve → Set user.driverDocsApproved = true             │
│    ❌ Reject → Provide rejection reason                        │
└────────────────────────┬────────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────────┐
│ Driver Notification                                              │
│  - If approved → Can access Driver Dashboard                    │
│  - If rejected → Must resubmit documents                        │
└─────────────────────────────────────────────────────────────────┘
```


---

## 8. Machine Learning Pipeline

### 8.1 Model Architecture

#### Custom CNN Model (LandmarkCNN)

```python
Input: RGB Image (224x224x3)
    ↓
Stem Block (Conv7x7, stride=2, BN, ReLU, MaxPool)
    ↓
Layer 1: 2x ResidualBlock(64 channels)
    ↓
Layer 2: 2x ResidualBlock(128 channels, stride=2)
    ↓
Layer 3: 2x ResidualBlock(256 channels, stride=2)
    ↓
Layer 4: 2x ResidualBlock(512 channels, stride=2)
    ↓
Coordinate Attention Module (512 channels)
    ↓
Global Average Pooling
    ↓
Fully Connected Layers:
    - FC(512 → 1024) + ReLU + Dropout(0.3)
    - FC(1024 → 1024) + ReLU + Dropout(0.2)
    - FC(1024 → 1434)  # 478 landmarks × 3 (x, y, z)
    ↓
Output: 478 facial landmarks (x, y, z coordinates)
```

**Key Components**:

1. **ResidualBlock**:
   - Conv3x3 → BN → ReLU → Conv3x3 → BN → SE Block
   - Skip connection
   - ReLU activation

2. **SE Block (Squeeze-and-Excitation)**:
   - Global Average Pooling
   - FC(channels → channels/16) → ReLU
   - FC(channels/16 → channels) → Sigmoid
   - Channel-wise multiplication

3. **Coordinate Attention**:
   - Separate pooling for height and width
   - Spatial attention mechanism
   - Preserves location information

### 8.2 Drowsiness Detection Algorithm

#### Eye Aspect Ratio (EAR)

```python
def compute_ear(landmarks):
    # Left eye indices: [33, 160, 158, 133, 153, 144]
    # Right eye indices: [362, 385, 387, 263, 373, 380]
    
    # For each eye:
    #   p1 -------- p4
    #   |  p2  p6  |
    #   |  p3  p5  |
    #   ---------------
    
    vertical_1 = distance(p2, p6)
    vertical_2 = distance(p3, p5)
    horizontal = distance(p1, p4)
    
    ear = (vertical_1 + vertical_2) / (2.0 * horizontal)
    
    return (left_ear + right_ear) / 2.0
```

**Interpretation**:
- Normal (eyes open): EAR ≈ 0.25 - 0.35
- Drowsy (eyes closing): EAR < 0.20
- Closed (eyes shut): EAR < 0.15

#### Mouth Aspect Ratio (MAR)

```python
def compute_mar(landmarks):
    # Mouth landmarks:
    # left_corner (78), right_corner (308)
    # upper_mid (13), lower_mid (14)
    # upper_left (82), lower_left (87)
    # upper_right (312), lower_right (317)
    
    vertical_1 = distance(upper_mid, lower_mid)
    vertical_2 = distance(upper_left, lower_left)
    vertical_3 = distance(upper_right, lower_right)
    horizontal = distance(left_corner, right_corner)
    
    mar = (vertical_1 + vertical_2 + vertical_3) / (3.0 * horizontal)
    
    return mar
```

**Interpretation**:
- Normal (mouth closed): MAR ≈ 0.10 - 0.30
- Talking: MAR ≈ 0.30 - 0.50
- Yawning: MAR > 0.50

### 8.3 Adaptive Thresholding

#### Adaptive EAR State Machine

```python
class AdaptiveEARState:
    baseline: float = None          # Personal baseline (learned)
    is_closed: bool = False
    closed_since: float = None
    closure_duration: float = 0.0
    
    def update(ear, current_time):
        # Initialize baseline on first frame
        if baseline is None:
            baseline = ear
        
        # Calculate drop from baseline
        drop_ratio = (baseline - ear) / baseline
        
        # Detect closure (7% drop from baseline)
        if drop_ratio >= 0.07 and abs_drop >= 0.008:
            if not is_closed:
                closed_since = current_time
            is_closed = True
        
        # Detect reopening (4% drop - hysteresis)
        elif drop_ratio <= 0.04:
            is_closed = False
            closed_since = None
            closure_duration = 0.0
        
        # Calculate closure duration
        if is_closed and closed_since:
            closure_duration = current_time - closed_since
        
        # Alert if closed for > 0.45 seconds (blink rejection)
        alert_active = is_closed and closure_duration >= 0.45
        
        # Update baseline when eyes are open
        if not is_closed and drop_ratio <= 0.05:
            baseline = 0.97 * baseline + 0.03 * ear
        
        return alert_active
```

#### Adaptive MAR State Machine

```python
class AdaptiveMARState:
    baseline: float = None
    is_yawning: bool = False
    yawn_since: float = None
    consecutive_events: int = 0
    last_event_time: float = None
    
    def update(mar, current_time):
        # Initialize baseline
        if baseline is None:
            baseline = mar
        
        # Calculate rise from baseline
        rise_ratio = (mar - baseline) / baseline
        
        # Detect yawn start (7% increase from baseline)
        yawn_threshold = max(
            baseline * 1.07,
            baseline + 0.02
        )
        
        if mar >= yawn_threshold:
            if not is_yawning:
                yawn_since = current_time
            is_yawning = True
        
        # Detect yawn end (4% increase - hysteresis)
        elif rise_ratio <= 0.04:
            if is_yawning:
                event_duration = current_time - yawn_since
                
                # Count as event if > 0.35 seconds
                if event_duration >= 0.35:
                    # Check if consecutive (within 6 seconds)
                    if last_event_time and (current_time - last_event_time) <= 6.0:
                        consecutive_events += 1
                    else:
                        consecutive_events = 1
                    last_event_time = current_time
            
            is_yawning = False
            yawn_since = None
        
        # Calculate yawn duration
        yawn_duration = 0.0
        if is_yawning and yawn_since:
            yawn_duration = current_time - yawn_since
        
        # Drowsy if long yawn (>1s) or 2+ consecutive yawns
        long_yawn = yawn_duration >= 1.0
        drowsy_by_yawn = long_yawn or consecutive_events >= 2
        
        # Update baseline when mouth is closed
        if not is_yawning and rise_ratio <= 0.04:
            baseline = 0.97 * baseline + 0.03 * mar
        
        return drowsy_by_yawn
```

### 8.4 Alertness Score Calculation

```python
def calculate_alertness(ear_info, mar_info):
    # Eye closure component (0-100)
    eye_closure = ear_info['drop_ratio'] * 100.0
    
    # Mouth opening component (0-30)
    mouth_penalty = mar_info['rise_ratio'] * 30.0
    
    # Combined alertness score
    alertness = max(0.0, 100.0 - eye_closure - mouth_penalty)
    
    return alertness
```

**Score Ranges**:
- 90-100: Fully alert
- 70-89: Good alertness
- 50-69: Moderate alertness
- 30-49: Low alertness (warning)
- 0-29: Critical (drowsy)


---

## 9. Real-time Data Synchronization

### 9.1 WebSocket Communication

#### Connection Establishment
```dart
// Flutter Client
final channel = WebSocketChannel.connect(
  Uri.parse('ws://backend:8000/ws/monitor')
);

// Listen for messages
channel.stream.listen((message) {
  final data = jsonDecode(message);
  updateUI(data);
});

// Send frame
channel.sink.add(jsonEncode({
  'frame': base64Frame
}));
```

#### Frame Processing Pipeline
```
Camera → Capture (500ms) → Resize (640x480) → JPEG Encode 
  → Base64 Encode → JSON Wrap → WebSocket Send
  → Python Backend → Decode → Process → Respond
  → Flutter Receive → Parse → Update UI → Save to DB
```

### 9.2 Firestore Real-time Streams

#### Driver Location Stream
```dart
// Owner/Admin Dashboard
Stream<List<DriverLocation>> getActiveDrivers() {
  return FirebaseFirestore.instance
    .collection('drivers')
    .where('status', isNotEqualTo: 'offline')
    .snapshots()
    .map((snapshot) => snapshot.docs
      .map((doc) => DriverLocation.fromMap(doc.data(), doc.id))
      .toList()
    );
}
```

#### Vehicle Status Stream
```dart
// Owner Dashboard
Stream<List<Vehicle>> getMyVehicles(String ownerId) {
  return FirebaseFirestore.instance
    .collection('vehicles')
    .where('ownerId', isEqualTo: ownerId)
    .snapshots()
    .map((snapshot) => snapshot.docs
      .map((doc) => Vehicle.fromMap(doc.data()))
      .toList()
    );
}
```

### 9.3 Realtime Database Streams

#### Current Stats Stream
```dart
// Driver Dashboard
Stream<Map<String, dynamic>> getCurrentStats(String driverId) {
  return FirebaseDatabase.instance
    .ref('drivers/$driverId/current_stats')
    .onValue
    .map((event) => Map<String, dynamic>.from(event.snapshot.value as Map));
}
```

#### History Stream
```dart
// Driver History Screen
Stream<Map<String, dynamic>> getDriverHistory(String driverId) {
  return FirebaseDatabase.instance
    .ref('drivers/$driverId/history')
    .onValue
    .map((event) => Map<String, dynamic>.from(event.snapshot.value as Map));
}
```

### 9.4 Location Updates

```dart
class DriverLocationUpdateService {
  Timer? _locationTimer;
  
  void startLocationUpdates(String driverId) {
    _locationTimer = Timer.periodic(Duration(seconds: 5), (timer) async {
      // Get current position
      Position position = await Geolocator.getCurrentPosition();
      
      // Update Firestore
      await FirebaseFirestore.instance
        .collection('drivers')
        .doc(driverId)
        .set({
          'lat': position.latitude,
          'lng': position.longitude,
          'status': 'on_trip',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
    });
  }
  
  void stopLocationUpdates() {
    _locationTimer?.cancel();
  }
}
```


---

## 10. File Structure

```
Alert-Mate-master/
│
├── android/                          # Android native code
├── ios/                              # iOS native code
├── web/                              # Web platform files
├── windows/                          # Windows platform files
├── linux/                            # Linux platform files
├── macos/                            # macOS platform files
│
├── assets/
│   └── images/
│       └── Alert Mate New.png        # App logo
│
├── lib/                              # Flutter application code
│   ├── main.dart                     # App entry point
│   ├── auth_screen.dart              # Unified authentication screen
│   ├── firebase_options.dart         # Firebase configuration
│   │
│   ├── constants/
│   │   ├── app_colors.dart           # Color scheme
│   │   └── cloudinary_constants.dart # Cloudinary config
│   │
│   ├── models/                       # Data models
│   │   ├── user.dart                 # User model
│   │   ├── vehicle.dart              # Vehicle model
│   │   ├── driver_location.dart      # Location model
│   │   ├── emergency_contact.dart    # Emergency contact model
│   │   ├── driver_document_submission.dart
│   │   ├── driver_vehicle_submission.dart
│   │   └── owner_vehicle_submission.dart
│   │
│   ├── services/                     # Business logic layer
│   │   ├── firebase_auth_service.dart           # Authentication
│   │   ├── monitoring_service.dart              # Drowsiness monitoring
│   │   ├── driver_location_service.dart         # Location streaming
│   │   ├── driver_location_update_service.dart  # Location updates
│   │   ├── vehicle_service.dart                 # Vehicle management
│   │   ├── emergency_contact_service.dart       # Emergency contacts
│   │   ├── cloudinary_service.dart              # Image uploads
│   │   ├── driver_document_submission_service.dart
│   │   ├── driver_vehicle_submission_service.dart
│   │   └── owner_vehicle_submission_service.dart
│   │
│   ├── screens/                      # Full-page screens
│   │   ├── splash_screen.dart        # App launch screen
│   │   ├── driver_documents_gate_screen.dart  # Document upload
│   │   └── driver_history_screen.dart         # Trip history
│   │
│   ├── dashboards/                   # Role-based dashboards
│   │   ├── driver_dashboard.dart     # Driver monitoring interface
│   │   ├── passenger_dashboard.dart  # Passenger tracking interface
│   │   ├── owner_dashboard.dart      # Fleet management interface
│   │   └── admin_dashboard.dart      # Admin management interface
│   │
│   ├── widgets/                      # Reusable UI components
│   │   └── [various widgets]
│   │
│   └── utils/                        # Utility functions
│       └── page_transitions.dart     # Custom page transitions
│
├── python/                           # Python backend
│   ├── backend.py                    # FastAPI server
│   ├── Testing.py                    # Standalone testing script
│   ├── detector.py                   # Detection utilities
│   ├── drowsiness_model.pth.zip      # Trained model weights
│   └── face_landmarker.task          # MediaPipe model
│
├── pubspec.yaml                      # Flutter dependencies
├── firebase.json                     # Firebase configuration
├── firestore.rules                   # Firestore security rules
├── database.rules.json               # Realtime DB security rules
├── README.md                         # Basic project info
├── PROJECT_OVERVIEW.md               # High-level overview
└── COMPLETE_PROJECT_DOCUMENTATION.md # This file
```


---

## 11. Setup & Configuration

### 11.1 Prerequisites

- **Flutter SDK**: 3.9.2 or higher
- **Dart SDK**: Included with Flutter
- **Python**: 3.8 or higher
- **Firebase Project**: With Authentication, Firestore, Realtime Database, and Storage enabled
- **Android Studio** or **Xcode** (for mobile development)
- **ngrok** (for WebSocket tunneling during development)

### 11.2 Firebase Setup

#### Step 1: Create Firebase Project
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create new project: "alertmate-26d10"
3. Enable Google Analytics (optional)

#### Step 2: Enable Services
```
Authentication:
  - Enable Email/Password provider
  
Firestore Database:
  - Create database in production mode
  - Deploy firestore.rules
  
Realtime Database:
  - Create database (region: asia-southeast1)
  - Deploy database.rules.json
  
Storage:
  - Create default bucket
  - Set up CORS rules
```

#### Step 3: Add Apps
```bash
# Android
flutterfire configure --project=alertmate-26d10 --platforms=android

# iOS
flutterfire configure --project=alertmate-26d10 --platforms=ios

# Web
flutterfire configure --project=alertmate-26d10 --platforms=web
```

#### Step 4: Deploy Security Rules
```bash
# Firestore
firebase deploy --only firestore:rules

# Realtime Database
firebase deploy --only database
```

### 11.3 Flutter Setup

#### Step 1: Install Dependencies
```bash
cd Alert-Mate-master
flutter pub get
```

#### Step 2: Configure Firebase
```bash
# Install FlutterFire CLI
dart pub global activate flutterfire_cli

# Configure Firebase
flutterfire configure
```

#### Step 3: Update Cloudinary Constants
```dart
// lib/constants/cloudinary_constants.dart
class CloudinaryConstants {
  static const String cloudName = 'YOUR_CLOUD_NAME';
  static const String uploadPreset = 'YOUR_UPLOAD_PRESET';
}
```

#### Step 4: Run the App
```bash
# Android
flutter run -d android

# iOS
flutter run -d ios

# Web
flutter run -d chrome
```

### 11.4 Python Backend Setup

#### Step 1: Install Dependencies
```bash
cd Alert-Mate-master/python
pip install fastapi uvicorn opencv-python torch torchvision numpy scipy
```

#### Step 2: Download Model Weights
```bash
# Custom model (already included)
# drowsiness_model.pth.zip

# MediaPipe model (auto-downloads on first run)
# face_landmarker.task
```

#### Step 3: Configure Environment
```bash
# Set detection mode
export DROWSINESS_MODE=custom  # or mediapipe

# Set model paths (optional)
export CUSTOM_MODEL_PATH=drowsiness_model.pth.zip
export MEDIAPIPE_MODEL_PATH=face_landmarker.task
```

#### Step 4: Run the Server
```bash
# Local
python backend.py
# Server runs on http://localhost:8000

# With ngrok (for mobile testing)
ngrok http 8000
# Use ngrok URL in Flutter app
```

#### Step 5: Update Flutter WebSocket URL
```dart
// In driver_dashboard.dart or config file
final wsUrl = 'ws://YOUR_NGROK_URL/ws/monitor';
// or
final wsUrl = 'ws://localhost:8000/ws/monitor';  // for emulator
```

### 11.5 Testing the System

#### Test Driver Flow
```bash
1. Run Python backend: python backend.py
2. Run Flutter app: flutter run
3. Sign up as Driver
4. Verify email
5. Sign in
6. Upload CNIC + License
7. (Admin) Approve documents
8. Start monitoring session
9. Verify WebSocket connection
10. Check real-time metrics
```

#### Test Owner Flow
```bash
1. Sign up as Owner
2. Verify email
3. Sign in
4. Add vehicle with registration
5. (Admin) Approve vehicle
6. Assign driver to vehicle
7. View live tracking
```

#### Test Admin Flow
```bash
1. Sign in with admin credentials
2. Review pending document submissions
3. Approve/reject documents
4. View all drivers and vehicles
5. Monitor system health
```

### 11.6 Common Issues & Solutions

#### Issue: WebSocket Connection Failed
```
Solution:
1. Check if Python backend is running
2. Verify WebSocket URL in Flutter app
3. Check firewall settings
4. Use ngrok for remote testing
```

#### Issue: Camera Permission Denied
```
Solution:
1. Add permissions to AndroidManifest.xml:
   <uses-permission android:name="android.permission.CAMERA"/>
2. Add permissions to Info.plist (iOS):
   <key>NSCameraUsageDescription</key>
   <string>Camera access for drowsiness detection</string>
```

#### Issue: Location Not Updating
```
Solution:
1. Check location permissions
2. Verify GPS is enabled
3. Check Firestore security rules
4. Ensure location service is started
```

#### Issue: Firebase Authentication Error
```
Solution:
1. Verify Firebase project configuration
2. Check firebase_options.dart
3. Ensure Email/Password provider is enabled
4. Clear app data and retry
```


---

## 12. Key Algorithms & Formulas

### 12.1 Distance Calculation
```python
def euclidean_distance(p1, p2):
    """Calculate Euclidean distance between two points"""
    return sqrt((p2.x - p1.x)² + (p2.y - p1.y)²)
```

### 12.2 Eye Aspect Ratio (EAR)
```
EAR = (||p2 - p6|| + ||p3 - p5||) / (2 * ||p1 - p4||)

Where:
  p1, p4 = horizontal eye corners
  p2, p3, p5, p6 = vertical eye points
```

### 12.3 Mouth Aspect Ratio (MAR)
```
MAR = (||upper_mid - lower_mid|| + ||upper_left - lower_left|| + ||upper_right - lower_right||) 
      / (3 * ||left_corner - right_corner||)
```

### 12.4 Alertness Score
```
eye_closure_penalty = (baseline_ear - current_ear) / baseline_ear * 100
mouth_opening_penalty = (current_mar - baseline_mar) / baseline_mar * 30
alertness = max(0, 100 - eye_closure_penalty - mouth_opening_penalty)
```

### 12.5 Adaptive Baseline Update
```
# Exponential Moving Average (EMA)
new_baseline = (1 - alpha) * old_baseline + alpha * current_value

Where:
  alpha = 0.03 (3% weight to new value)
  
# Only update when:
  - Eyes are open (for EAR baseline)
  - Mouth is closed (for MAR baseline)
  - Value is within valid range
```

---

## 13. Security Considerations

### 13.1 Authentication
- Email verification required for all non-admin users
- Password minimum length: 6 characters (Firebase default)
- Admin accounts cannot self-register
- Session tokens expire after 1 hour (Firebase default)

### 13.2 Data Access
- Firestore rules enforce role-based access
- Drivers can only write to their own monitoring data
- Passengers have read-only access
- Admins have full access to all collections

### 13.3 Image Storage
- Documents uploaded to Cloudinary with secure URLs
- Firebase Storage used for additional files
- No sensitive data in image filenames
- Admin approval required before document access

### 13.4 WebSocket Security
- No authentication on WebSocket (development mode)
- Production should implement token-based auth
- Rate limiting recommended for production
- Frame data not persisted on backend

---

## 14. Performance Optimization

### 14.1 Frame Processing
- Frame capture: 500ms interval (2 FPS)
- Image resize: 640x480 before encoding
- JPEG quality: 80% for balance
- Base64 encoding for WebSocket transmission

### 14.2 Database Optimization
- Firestore: Indexed queries on frequently accessed fields
- Realtime DB: Denormalized data for fast reads
- Location updates: 5-second intervals
- Stats updates: Only when drowsiness detected or every 1 second

### 14.3 UI Optimization
- StreamBuilder for real-time updates
- Lazy loading for history lists
- Image caching for documents
- Debouncing for search inputs

---

## 15. Future Enhancements

### Planned Features
1. **Multi-language Support**: Internationalization (i18n)
2. **Voice Alerts**: Text-to-speech warnings
3. **SMS Notifications**: Emergency contact alerts
4. **Route Planning**: Integration with Google Maps
5. **Driver Scoring**: Gamification and leaderboards
6. **Offline Mode**: Local data caching
7. **Advanced Analytics**: ML-based insights
8. **Wearable Integration**: Smartwatch support

### Technical Improvements
1. **WebSocket Authentication**: JWT tokens
2. **Model Optimization**: TensorFlow Lite for on-device inference
3. **Edge Computing**: Process frames on device
4. **CDN Integration**: Faster image delivery
5. **Load Balancing**: Multiple backend instances
6. **Monitoring**: Application performance monitoring (APM)

---

## 16. Glossary

| Term | Definition |
|------|------------|
| **EAR** | Eye Aspect Ratio - metric for eye openness |
| **MAR** | Mouth Aspect Ratio - metric for mouth openness |
| **Landmark** | Specific point on face (e.g., eye corner, nose tip) |
| **Baseline** | Personal average value learned over time |
| **Hysteresis** | Different thresholds for state entry/exit to prevent oscillation |
| **Drowsiness Event** | Instance where driver shows signs of fatigue |
| **Monitoring Session** | Period from "Start" to "Stop" monitoring |
| **Alertness Score** | 0-100 metric indicating driver focus level |
| **WebSocket** | Bidirectional communication protocol |
| **Firestore** | NoSQL document database (persistent) |
| **Realtime DB** | JSON tree database (high-frequency updates) |
| **BaaS** | Backend as a Service (Firebase) |
| **CNN** | Convolutional Neural Network |
| **ResNet** | Residual Network architecture |
| **SE Block** | Squeeze-and-Excitation attention mechanism |

---

## 17. Contact & Support

### Project Information
- **Project Name**: Alert-Mate
- **Version**: 1.0.0
- **Firebase Project**: alertmate-26d10
- **Database Region**: asia-southeast1

### Development Team
- Final year project by Muhammad Wahb and team

### Resources
- [Flutter Documentation](https://docs.flutter.dev/)
- [Firebase Documentation](https://firebase.google.com/docs)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [PyTorch Documentation](https://pytorch.org/docs/)

---

## 18. License & Credits

### Third-Party Libraries
- **Flutter**: BSD 3-Clause License
- **Firebase**: Google Terms of Service
- **FastAPI**: MIT License
- **PyTorch**: BSD-style License
- **OpenCV**: Apache 2.0 License
- **MediaPipe**: Apache 2.0 License

### Model Credits
- Custom CNN architecture inspired by ResNet and SE-Net
- Facial landmark detection based on MediaPipe Face Mesh
- Drowsiness detection algorithm adapted from research papers

---

**Document Version**: 1.0  
**Last Updated**: 2024  
**Generated For**: AI Agents and Developers with Zero Context

---

*This documentation provides a complete overview of the Alert-Mate project. For specific implementation details, refer to the source code in the respective directories.*
