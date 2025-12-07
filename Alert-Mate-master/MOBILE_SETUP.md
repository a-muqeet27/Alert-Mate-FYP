# Mobile Setup Guide for Alert-Mate

## Overview
The Alert-Mate app **can run on mobile devices**, but requires some configuration changes because the Python backend cannot run directly on mobile devices.

## Architecture

```
┌─────────────────┐         WebSocket          ┌──────────────────┐
│  Mobile Device  │ ◄─────────────────────────► │  Python Backend  │
│  (Flutter App)  │                              │  (Server/PC)     │
└─────────────────┘                              └──────────────────┘
```

## Setup Requirements

### 1. Python Backend Server
The Python backend (`backend.py`) **must run on a separate machine**:
- Your development computer
- A cloud server (AWS, Google Cloud, etc.)
- A local server on your network

**The backend cannot run on the mobile device itself.**

### 2. Network Configuration

#### For Android Emulator:
- Uses `ws://10.0.2.2:8000/ws/monitor` (already configured)
- `10.0.2.2` is a special IP that points to the host machine

#### For Physical Android Device:
1. Find your computer's local IP address:
   - Windows: Run `ipconfig` in CMD, look for "IPv4 Address"
   - Mac/Linux: Run `ifconfig` or `ip addr`
   - Example: `192.168.1.50`

2. Update `driver_dashboard.dart`:
   ```dart
   const String serverIp = '192.168.1.50'; // Your computer's IP
   return 'ws://$serverIp:8000/ws/monitor';
   ```

3. Ensure both devices are on the same Wi-Fi network

#### For iOS Simulator:
- Uses `ws://localhost:8000/ws/monitor` (already configured)

#### For Physical iOS Device:
- Same as Android physical device - use your computer's LAN IP

### 3. Running the Backend Server

1. Navigate to the Python directory:
   ```bash
   cd Alert-Mate-master/python
   ```

2. Install dependencies:
   ```bash
   pip install fastapi uvicorn opencv-python torch torchvision pillow numpy
   ```

3. Start the server:
   ```bash
   python backend.py
   ```
   Or:
   ```bash
   uvicorn backend:app --host 0.0.0.0 --port 8000
   ```

4. The server should be accessible at:
   - `http://YOUR_IP:8000` (from mobile device)
   - `http://localhost:8000` (from same machine)

### 4. Firewall Configuration

**Windows:**
- Allow Python through Windows Firewall
- Or allow port 8000

**Mac/Linux:**
- Allow incoming connections on port 8000

### 5. Testing Connection

1. Start the backend server on your computer
2. From your mobile device's browser, try:
   - `http://YOUR_COMPUTER_IP:8000`
   - You should see: `{"status":"FastAPI Drowsiness Detection Server Running"}`

3. If it works, the Flutter app will connect successfully

## Deployment Options

### Option 1: Local Development (Current Setup)
- Backend runs on your computer
- Mobile device connects via local network
- **Best for:** Development and testing

### Option 2: Cloud Deployment
- Deploy backend to AWS, Google Cloud, Azure, etc.
- Update WebSocket URL to cloud server address
- **Best for:** Production use

### Option 3: Edge Device
- Run backend on a Raspberry Pi or similar device
- Keep it in the vehicle
- **Best for:** Real-world deployment

## Important Notes

1. **Camera Access:**
   - ✅ Android: Permissions already configured
   - ✅ iOS: Permissions added to Info.plist

2. **Network Security:**
   - ✅ Android: `usesCleartextTraffic="true"` added for HTTP connections
   - ⚠️ For production, use HTTPS/WSS instead of HTTP/WS

3. **Python Process:**
   - The `_launchPythonMonitor()` function won't work on mobile
   - The app uses WebSocket connection instead (which is correct)

4. **Firebase:**
   - ✅ Already configured for mobile
   - Works on both Android and iOS

## Troubleshooting

### "Connection refused" or "Failed to connect"
- Check if backend server is running
- Verify IP address is correct
- Ensure both devices are on same network
- Check firewall settings

### "Camera not working"
- Check app permissions in device settings
- For iOS: Ensure Info.plist has camera permission description

### "WebSocket connection failed"
- Verify backend is accessible from mobile device's browser
- Check if port 8000 is open
- Try using `http://` instead of `ws://` in browser first

## Summary

✅ **The app WILL run on mobile** with these configurations:
- Backend server running on separate machine
- Correct IP address configured
- Both devices on same network
- Firewall allows connections

The Flutter app itself is fully mobile-compatible!


