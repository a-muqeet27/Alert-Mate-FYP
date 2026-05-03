# 🔧 Fix Instructions - Follow These Steps

## ⚠️ The Issue

The passenger dashboard is showing stale "Normal" and "Safe" status because there's old data in Firebase Realtime Database that needs to be cleared.

---

## ✅ Solution - Follow These Steps IN ORDER

### Step 1: Stop the App Completely

```bash
# In your terminal where the app is running, press:
Ctrl + C

# Wait for the app to fully stop
```

### Step 2: Clean and Rebuild

```bash
cd Alert-Mate-master
flutter clean
flutter pub get
flutter run
```

### Step 3: Run the Cleanup (ONE-TIME)

1. **Login as Driver** (Wahb Usman)
2. **Look for the orange button** that says "CLEANUP DATABASE (ONE-TIME)"
3. **Click the button**
4. **Wait for success message**: "✅ Database cleaned up! Old data removed."

### Step 4: Test the Fix

1. **Logout from driver account**
2. **Login as Passenger** (Abdul Muqeet)
3. **Search for vehicle**: abc123
4. **Expected Result**: Should show "Monitoring Not Started" message
5. **Should NOT show**: "Normal" or "Safe" status

### Step 5: Test Monitoring Flow

1. **Login as Driver** again
2. **Click "START MONITORING"**
3. **Switch to Passenger dashboard**
4. **Expected**: Live status should appear (Normal/Drowsy)
5. **Switch back to Driver**
6. **Click "STOP MONITORING"**
7. **Switch to Passenger dashboard**
8. **Expected**: Should immediately show "Monitoring Not Started"

### Step 6: Remove the Cleanup Button (After Successful Test)

Once everything works, remove the temporary cleanup button:

1. Open `Alert-Mate-master/lib/dashboards/driver_dashboard.dart`
2. Find the section with comment: `// TEMPORARY: One-time database cleanup button`
3. Delete the entire `SizedBox` block (lines ~1185-1225)
4. Save the file

---

## 🎯 What Each Step Does

### Step 1: Stop the App
- Ensures no old code is running
- Clears memory cache

### Step 2: Clean and Rebuild
- `flutter clean` removes all build artifacts
- `flutter pub get` ensures dependencies are up to date
- `flutter run` builds and runs with new code

### Step 3: Run Cleanup
- Removes old `current_stats` from Firebase Realtime Database
- This is a ONE-TIME operation
- After this, the new code will automatically manage the data

### Step 4-5: Test
- Verifies the fix is working correctly
- Ensures real-time updates work

### Step 6: Cleanup Code
- Removes the temporary button
- Keeps codebase clean

---

## 📋 Quick Checklist

- [ ] Stopped app completely (Ctrl+C)
- [ ] Ran `flutter clean`
- [ ] Ran `flutter pub get`
- [ ] Ran `flutter run`
- [ ] Logged in as driver
- [ ] Clicked "CLEANUP DATABASE" button
- [ ] Saw success message
- [ ] Logged in as passenger
- [ ] Searched for vehicle
- [ ] Verified "Monitoring Not Started" shows (no "Normal"/"Safe")
- [ ] Tested START MONITORING → live status appears
- [ ] Tested STOP MONITORING → "Monitoring Not Started" appears
- [ ] Removed cleanup button from code

---

## 🐛 Troubleshooting

### If cleanup button doesn't appear:
- Make sure you did `flutter clean` and `flutter run` (not just hot reload)
- Check you're logged in as driver (not passenger)
- Scroll down on the driver dashboard

### If "Normal" status still shows after cleanup:
1. Check Firebase Console → Realtime Database
2. Navigate to `drivers/{driverId}/current_stats`
3. If it still exists, delete it manually
4. Refresh passenger dashboard

### If cleanup button gives an error:
- Check console logs for error details
- Verify internet connection
- Try clicking the button again

### If changes don't appear:
- Make sure you did `flutter clean` (not just restart)
- Make sure you did `flutter run` (not just hot reload with R)
- Check that you're testing on the same device/browser

---

## 🎉 Expected Final Result

### Passenger Dashboard - Driver NOT Monitoring:

```
┌─────────────────────────────────────────────────────────┐
│ Find Driver by License Plate                            │
│ [abc123]                                    [Search]    │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Vehicle & Driver                                        │
│ Driver:                                  Wahb Usman     │
│ Vehicle:                                 Changan Alsvin │
│ License Plate:                           ABC-123        │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ ℹ️ Monitoring Not Started                               │
│                                                         │
│ Driver has not started monitoring session yet.          │
│ Live status will appear when driver clicks              │
│ "START MONITORING".                                     │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Trip Information                                        │
│ Current vehicle monitoring details                      │
│                                                         │
│ No active monitoring session. Trip information will     │
│ appear when driver starts monitoring.                   │
└─────────────────────────────────────────────────────────┘
```

**NO "Normal" or "Safe" status should be visible!**

---

## 📞 Still Having Issues?

If you've followed all steps and it's still not working:

1. **Check console logs** for any error messages
2. **Check Firebase Console** → Realtime Database → verify `current_stats` is deleted
3. **Check Firebase Console** → Firestore → drivers → verify status is "idle"
4. **Take a screenshot** of the passenger dashboard and console logs
5. **Share the screenshot** for further debugging

---

## ⏱️ Time Estimate

- Step 1-2: 2-3 minutes (clean and rebuild)
- Step 3: 10 seconds (click button)
- Step 4-5: 2 minutes (testing)
- Step 6: 1 minute (remove button)

**Total: ~5-6 minutes**

---

## 🎯 Summary

The fix requires:
1. ✅ Full app restart (not hot reload)
2. ✅ One-time database cleanup (click button)
3. ✅ Testing to verify it works
4. ✅ Removing the temporary button

After this, the system will automatically manage the data correctly!
