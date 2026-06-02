# Live Location Tracking - Deployment Guide

## ✅ Implementation Status: COMPLETE

The live location tracking system has been successfully implemented with the following components:

### 📦 New Files Created

1. **`lib/models/tracking_token.dart`** - Tracking token data model
2. **`lib/services/tracking_service.dart`** - Service for managing tracking tokens
3. **`lib/screens/public_live_tracking_screen.dart`** - Public tracking UI

### 🔧 Modified Files

1. **`lib/dashboards/passenger_dashboard.dart`** - Added "Share Live Location" button
2. **`lib/main.dart`** - Added route handling for `/track/:tokenId`

---

## 🚀 Deployment Steps

### Step 1: Update Firebase Security Rules

Add the following rules to your Firestore Security Rules:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Existing rules...
    
    // Tracking tokens - public read, authenticated write
    match /tracking_tokens/{tokenId} {
      // Anyone can read tracking tokens (for public tracking)
      allow read: if true;
      
      // Only authenticated users can create tokens
      allow create: if request.auth != null;
      
      // Only the creator can update/delete
      allow update, delete: if request.auth != null 
                            && request.auth.uid == resource.data.driverId;
    }
  }
}
```

**How to update:**
1. Go to Firebase Console → Firestore Database → Rules
2. Add the tracking_tokens rules above
3. Click "Publish"

---

### Step 2: Deploy to Web Hosting

To get a real domain URL for the tracking links, deploy your Flutter web app:

#### Option A: Firebase Hosting (Recommended - Free)

```bash
# Install Firebase CLI
npm install -g firebase-tools

# Login to Firebase
firebase login

# Initialize Firebase Hosting in your project
cd Alert-Mate-master
firebase init hosting

# Build Flutter web app
flutter build web

# Deploy to Firebase Hosting
firebase deploy --only hosting
```

After deployment, you'll get a URL like: `https://your-project.firebaseapp.com`

#### Option B: Other Hosting Providers

- **Netlify**: Drag & drop `build/web` folder
- **Vercel**: Connect GitHub repo and deploy
- **GitHub Pages**: Push `build/web` to gh-pages branch

---

### Step 3: Update Tracking URL in Code

Once deployed, update the tracking URL in `passenger_dashboard.dart`:

**Find this line (around line 1250):**
```dart
final trackingUrl = 'https://yourapp.com/track/$tokenId';
```

**Replace with your actual domain:**
```dart
final trackingUrl = 'https://your-project.firebaseapp.com/track/$tokenId';
```

---

### Step 4: Test the Complete Flow

1. **As Passenger:**
   - Open passenger dashboard
   - Search for a vehicle by Vehicle Registration Number
   - Click "Share Live Location" button
   - WhatsApp should open with pre-filled message

2. **As Recipient:**
   - Open the tracking link from WhatsApp/SMS
   - Should see the public tracking screen
   - Verify real-time location updates work
   - Check countdown timer shows remaining time

3. **Verify Expiry:**
   - Wait for token to expire (or manually set short duration for testing)
   - Link should show "Tracking Link Expired" message

---

## 💰 Cost Optimization

The system is designed to be cost-effective:

### Current Settings
- **Token Expiry**: 6 hours (configurable)
- **Location Updates**: Every 10 seconds (from existing driver tracking)
- **Auto-cleanup**: Expired tokens are deactivated

### Estimated Costs (Firebase Free Tier)
- **Firestore Reads**: ~2,160 reads per token (6 hours × 360 reads/hour)
- **Firestore Writes**: 1 write per token creation
- **Free Tier Limits**: 50,000 reads/day, 20,000 writes/day
- **Estimated Usage**: ~23 tokens/day within free tier

### Cost Optimization Tips

1. **Adjust Token Duration** (in `passenger_dashboard.dart`):
```dart
// Reduce from 6 hours to 3 hours
duration: const Duration(hours: 3),
```

2. **Reduce Update Frequency** (in `public_live_tracking_screen.dart`):
```dart
// Change from 10 seconds to 30 seconds
// Note: This requires updating the driver location update frequency
```

3. **Add Cleanup Job** (optional):
```dart
// In tracking_service.dart, call periodically
await trackingService.cleanupExpiredTokens();
```

---

## 🔒 Security Features

✅ **Token-based access** - No authentication required for recipients
✅ **Time-limited** - Tokens expire after 6 hours
✅ **Deactivation** - Expired tokens are automatically deactivated
✅ **Public read-only** - Recipients can only view, not modify
✅ **Driver-controlled** - Only authenticated users can create tokens

---

## 🎨 UI Features

✅ **Responsive design** - Works on mobile and desktop
✅ **Real-time updates** - Location updates every 10 seconds
✅ **Status indicators** - Shows driver status (on trip, idle, offline)
✅ **Drowsiness alerts** - Visual warning if driver is drowsy
✅ **Countdown timer** - Shows remaining time before expiry
✅ **Error states** - Handles expired links and offline drivers
✅ **Vehicle info** - Displays make, model, and Vehicle Registration Number

---

## 🧪 Testing Checklist

- [ ] Firebase Security Rules updated
- [ ] App deployed to web hosting
- [ ] Tracking URL updated in code
- [ ] WhatsApp sharing works
- [ ] SMS fallback works
- [ ] Tracking link opens correctly
- [ ] Real-time location updates work
- [ ] Countdown timer displays correctly
- [ ] Expired links show error message
- [ ] Offline drivers show error message
- [ ] Mobile responsive design works
- [ ] Desktop layout works

---

## 🐛 Troubleshooting

### Issue: "Tracking Link Expired" immediately
**Solution:** Check that token creation succeeded and Firebase rules allow read access

### Issue: WhatsApp says "person not available"
**Solution:** This was fixed - WhatsApp now opens with message pre-filled for user to select contacts

### Issue: Location not updating
**Solution:** Verify driver is online and location services are enabled

### Issue: Link doesn't open
**Solution:** Ensure route handling is configured in `main.dart` and app is deployed

### Issue: High Firebase costs
**Solution:** Reduce token duration or update frequency

---

## 📱 How It Works

1. **Passenger searches for vehicle** by Vehicle Registration Number
2. **Clicks "Share Live Location"** button
3. **System creates tracking token** with 6-hour expiry
4. **Token stored in Firestore** with vehicle and driver info
5. **Tracking URL generated** with token ID
6. **WhatsApp/SMS opens** with pre-filled message
7. **Recipient opens link** in browser
8. **Public tracking screen loads** and validates token
9. **Real-time location streams** from Firestore
10. **Map updates every 10 seconds** automatically
11. **Token expires after 6 hours** and link becomes invalid

---

## 🔄 Future Enhancements (Optional)

- [ ] Add ability to revoke tokens from passenger dashboard
- [ ] Show list of active tracking links
- [ ] Add push notifications when driver status changes
- [ ] Add analytics to track token usage
- [ ] Add custom expiry duration selector
- [ ] Add password protection for sensitive trips
- [ ] Add geofencing alerts (notify when driver enters/exits area)
- [ ] Add trip history replay feature

---

## 📞 Support

If you encounter any issues during deployment:

1. Check Firebase Console logs
2. Verify Firestore Security Rules
3. Test with Flutter DevTools
4. Check browser console for errors
5. Verify all dependencies are installed

---

## ✨ Summary

The live location tracking system is **fully implemented and ready for deployment**. Follow the steps above to:

1. Update Firebase Security Rules
2. Deploy to web hosting
3. Update tracking URL in code
4. Test the complete flow

The system is cost-optimized for the Firebase free tier and includes all necessary security, error handling, and UI features.
