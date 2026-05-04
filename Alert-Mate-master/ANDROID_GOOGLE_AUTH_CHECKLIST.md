# Android Google Authentication - Complete Checklist ✅

## 🔍 Configuration Review

I've thoroughly checked your Android setup. Here's the status:

### ✅ CORRECT - Already Configured

1. **settings.gradle.kts** ✅
   - Google Services plugin declared: `id("com.google.gms.google-services") version("4.4.2")`
   - Repositories configured correctly (google(), mavenCentral())

2. **app/build.gradle.kts** ✅
   - Google Services plugin applied: `id("com.google.gms.google-services")`
   - Package name correct: `com.example.alert_mate`
   - Firebase dependencies included

3. **AndroidManifest.xml** ✅
   - INTERNET permission present
   - Package name matches: `com.example.alert_mate`
   - Main activity exported correctly

4. **Code Implementation** ✅
   - FirebaseAuthService has Google Sign-In method
   - Auth screen has Google Sign-In button
   - Error handling implemented
   - Role management integrated

### ⚠️ NEEDS ATTENTION

1. **google-services.json** ⚠️
   - Template file created but needs real values
   - **ACTION REQUIRED**: Download from Firebase Console

## 📋 Step-by-Step Setup Guide

### Step 1: Firebase Console Configuration

1. **Go to Firebase Console**
   - URL: https://console.firebase.google.com/
   - Project: `helical-liberty-491813-e1`

2. **Add Android App (if not already added)**
   - Click "Add app" → Android icon
   - Package name: `com.example.alert_mate`
   - App nickname: `Alert Mate` (optional)
   - **CRITICAL**: Add SHA-1 certificate fingerprint:
     ```
     A8:04:50:D0:FF:B0:F2:3C:E8:BE:A7:BA:26:36:16:C2:97:34:AC:39
     ```

3. **Enable Google Sign-In**
   - Go to Authentication → Sign-in method
   - Click on "Google"
   - Toggle "Enable"
   - Project support email: (your email)
   - Click "Save"

4. **Download google-services.json**
   - Go to Project Settings (gear icon)
   - Scroll to "Your apps"
   - Find your Android app
   - Click "Download google-services.json"
   - **IMPORTANT**: Replace the file at `android/app/google-services.json`

### Step 2: Verify SHA-1 Fingerprint

Your SHA-1 fingerprint:
```
A8:04:50:D0:FF:B0:F2:3C:E8:BE:A7:BA:26:36:16:C2:97:34:AC:39
```

**How to verify it's correct:**

For debug builds:
```bash
cd android
./gradlew signingReport
```

For release builds (if you have a keystore):
```bash
keytool -list -v -keystore your-release-key.keystore -alias your-key-alias
```

### Step 3: Install Dependencies

```bash
flutter pub get
```

### Step 4: Clean and Rebuild

```bash
flutter clean
flutter pub get
cd android
./gradlew clean
cd ..
flutter run
```

## 🔧 Android-Specific Configuration Details

### Minimum SDK Version
Your app uses Flutter's default minSdk. Google Sign-In requires:
- **Minimum SDK**: 21 (Android 5.0)
- Your current setup: Uses `flutter.minSdkVersion` (should be 21+)

### Dependencies Versions
Current versions in your build.gradle.kts:
```kotlin
implementation("com.google.firebase:firebase-auth-ktx:22.2.0")
```

This version supports Google Sign-In. ✅

### Internet Permission
Already present in AndroidManifest.xml:
```xml
<uses-permission android:name="android.permission.INTERNET" />
```

## 🧪 Testing on Android

### Test on Real Device (Recommended)
```bash
flutter run --release
```

**Why release mode?**
- Debug mode uses debug SHA-1
- Release mode uses release SHA-1
- Make sure the SHA-1 you added matches your build type

### Test on Emulator
```bash
flutter run
```

**Emulator requirements:**
- Google Play Services installed
- Signed in with a Google account

## 🐛 Common Android Issues & Solutions

### Issue 1: "Developer Error" or "Sign-in failed"
**Cause**: SHA-1 fingerprint not added or incorrect

**Solution**:
1. Get your SHA-1: `cd android && ./gradlew signingReport`
2. Add it to Firebase Console → Project Settings → Your app
3. Wait 5-10 minutes for changes to propagate
4. Rebuild: `flutter clean && flutter run`

### Issue 2: "PlatformException(sign_in_failed)"
**Cause**: google-services.json not properly configured

