# Location Visibility - Visual Guide

## 🎯 Quick Reference

```
┌─────────────────────────────────────────────────────────────────┐
│                    DRIVER LOCATION VISIBILITY                    │
└─────────────────────────────────────────────────────────────────┘

┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   OFFLINE    │     │     IDLE     │     │   ON_TRIP    │
│              │     │              │     │              │
│  ❌ Not on   │     │  ❌ Not on   │     │  ✅ Visible  │
│     map      │     │     map      │     │    on map    │
└──────────────┘     └──────────────┘     └──────────────┘
```

---

## 📱 Driver Dashboard Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        DRIVER OPENS APP                          │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │  Status: IDLE   │
                    │  🔴 NOT VISIBLE │
                    └────────┬────────┘
                             │
                             │ Clicks "START MONITORING"
                             ▼
                    ┌─────────────────┐
                    │ Status: ON_TRIP │
                    │  🟢 VISIBLE     │
                    └────────┬────────┘
                             │
                             │ Clicks "STOP MONITORING"
                             ▼
                    ┌─────────────────┐
                    │  Status: IDLE   │
                    │  🔴 NOT VISIBLE │
                    └────────┬────────┘
                             │
                             │ Closes App
                             ▼
                    ┌─────────────────┐
                    │ Status: OFFLINE │
                    │  🔴 NOT VISIBLE │
                    └─────────────────┘
```

---

## 🗺️ Map Visibility Across Dashboards

### Admin Dashboard

```
┌─────────────────────────────────────────────────────────────────┐
│                      ADMIN DASHBOARD MAP                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Shows: ALL drivers with status = 'on_trip'                     │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                                                          │  │
│  │    🟢 Driver A (on_trip) ← VISIBLE                      │  │
│  │                                                          │  │
│  │    ⚪ Driver B (idle) ← NOT VISIBLE                     │  │
│  │                                                          │  │
│  │    🟢 Driver C (on_trip) ← VISIBLE                      │  │
│  │                                                          │  │
│  │    ⚪ Driver D (offline) ← NOT VISIBLE                  │  │
│  │                                                          │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Result: Only Driver A and C appear on map                      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Owner Dashboard

```
┌─────────────────────────────────────────────────────────────────┐
│                      OWNER DASHBOARD MAP                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Shows: ASSIGNED drivers with status = 'on_trip'                │
│                                                                  │
│  Owner's Assigned Drivers:                                      │
│  • Driver A (Vehicle ABC-123)                                   │
│  • Driver B (Vehicle XYZ-789)                                   │
│  • Driver C (Vehicle DEF-456)                                   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                                                          │  │
│  │    🟢 Driver A (on_trip) ← VISIBLE                      │  │
│  │                                                          │  │
│  │    ⚪ Driver B (idle) ← NOT VISIBLE                     │  │
│  │                                                          │  │
│  │    🟢 Driver C (on_trip) ← VISIBLE                      │  │
│  │                                                          │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Result: Only Driver A and C appear on map                      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Passenger Dashboard

```
┌─────────────────────────────────────────────────────────────────┐
│                    PASSENGER DASHBOARD MAP                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Shows: SEARCHED driver with status = 'on_trip'                 │
│                                                                  │
│  Passenger searches for: ABC-123                                │
│                                                                  │
│  Scenario 1: Driver is monitoring (on_trip)                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                                                          │  │
│  │    🟢 Driver A (ABC-123) ← VISIBLE                      │  │
│  │       Status: On Trip                                    │  │
│  │       Location updating...                               │  │
│  │                                                          │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Scenario 2: Driver is NOT monitoring (idle)                    │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                                                          │  │
│  │    ⚪ No active drivers                                  │  │
│  │       Driver locations will appear here                  │  │
│  │       when drivers start monitoring                      │  │
│  │                                                          │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔄 Real-time Updates

### When Driver Starts Monitoring

```
Time: 10:00:00 AM
┌─────────────────────────────────────────────────────────────────┐
│  Driver clicks "START MONITORING"                                │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  Firestore Update                                                │
│  drivers/{driverId}                                              │
│  {                                                               │
│    status: "on_trip",  ← Changed from "idle"                    │
│    lat: 31.5204,                                                 │
│    lng: 74.3587,                                                 │
│    updatedAt: 2024-01-15 10:00:00                               │
│  }                                                               │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  Real-time Stream Update (< 1 second)                            │
│                                                                  │
│  Admin Dashboard:  Driver appears on map ✅                      │
│  Owner Dashboard:  Driver appears on map ✅                      │
│  Passenger Dashboard: Driver appears on map ✅                   │
│  Public Tracking: Driver location starts updating ✅             │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### When Driver Stops Monitoring

```
Time: 12:00:00 PM
┌─────────────────────────────────────────────────────────────────┐
│  Driver clicks "STOP MONITORING"                                 │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  Firestore Update                                                │
│  drivers/{driverId}                                              │
│  {                                                               │
│    status: "idle",  ← Changed from "on_trip"                    │
│    drowsinessAlert: false,                                       │
│    updatedAt: 2024-01-15 12:00:00                               │
│  }                                                               │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  Real-time Stream Update (< 1 second)                            │
│                                                                  │
│  Admin Dashboard:  Driver disappears from map ❌                 │
│  Owner Dashboard:  Driver disappears from map ❌                 │
│  Passenger Dashboard: Driver disappears from map ❌              │
│  Public Tracking: Shows "Location Unavailable" ❌                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🎯 Status Comparison

