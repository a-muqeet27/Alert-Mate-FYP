# Live Location Tracking - System Architecture

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        ALERT-MATE SYSTEM                         │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      PASSENGER DASHBOARD                         │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  1. Search Vehicle by License Plate                      │  │
│  │  2. View Vehicle Details                                 │  │
│  │  3. Click "Share Live Location" Button                   │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                      TRACKING SERVICE                            │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  • Generate 8-character token (e.g., "a3x9k2m7")        │  │
│  │  • Create token document in Firestore                    │  │
│  │  • Set expiry time (6 hours from now)                    │  │
│  │  • Return token ID                                       │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                         FIRESTORE                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Collection: tracking_tokens                             │  │
│  │  Document: a3x9k2m7                                      │  │
│  │  {                                                       │  │
│  │    driverId: "driver123",                               │  │
│  │    vehiclePlate: "ABC-1234",                            │  │
│  │    vehicleMake: "Toyota",                               │  │
│  │    vehicleModel: "Corolla",                             │  │
│  │    createdAt: 1234567890,                               │  │
│  │    expiresAt: 1234589490,  // +6 hours                 │  │
│  │    isActive: true                                       │  │
│  │  }                                                       │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                      SHARE MECHANISM                             │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  URL: https://yourapp.com/track/a3x9k2m7                │  │
│  │                                                          │  │
│  │  Message:                                                │  │
│  │  🚗 Track vehicle ABC-1234 LIVE:                        │  │
│  │  https://yourapp.com/track/a3x9k2m7                     │  │
│  │                                                          │  │
│  │  📍 Real-time location updates                          │  │
│  │  ⏱️ Valid for 6 hours                                   │  │
│  │  🔄 Updates every 10 seconds                            │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────┐              ┌──────────────┐                │
│  │  WhatsApp    │              │     SMS      │                │
│  │  (Primary)   │              │  (Fallback)  │                │
│  └──────────────┘              └──────────────┘                │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    RECIPIENT OPENS LINK                          │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Browser navigates to:                                   │  │
│  │  https://yourapp.com/track/a3x9k2m7                     │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                      ROUTE HANDLER (main.dart)                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  onGenerateRoute: (settings) {                          │  │
│  │    if (settings.name.startsWith('/track/')) {           │  │
│  │      final tokenId = settings.name.substring(7);        │  │
│  │      return PublicLiveTrackingScreen(tokenId);          │  │
│  │    }                                                     │  │
│  │  }                                                       │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                PUBLIC LIVE TRACKING SCREEN                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Step 1: Validate Token                                 │  │
│  │  • Fetch token from Firestore                           │  │
│  │  • Check if exists                                      │  │
│  │  • Check if expired                                     │  │
│  │  • Check if active                                      │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Step 2: Stream Driver Location                         │  │
│  │  • Get driverId from token                              │  │
│  │  • Stream from drivers/{driverId}                       │  │
│  │  • Extract lat, lng, status, drowsinessAlert           │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Step 3: Display UI                                     │  │
│  │  • Vehicle info card                                    │  │
│  │  • Status indicators                                    │  │
│  │  • Countdown timer                                      │  │
│  │  • Live map with marker                                 │  │
│  │  • Coordinates display                                  │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                      REAL-TIME UPDATES                           │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Every 10 seconds:                                       │  │
│  │  1. Driver app updates location in Firestore            │  │
│  │  2. Firestore triggers snapshot listener                │  │
│  │  3. Public tracking screen receives update              │  │
│  │  4. Map marker moves to new position                    │  │
│  │  5. Coordinates update                                   │  │
│  │  6. Status indicators refresh                            │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔄 Data Flow Diagram