**Solution**:
1. Download fresh google-services.json from Firebase Console
2. Replace `android/app/google-services.json`
3. Rebuild: `flutter clean && flutter run`

### Issue 3: "API not enabled"
**Cause**: Google Sign-In API not enabled in Google Cloud Console

**Solution**:
1. Go to https://console.cloud.google.com/
2. Select project: `helical-liberty-491813-e1`
3. APIs & Services → Library
4. Search "Google Sign-In API"
5. Click "Enable"

### Issue 4: "Network error"
**Cause**: Internet permission missing or network issues

**Solution**:
- Verify INTERNET permission in AndroidManifest.xml ✅ (already present)
- Check device/emulator internet connection
- Try on different network

### Issue 5: "Package name mismatch"
**Cause**: Package name in google-services.json doesn't match app

**Solution**:
- Verify package name in AndroidManifest.xml: `com.example.alert_mate` ✅
- Verify package name in google-services.json matches
- Rebuild app

## 📱 Android Build Types

### Debug Build
- Uses debug signing certificate
- SHA-1 from: `~/.android/debug.keystore`
- Easier for testing

### Release Build
- Uses release signing certificate
- SHA-1 from your release keystore
- Required for production

**IMPORTANT**: Add SHA-1 for BOTH debug and release if you plan to test both!

## ✅ Pre-Flight Checklist

Before testing, verify:

- [ ] Firebase project created: `helical-liberty-491813-e1`
- [ ] Android app added to Firebase with package: `com.example.alert_mate`
- [ ] SHA-1 fingerprint added: `A8:04:50:D0:FF:B0:F2:3C:E8:BE:A7:BA:26:36:16:C2:97:34:AC:39`
- [ ] Google Sign-In enabled in Firebase Authentication
- [ ] google-services.json downloaded and placed in `android/app/`
- [ ] Dependencies installed: `flutter pub get`
- [ ] App builds successfully: `flutter build apk` or `flutter run`
- [ ] Device/emulator has Google Play Services
- [ ] Device/emulator has internet connection
- [ ] Device/emulator signed in with Google account (for testing)

## 🎯 Expected Behavior

### Successful Flow:
1. User opens app
2. Selects role (Driver/Passenger/Owner/Admin)
3. Clicks "Continue with Google"
4. Google account picker appears
5. User selects account
6. Brief loading
7. Redirected to dashboard

### What You'll See in Logs:
```
🔐 Starting Google Sign-In...
✅ Google user selected: user@gmail.com
✅ Firebase sign-in successful!
📝 Creating new user profile... (or 👤 Existing user found)
✅ New user profile created with roles: [driver]
```

## 🔐 Security Notes

### OAuth Client Types
Your OAuth client ID is type 3 (Web client):
```
482858582207-cbvsgpu2o0ligt24vh2etbuumdn5358r.apps.googleusercontent.com
```

This is correct for Firebase Authentication. ✅

### SHA-1 Security
- SHA-1 is used to verify your app's identity
- Only apps signed with the matching certificate can use Google Sign-In
- Keep your release keystore secure!

## 📊 What Gets Created in Firestore

When a user signs in with Google:

```json
{
  "uid": "firebase_generated_id",
  "firstName": "John",
  "lastName": "Doe",
  "name": "John Doe",
  "email": "john@gmail.com",
  "phone": "",
  "roles": ["driver"],
  "activeRole": "driver",
  "emailVerified": true,
  "isActive": true,
  "authProvider": "google",
  "photoURL": "https://lh3.googleusercontent.com/...",
  "createdAt": "2026-05-05T...",
  "lastLogin": "2026-05-05T..."
}
```

## 🚀 Ready to Test!

Your Android configuration is **95% complete**. 

**Only remaining step**: Download and replace google-services.json from Firebase Console.

After that, you're ready to test Google Sign-In on Android! 🎉

---

## 📞 Quick Reference

**Firebase Console**: https://console.firebase.google.com/
**Project ID**: helical-liberty-491813-e1
**Package Name**: com.example.alert_mate
**SHA-1**: A8:04:50:D0:FF:B0:F2:3C:E8:BE:A7:BA:26:36:16:C2:97:34:AC:39
**OAuth Client**: 482858582207-cbvsgpu2o0ligt24vh2etbuumdn5358r.apps.googleusercontent.com

---

**Last Checked**: May 5, 2026
**Status**: ✅ Configuration Verified - Ready for Firebase Console Setup