### Before Fix

```
┌──────────────────────────────────────────────────────────────┐
│  Map Query: status != 'offline'                              │
│                                                              │
│  ✅ Shows: idle drivers                                     │
│  ✅ Shows: on_trip drivers                                  │
│  ❌ Hides: offline drivers                                  │
│                                                              │
│  Problem: Drivers visible even when NOT monitoring          │
└──────────────────────────────────────────────────────────────┘
```

### After Fix

```
┌──────────────────────────────────────────────────────────────┐
│  Map Query: status == 'on_trip'                              │
│                                                              │
│  ❌ Hides: idle drivers                                     │
│  ✅ Shows: on_trip drivers                                  │
│  ❌ Hides: offline drivers                                  │
│                                                              │
│  Solution: Drivers only visible when actively monitoring    │
└──────────────────────────────────────────────────────────────┘
```

---

## 📊 Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        DRIVER APP                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  [START MONITORING] Button Clicked                       │  │
│  └────────────────────────────┬─────────────────────────────┘  │
└────────────────────────────────┼────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                  DriverLocationUpdateService                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  goOnTrip(driverId)                                      │  │
│  │  • Updates status to 'on_trip'                           │  │
│  │  • Starts GPS updates (every 10 seconds)                 │  │
│  └────────────────────────────┬─────────────────────────────┘  │
└────────────────────────────────┼────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                        FIRESTORE                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Collection: drivers                                     │  │
│  │  Document: {driverId}                                    │  │
│  │  {                                                       │  │
│  │    status: "on_trip",  ← UPDATED                        │  │
│  │    lat: 31.5204,                                         │  │
│  │    lng: 74.3587,                                         │  │
│  │    updatedAt: timestamp                                  │  │
│  │  }                                                       │  │
│  └────────────────────────────┬─────────────────────────────┘  │
└────────────────────────────────┼────────────────────────────────┘
                                 │
                                 │ Real-time Stream
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                  DriverLocationService                           │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Query: .where('status', isEqualTo: 'on_trip')          │  │
│  │  • Filters at database level                            │  │
│  │  • Only returns on_trip drivers                         │  │
│  └────────────────────────────┬─────────────────────────────┘  │
└────────────────────────────────┼────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                        LIVE MAP                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  • Receives only on_trip drivers                         │  │
│  │  • Displays markers on map                               │  │
│  │  • Updates in real-time                                  │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## ✅ Testing Scenarios

### Scenario 1: Single Driver

```
Step 1: Driver logs in
┌──────────────────────────────────────┐
│ Driver Dashboard: Status = idle      │
│ Admin Map: ❌ Driver NOT visible     │
└──────────────────────────────────────┘

Step 2: Driver starts monitoring
┌──────────────────────────────────────┐
│ Driver Dashboard: Status = on_trip   │
│ Admin Map: ✅ Driver IS visible      │
└──────────────────────────────────────┘

Step 3: Driver stops monitoring
┌──────────────────────────────────────┐
│ Driver Dashboard: Status = idle      │
│ Admin Map: ❌ Driver NOT visible     │
└──────────────────────────────────────┘
```

### Scenario 2: Multiple Drivers

```
Initial State:
┌──────────────────────────────────────┐
│ Driver A: idle                       │
│ Driver B: on_trip                    │
│ Driver C: idle                       │
│ Driver D: on_trip                    │
│                                      │
│ Admin Map Shows:                     │
│ • Driver B ✅                        │
│ • Driver D ✅                        │
└──────────────────────────────────────┘

Driver A starts monitoring:
┌──────────────────────────────────────┐
│ Driver A: on_trip ← Changed          │
│ Driver B: on_trip                    │
│ Driver C: idle                       │
│ Driver D: on_trip                    │
│                                      │
│ Admin Map Shows:                     │
│ • Driver A ✅ (NEW)                  │
│ • Driver B ✅                        │
│ • Driver D ✅                        │
└──────────────────────────────────────┘

Driver B stops monitoring:
┌──────────────────────────────────────┐
│ Driver A: on_trip                    │
│ Driver B: idle ← Changed             │
│ Driver C: idle                       │
│ Driver D: on_trip                    │
│                                      │
│ Admin Map Shows:                     │
│ • Driver A ✅                        │
│ • Driver D ✅                        │
└──────────────────────────────────────┘
```

---

## 🎉 Summary

✅ **Drivers only visible when monitoring is active**
✅ **Real-time updates (< 1 second)**
✅ **Works across all dashboards**
✅ **Better privacy and performance**
