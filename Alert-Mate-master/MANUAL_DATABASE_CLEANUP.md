# Manual Database Cleanup - Required

## 🚨 IMPORTANT: One-Time Manual Cleanup Required

The passenger dashboard is still showing stale data because there's old `current_stats` data in Firebase Realtime Database from previous monitoring sessions. This data needs to be manually cleared once.

---

## 🔧 Option 1: Clear via Firebase Console (Recommended)

### Steps:

1. **Open Firebase Console**
   - Go to https://console.firebase.google.com
   - Select your project: `alertmate-26d10`

2. **Navigate to Realtime Database**
   - Click "Realtime Database" in the left sidebar
   - You should see the database URL: `https://alertmate-26d10-default-rtdb.asia-southeast1.firebasedatabase.app`

3. **Find and Delete current_stats**
   - Navigate to: `drivers` → `{driverId}` → `current_stats`
   - Click on `current_stats` node
   - Click the **trash icon** (🗑️) to delete
   - Confirm deletion

4. **Repeat for All Drivers**
   - If you have multiple drivers, repeat step 3 for each driver
   - Or delete the entire `drivers` node and let it recreate (this will also clear monitoring_sessions and history)

5. **Verify Deletion**
   - Refresh the database view
   - Confirm `current_stats` nodes are gone

---

## 🔧 Option 2: Clear via Code (One-Time Script)

Create a temporary cleanup function and run it once:

### Add to driver_dashboard.dart (temporarily):

```dart
// Add this method temporarily
Future<void> _cleanupAllCurrentStats() async {
  try {
    final driverId = widget.user.id;
    if (driverId != null) {
      await _monitoringService.clearCurrentStats(driverId);
      print('✅ Cleaned up current_stats for driver $driverId');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Database cleaned up successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  } catch (e) {
    print('❌ Cleanup error: $e');
  }
}
```

### Add a temporary button in the UI:

```dart
// Add this button temporarily in the driver dashboard
ElevatedButton(
  onPressed: _cleanupAllCurrentStats,
  child: const Text('CLEANUP DATABASE (ONE-TIME)'),
),
```

### Run the cleanup:
1. Restart the app completely
2. Login as driver
3. Click the "CLEANUP DATABASE" button
4. Remove the button and method after cleanup

---

## 🔧 Option 3: Clear via Firebase CLI

If you have Firebase CLI installed:

```bash
# Install Firebase CLI (if not installed)
npm install -g firebase-tools

# Login
firebase login

# Delete current_stats for a specific driver
firebase database:remove /drivers/{driverId}/current_stats --project alertmate-26d10

# Or delete all current_stats
firebase database:remove /drivers --project alertmate-26d10
```

---

## ✅ After Cleanup

Once you've cleared the old data:

1. **Stop the app completely**
   ```bash
   # In terminal, press Ctrl+C to stop
   ```

2. **Clean and rebuild**
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```

3. **Test the fix**
   - Login as passenger
   - Search for vehicle (driver should NOT be monitoring)
   - **Expected**: Shows "Monitoring Not Started" message
   - **Expected**: No "Normal" or "Safe" status

4. **Test monitoring flow**
   - Driver clicks "START MONITORING"
   - Passenger dashboard should show live status
   - Driver clicks "STOP MONITORING"
   - Passenger dashboard should immediately show "Monitoring Not Started"

---

## 🔍 Verify the Fix is Working

### Check Firebase Realtime Database:

**Before driver starts monitoring:**
```
drivers/
  {driverId}/
    current_stats/  ← Should NOT exist
```

**After driver starts monitoring:**
```
drivers/
  {driverId}/
    current_stats/  ← Should exist with live data
      alertness: 85.5
      drowsinessDetected: false
      lastUpdate: 1234567890
```

**After driver stops monitoring:**
```
drivers/
  {driverId}/
    current_stats/  ← Should be DELETED
```

---

## 🐛 If Still Not Working

### Check 1: Verify code changes were applied

```bash
# Check if clearCurrentStats method exists
grep -n "clearCurrentStats" Alert-Mate-master/lib/services/monitoring_service.dart

# Check if it's being called in driver dashboard
grep -n "clearCurrentStats" Alert-Mate-master/lib/dashboards/driver_dashboard.dart
```

### Check 2: Verify app was fully restarted

- Hot reload (R) is NOT enough
- Hot restart (Shift+R) is NOT enough
- Must do: Stop app → `flutter run`

### Check 3: Check console logs

When driver stops monitoring, you should see:
```
🛑 Stopping monitoring...
✅ Firebase session ended: {sessionId}
✅ Current stats cleared from Realtime Database  ← This line is critical
✅ DriverLocationUpdateService: driver {driverId} status → idle
✅ Monitoring stopped successfully
```

If you don't see "Current stats cleared", the new code isn't running.

### Check 4: Verify Firestore status

Open Firebase Console → Firestore → drivers → {driverId}

**When driver is NOT monitoring:**
```
{
  status: "idle",  ← Should be "idle" or "offline"
  ...
}
```

**When driver IS monitoring:**
```
{
  status: "on_trip",  ← Should be "on_trip"
  ...
}
```

---

## 📋 Quick Checklist

- [ ] Cleared old `current_stats` from Realtime Database (Option 1, 2, or 3)
- [ ] Stopped the app completely (Ctrl+C)
- [ ] Ran `flutter clean`
- [ ] Ran `flutter pub get`
- [ ] Ran `flutter run` (full restart)
- [ ] Tested passenger dashboard with driver NOT monitoring
- [ ] Verified "Monitoring Not Started" message appears
- [ ] Tested driver START MONITORING → passenger sees live status
- [ ] Tested driver STOP MONITORING → passenger sees "Monitoring Not Started"

---

## 🎯 Root Cause Summary

The issue persists because:

1. ✅ **Code is correct** - Changes were properly applied
2. ❌ **Old data exists** - Previous sessions left `current_stats` in database
3. ❌ **App not fully restarted** - Hot reload doesn't load new code
4. ❌ **Database not cleaned** - Old data still being read by passenger dashboard

**Solution:** Clear the database manually (one-time) + Full app restart

---

## 🎉 Expected Result After Fix

### Passenger Dashboard - Driver NOT Monitoring:
```
┌─────────────────────────────────────────┐
│ Vehicle & Driver                        │
│ • Driver: Wahb Usman                    │
│ • Vehicle: Changan Alsvin               │
│ • License Plate: ABC-123                │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ ℹ️ Monitoring Not Started               │
│                                         │
│ Driver has not started monitoring       │
│ session yet. Live status will appear    │
│ when driver clicks "START MONITORING".  │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ Trip Information                        │
│                                         │
│ No active monitoring session.           │
└─────────────────────────────────────────┘
```

No "Normal" or "Safe" status should be visible!