```
┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│Passenger │────▶│ Tracking │────▶│Firestore │────▶│WhatsApp/ │
│Dashboard │     │ Service  │     │          │     │   SMS    │
└──────────┘     └──────────┘     └──────────┘     └──────────┘
                                        │
                                        │ Stream
                                        ▼
┌──────────┐     ┌──────────┐     ┌──────────┐
│Recipient │────▶│ Public   │◀────│Firestore │
│ Browser  │     │ Tracking │     │          │
└──────────┘     └──────────┘     └──────────┘
                      │
                      │ Stream
                      ▼
                 ┌──────────┐
                 │ Driver   │
                 │ Location │
                 └──────────┘
```

---

## 🗄️ Database Schema

### Collection: `tracking_tokens`

```javascript
{
  // Document ID: 8-character token (e.g., "a3x9k2m7")
  "driverId": "string",           // Reference to driver
  "vehiclePlate": "string",       // License plate number
  "vehicleMake": "string",        // Vehicle manufacturer
  "vehicleModel": "string",       // Vehicle model
  "createdAt": number,            // Timestamp (milliseconds)
  "expiresAt": number,            // Timestamp (milliseconds)
  "isActive": boolean             // Token status
}
```

**Indexes Required:**
- `driverId` (for querying driver's tokens)
- `expiresAt` (for cleanup queries)
- `isActive` (for filtering active tokens)

**Security Rules:**
```javascript
match /tracking_tokens/{tokenId} {
  allow read: if true;                    // Public read
  allow create: if request.auth != null;  // Authenticated write
  allow update, delete: if request.auth != null 
                        && request.auth.uid == resource.data.driverId;
}
```

---

## 🔐 Security Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      SECURITY LAYERS                             │
└─────────────────────────────────────────────────────────────────┘

Layer 1: Token-Based Access
├─ Unique 8-character tokens
├─ No authentication required for viewing
├─ Token acts as temporary access key
└─ Cannot guess or enumerate tokens

Layer 2: Time-Limited Access
├─ 6-hour expiry by default
├─ Automatic deactivation after expiry
├─ Cannot extend expired tokens
└─ Must create new token for continued access

Layer 3: Firestore Security Rules
├─ Public read access (for tracking)
├─ Authenticated write access (for creation)
├─ Owner-only update/delete
└─ Server-side validation

Layer 4: Data Minimization
├─ Only essential data in token
├─ No personal information exposed
├─ No driver contact details
└─ Location data only (no history)

Layer 5: Automatic Cleanup
├─ Expired tokens deactivated
├─ Periodic cleanup job available
├─ Storage optimization
└─ Cost control
```

---

## 📊 Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         FRONTEND                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────────┐         ┌────────────────────┐         │
│  │ Passenger Dashboard│         │ Public Tracking    │         │
│  │                    │         │ Screen             │         │
│  │ • Search vehicle   │         │ • Validate token   │         │
│  │ • Create token     │         │ • Stream location  │         │
│  │ • Share link       │         │ • Display map      │         │
│  └────────┬───────────┘         └────────┬───────────┘         │
│           │                              │                      │
└───────────┼──────────────────────────────┼──────────────────────┘
            │                              │
            ▼                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         SERVICES                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────────┐         ┌────────────────────┐         │
│  │ TrackingService    │         │ VehicleService     │         │
│  │                    │         │                    │         │
│  │ • createToken()    │         │ • searchByPlate()  │         │
│  │ • getToken()       │         │ • getVehicle()     │         │
│  │ • streamToken()    │         │ • getDriver()      │         │
│  │ • streamLocation() │         │                    │         │
│  │ • deactivateToken()│         │                    │         │
│  │ • cleanupExpired() │         │                    │         │
│  └────────┬───────────┘         └────────┬───────────┘         │
│           │                              │                      │
└───────────┼──────────────────────────────┼──────────────────────┘
            │                              │
            ▼                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         MODELS                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────────┐         ┌────────────────────┐         │
│  │ TrackingToken      │         │ Vehicle            │         │
│  │                    │         │                    │         │
│  │ • id               │         │ • licensePlate     │         │
│  │ • driverId         │         │ • make             │         │
│  │ • vehiclePlate     │         │ • model            │         │
│  │ • vehicleMake      │         │ • driverId         │         │
│  │ • vehicleModel     │         │                    │         │
│  │ • createdAt        │         │                    │         │
│  │ • expiresAt        │         │                    │         │
│  │ • isActive         │         │                    │         │
│  │ • isExpired        │         │                    │         │
│  │ • timeRemaining    │         │                    │         │
│  └────────────────────┘         └────────────────────┘         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────────────┐
│                       FIREBASE                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────────┐         ┌────────────────────┐         │
│  │ Firestore          │         │ Hosting            │         │
│  │                    │         │                    │         │
│  │ • tracking_tokens  │         │ • Web app          │         │
│  │ • drivers          │         │ • Static assets    │         │
│  │ • vehicles         │         │ • CDN              │         │
│  │ • users            │         │                    │         │
│  └────────────────────┘         └────────────────────┘         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔄 State Management

### Passenger Dashboard State
```dart
class _PassengerDashboardState {
  // Vehicle lookup
  Vehicle? _lookupVehicle;
  String? _lookupDriverId;
  bool _isSearchingPlate;
  
  // Services
  TrackingService _trackingService;
  VehicleService _vehicleService;
}
```

### Public Tracking Screen State
```dart
class _PublicLiveTrackingScreenState {
  // Token validation
  Stream<TrackingToken?> tokenStream;
  
  // Location streaming
  Stream<Map<String, dynamic>?> locationStream;
  
  // UI updates
  Timer _expiryTimer;  // Updates countdown every second
}
```

---

## 🌐 Network Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         CLIENT                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Flutter Web App                                         │  │
│  │  • Passenger Dashboard                                   │  │
│  │  • Public Tracking Screen                                │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             │ HTTPS
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                      FIREBASE HOSTING                            │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  • CDN (Content Delivery Network)                        │  │
│  │  • SSL/TLS Certificates                                  │  │
│  │  • Static Asset Serving                                  │  │
│  │  • Routing (/track/:tokenId)                             │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             │ WebSocket
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                      FIREBASE FIRESTORE                          │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  • Real-time Database                                    │  │
│  │  • Security Rules Engine                                 │  │
│  │  • Query Engine                                          │  │
│  │  • Snapshot Listeners                                    │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📈 Scalability Considerations

### Current Capacity (Free Tier)
- **23 tokens/day** (within free tier)
- **~690 tokens/month**
- **Unlimited concurrent viewers** per token

### Scaling Options

#### Option 1: Optimize Token Duration
```dart
// Reduce from 6 hours to 3 hours
duration: const Duration(hours: 3)
// Result: 46 tokens/day capacity
```

#### Option 2: Reduce Update Frequency
```dart
// Increase from 10 seconds to 30 seconds
// Result: 3x capacity increase
```

#### Option 3: Upgrade Firebase Plan
- **Spark (Free)**: 50K reads/day
- **Blaze (Pay-as-you-go)**: $0.06 per 100K reads
- **Cost**: ~$1.30 per 1000 tokens

---

## 🎯 Performance Metrics

### Target Metrics
- **Token Creation**: < 2 seconds
- **Page Load**: < 3 seconds
- **Location Update Latency**: < 1 second
- **Map Render Time**: < 2 seconds

### Monitoring Points
1. Token creation time
2. Firestore query latency
3. WebSocket connection time
4. Map initialization time
5. Location update frequency

---

## ✨ Summary

This architecture provides:

✅ **Scalable**: Handles multiple concurrent users
✅ **Secure**: Multi-layer security approach
✅ **Cost-effective**: Optimized for free tier
✅ **Maintainable**: Clean separation of concerns
✅ **Extensible**: Easy to add new features
✅ **Reliable**: Real-time updates with error handling
