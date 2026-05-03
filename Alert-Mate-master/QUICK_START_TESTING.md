# Quick Start - Testing Live Location Tracking

## 🎯 Quick Test (Before Deployment)

You can test the implementation locally before deploying to production:

### 1. Update Tracking URL for Local Testing

In `lib/dashboards/passenger_dashboard.dart` (around line 1250), temporarily change:

```dart
// For local testing
final trackingUrl = 'http://localhost:8080/#/track/$tokenId';
```

### 2. Run the App

```bash
cd Alert-Mate-master
flutter run -d chrome
```

### 3. Test Flow

1. **Login as Passenger**
2. **Search for a vehicle** by license plate
3. **Click "Share Live Location"**
4. **Copy the tracking URL** from WhatsApp/SMS
5. **Open in new browser tab** to see the public tracking screen

---

## 🔥 Firebase Setup (Required)

### Update Firestore Security Rules

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Navigate to **Firestore Database** → **Rules**
4. Copy the rules from `firestore_security_rules.txt`
5. Click **Publish**

---

## 📱 Test Scenarios

### ✅ Scenario 1: Happy Path
- Passenger searches for vehicle
- Clicks "Share Live Location"
- WhatsApp opens with message
- Recipient opens link
- **Expected**: Live tracking screen shows vehicle location

### ✅ Scenario 2: Expired Token
- Create a token with short duration (for testing):
  ```dart
  duration: const Duration(minutes: 1), // 1 minute for testing
  ```
- Wait for expiry
- Open tracking link
- **Expected**: "Tracking Link Expired" message

### ✅ Scenario 3: Offline Driver
- Create tracking link
- Driver goes offline (closes app)
- Open tracking link
- **Expected**: "Location Unavailable" message

### ✅ Scenario 4: Invalid Token
- Open tracking link with random token: `/track/invalid123`
- **Expected**: "Tracking Link Expired" message

### ✅ Scenario 5: Real-time Updates
- Open tracking screen
- Driver moves location
- **Expected**: Map updates automatically every 10 seconds

---

## 🐛 Common Issues & Fixes

### Issue: "No driver assigned to this vehicle"
**Cause**: Vehicle doesn't have a driver assigned
**Fix**: Assign a driver to the vehicle in owner dashboard

### Issue: Token creation fails
**Cause**: Firebase Security Rules not updated
**Fix**: Update Firestore rules (see above)

### Issue: WhatsApp doesn't open
**Cause**: WhatsApp not installed or URL scheme not supported
**Fix**: System will fallback to SMS automatically

### Issue: Map doesn't show location
**Cause**: Driver location not being updated
**Fix**: Ensure driver has started a monitoring session

### Issue: "Tracking Link Expired" immediately
**Cause**: Token validation failing
**Fix**: Check Firebase Console → Firestore → tracking_tokens collection

---

## 📊 Monitoring & Debugging

### Check Token Creation

1. Go to Firebase Console → Firestore Database
2. Look for `tracking_tokens` collection
3. Verify token document exists with correct data:
   ```
   {
     driverId: "abc123",
     vehiclePlate: "ABC-1234",
     vehicleMake: "Toyota",
     vehicleModel: "Corolla",
     createdAt: 1234567890,
     expiresAt: 1234589490,
     isActive: true
   }
   ```

### Check Driver Location

1. Go to Firebase Console → Firestore Database
2. Look for `drivers` collection
3. Find driver document
4. Verify location data:
   ```
   {
     lat: 31.5204,
     lng: 74.3587,
     status: "on_trip",
     drowsinessAlert: false,
     updatedAt: timestamp
   }
   ```

### Check Console Logs

Open browser DevTools (F12) and check for:
- ✅ "TrackingService: Created token..."
- ✅ "Streaming driver location..."
- ❌ Any error messages

---

## 🚀 Ready for Production?

Before deploying to production, ensure:

- [ ] Firebase Security Rules updated
- [ ] All test scenarios pass
- [ ] Token expiry set to 6 hours (not 1 minute)
- [ ] Tracking URL uses production domain
- [ ] WhatsApp/SMS sharing works
- [ ] Real-time updates work smoothly
- [ ] Error states display correctly
- [ ] Mobile responsive design tested
- [ ] Desktop layout tested

---

## 📝 Next Steps

1. **Test locally** using the steps above
2. **Fix any issues** that arise
3. **Deploy to production** following `LIVE_TRACKING_DEPLOYMENT_GUIDE.md`
4. **Update tracking URL** with production domain
5. **Test in production** with real users

---

## 💡 Tips

- Use Chrome DevTools to simulate mobile devices
- Test with multiple browser tabs (passenger + recipient)
- Monitor Firebase usage in Firebase Console
- Check Firestore logs for any errors
- Test with different network conditions (slow 3G, offline, etc.)

---

## 🎉 Success Criteria

Your implementation is working correctly when:

✅ Passenger can create tracking links
✅ WhatsApp/SMS opens with pre-filled message
✅ Tracking link opens in browser
✅ Map shows driver's real-time location
✅ Location updates every 10 seconds
✅ Countdown timer shows remaining time
✅ Expired links show error message
✅ Offline drivers show error message
✅ UI is responsive on mobile and desktop

---

## 📞 Need Help?

If you encounter issues:

1. Check the console logs (browser DevTools)
2. Verify Firebase Security Rules
3. Check Firestore data structure
4. Review `LIVE_TRACKING_DEPLOYMENT_GUIDE.md`
5. Test with different browsers
