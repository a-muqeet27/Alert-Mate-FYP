# Google Authentication - Quick Start Guide 🚀

## ⚡ 5-Minute Setup

Everything is already implemented in your code! Just complete these Firebase Console steps:

---

## Step 1: Firebase Console (2 minutes)

### A. Add Android App (if not already added)
1. Go to: https://console.firebase.google.com/
2. Select project: **helical-liberty-491813-e1**
3. Click "Add app" → Android icon
4. Package name: `com.example.alert_mate`
5. SHA-1 fingerprint:
   ```
   A8:04:50:D0:FF:B0:F2:3C:E8:BE:A7:BA:26:36:16:C2:97:34:AC:39
   ```
6. Click "Register app"

### B. Download google-services.json
1. Click "Download google-services.json"
2. Save it
3. Replace the file at: `Alert-Mate-master/android/app/google-services.json`

### C. Enable Google Sign-In
1. Go to: Authentication → Sign-in method
2. Click "Google"
3. Toggle "Enable"
4. Select support email
5. Click "Save"

---

## Step 2: Install & Run (2 minutes)

```bash
# Install dependencies
flutter pub get

# Clean build
flutter clean

# Run on device/emulator
flutter run
```

---

## Step 3: Test (1 minute)

1. ✅ App opens
2. ✅ Select role (Driver/Passenger/Owner/Admin)
3. ✅ Click "Continue with Google"
4. ✅ Select Google account
5. ✅ Signed in → Dashboard appears

---

## ✅ That's It!

Your Google Authentication is now working! 🎉

---

## 📱 What Users Will See

### Sign-In Screen:
```
┌─────────────────────────────┐
│     ALERT MATE              │
│  Drowsiness Detection       │
├─────────────────────────────┤
│  [Driver] [Passenger]       │
│  [Owner]  [Admin]           │
├─────────────────────────────┤
│  Selected Role: Driver      │
├─────────────────────────────┤
│  Email: _______________     │
│  Password: ____________     │
│                             │
│  [Sign-In as Driver]        │
│                             │
│  ────────── OR ──────────   │
│                             │
│  [🔵 Continue with Google]  │
└─────────────────────────────┘
```

---

## 🔧 Troubleshooting

### Issue: "Developer Error"
**Fix**: Download fresh google-services.json from Firebase Console

### Issue: "Sign-in failed"
**Fix**: Verify SHA-1 is added in Firebase Console → Project Settings

### Issue: Button doesn't appear
**Fix**: Make sure you're on "Sign-In" tab (not "Sign-Up")

---

## 📊 What Gets Created

When user signs in with Google:

**Firestore Document** (`users/{uid}`):
```json
{
  "email": "user@gmail.com",
  "firstName": "John",
  "lastName": "Doe",
  "roles": ["driver"],
  "activeRole": "driver",
  "emailVerified": true,
  "authProvider": "google"
}
```

---

## 🎯 Key Features

✅ One-click sign-in
✅ No password needed
✅ No email verification needed
✅ Automatic profile creation
✅ Multi-role support
✅ Secure OAuth 2.0

---

## 📞 Need Help?

Check these files:
- `GOOGLE_AUTH_VERIFICATION.md` - Complete verification report
- `ANDROID_GOOGLE_AUTH_CHECKLIST.md` - Detailed checklist
- `GOOGLE_AUTH_SETUP.md` - Full setup guide

---

**Status**: ✅ Ready to use after Firebase Console setup
**Time Required**: 5 minutes
**Difficulty**: Easy 🟢
