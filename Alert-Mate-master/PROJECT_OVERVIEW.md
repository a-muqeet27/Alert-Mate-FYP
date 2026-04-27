# Alert-Mate: Project Overview

This document provides a comprehensive overview of the **Alert-Mate** application, detailing its architecture, tech stack, concepts, workflows, and features.

## 1. Introduction
**Alert-Mate** is a safety-oriented transport and vehicle monitoring application primarily focused on **Driver Drowsiness Detection**. It continuously monitors a driver's face during a trip to detect signs of fatigue (like yawning or prolonged eye closure) and alerts the driver. The application also provides role-based dashboards to allow Vehicle Owners, Passengers, and Admins to track vehicles and driver statuses in real-time.

## 2. Tech Stack

### Frontend & Mobile App
*   **Framework:** Flutter (uses Dart)
*   **Design:** Material Design (`uses-material-design: true`), Custom Theme Colors
*   **Maps & Location:** `flutter_map`, `latlong2`, `geolocator` (for live driver tracking)
*   **Hardware Interfacing:** `camera` (for capturing driver frames), `permission_handler`

### Backend Services (BaaS)
*   **Authentication:** Firebase Auth (Email/password validation, Sign-in/Sign-up)
*   **Database:** 
    *   **Cloud Firestore:** Used for persistent data like User Profiles, Vehicles, Emergency Contacts, and roles.
    *   **Firebase Realtime Database:** Used for high-frequency, low-latency updates such as live GPS tracking and live monitoring statistics (alertness score, events).
*   **Storage:** Firebase Storage & Cloudinary (used for driver documents like CNIC, License, and vehicle images).

### Machine Learning / Processing Backend
*   **Python (FastAPI / WebSockets):** A Python-based backend that receives base64 camera frames via WebSockets (`web_socket_channel`).
*   **Computer Vision Models:** Uses custom `.pth` (landmark detector) and `.pkl` (drowsiness classifier) models to analyze frames for facial landmarks.

## 3. Core Concepts

*   **EAR (Eye Aspect Ratio):** A metric calculated from facial landmarks to determine if the eyes are open or closed. If EAR falls below a threshold, the system flags eye closure.
*   **MAR (Mouth Aspect Ratio):** A metric to determine the state of the mouth. Elevated MAR indicates yawning.
*   **Alertness Score:** An aggregate percentage reflecting the driver's focus, affected dynamically by the EAR and MAR over time.
*   **Roles & Hierarchy:** The platform isolates functionality based on strict roles: Drivers generate the data, Owners manage the assets, Passengers consume specific data, and Admins oversee everything.

## 4. User Roles, Features & Flows

### 4.1. Driver
**Flow:** Sign Up -> Upload Documents (CNIC/License) -> Admin Approval -> Assign Vehicle (Optional depending on model) -> Start Trip.
**Features:**
*   **Dashboard:** Primary interface while driving.
*   **Drowsiness Monitoring:** When a trip starts, the app accesses the front camera and streams frames to the Python backend. If drowsy (yawning/eyes closed), an audio buzzer plays and a UI alert is displayed.
*   **Emergency Contacts:** Can define emergency contacts who can be notified in case of critical events.
*   **History:** Can view past trips, average alertness scores, and drowsiness events.

### 4.2. Vehicle Owner
**Flow:** Sign Up -> Add Vehicles -> View Dashboard.
**Features:**
*   **Fleet Management:** Add and manage owned vehicles (Submitting vehicle registration docs).
*   **Driver Association:** Can link drivers to their registered vehicles.
*   **Tracking:** View live locations and alertness statuses of drivers currently operating their vehicles.

### 4.3. Passenger
**Flow:** Sign Up -> Dashboard -> Search/Track Vehicle.
**Features:**
*   **Live Tracking:** Using a specific vehicle identifier (like license plate), the passenger can view the live location of their assigned driver/vehicle on the map.

### 4.4. Admin
**Flow:** Sign In (No public sign-up, credentials pre-provided).
**Features:**
*   **Verification Gate:** Reviews and approves driver documents (CNIC/Licenses) and Vehicle Registration documents.
*   **Global Overview:** Views all active drivers, all vehicles, system health, and handles user management.

## 5. Drowsiness Detection Flow (Under the Hood)

1.  **Session Start:** The driver taps "Start Monitoring". The Flutter app requests camera permission and connects to the Python backend via a **WebSocket** connection (often tunneled via ngrok during development, see `AppConfig.wsMonitorUrl`).
2.  **Streaming:** The Flutter app's `DriverDashboard` uses a timer to capture pictures (frames) every 500ms, converts them to base64, and sends them through the socket.
3.  **Processing:** The Python server runs the frame through the `landmark_detector` and `drowsiness_classifier`. It calculates EAR, MAR, and overall alertness.
4.  **Feedback Loop:** The server streams JSON back to Flutter with the stats (`alertness`, `ear`, `mar`, `isDrowsy`, `reason`).
5.  **Action:** 
    *   If `reason == 'yawning'` for 5-7 consecutive frames, a loud system sound (buzzer) plays to wake the driver.
    *   Flutter saves these stats to the **Firebase Realtime Database** so Admins and Owners can see live updates.

## 6. Live Tracking & Data Sync

*   **LocationService:** The app hooks into device GPS (`geolocator`). As the driver moves, coordinates are pushed to the Firebase Realtime Database.
*   **Realtime Nodes:**
    *   `drivers/${driverId}/current_stats`: Holds the immediate alertness %.
    *   `locations`: Holds the active GPS coordinates. 
*   **Maps Integration:** The Owner/Admin dashboards listen to these Firebase streams and plot markers on a `flutter_map`. If the `drowsinessDetected` flag is true, the marker might show up as red indicating the driver is sleeping or highly fatigued.

## 7. App Structure and Architecture

Located in `lib/`:
*   `main.dart`: Initialization of Firebase and the App theme. Routes to the Splash Screen.
*   `auth_screen.dart`: A centralized authentication screen managing state for all 4 roles using an animation-rich interface.
*   `dashboards/`: Contains the isolated dashboards for each role (`driver_dashboard.dart`, `owner_dashboard.dart`, etc.) Ensure separation of concerns.
*   `models/`: Dart data classes mapping to JSON/Firestore documents (e.g., `User`, `Vehicle`, `EmergencyContact`).
*   `services/`: Business logic and database interaction layer. E.g., `firebase_auth_service.dart`, `monitoring_service.dart` (handles stats and sessions), `driver_location_update_service.dart`.
*   `screens/`: Supplementary views like history, document upload panels, or splash screens.
*   `widgets/`: Reusable UI components.

## Summary
Alert-Mate elegantly combines real-time streaming, edge-assisted machine learning, and strict role-based data synchronization to create an end-to-end safety platform for the transportation sector.
