# Google Authentication Setup Guide

## ✅ What's Been Done

1. **Added google_sign_in dependency** to `pubspec.yaml`
2. **Created Google Services JSON** at `android/app/google-services.json`
3. **Updated FirebaseAuthService** with Google Sign-In functionality
4. **Added Google Sign-In button** to the auth screen
5. **Integrated with existing role system** - users can sign in with Google for any role

## 🔧 Configuration Steps

### 1. Complete Firebase Console Setup

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: **helical-liberty-491813-e1**
3. Go to **Authentication** → **Sign-in method**
4. Enable **Google** sign-in provider
5. Add your app's SHA-1 fingerprint:
   ```
   A8:04:50:D0:FF:B0:F2:3C:E8:BE:A7:BA:26:36:16:C2:97:34:AC:39
   ```

### 2. Download Complete google-services.json

1. In Firebase Console, go to **Project Settings** (gear icon)
2. Scroll down to **Your apps** section
3. Find your Android app or add one if it doesn't exist:
   - Package name: `com.example.alert_mate`
   - App nickname: Alert Mate
   - SHA-1: `A8:04:50:D0:FF:B0:F2:3C:E8:BE:A7:BA:26:36:16:C2:97:34:AC:39`
4. Click **Download google-services.json**
5. Replace the file at `android/app/google-services.json` with the downloaded one

### 3. Update Android Configuration

The `android/app/build.gradle.kts` already has the necessary configuration. Verify it includes:

```kotlin
plugins {
    id("com.google.gms.google-services")
}
```

### 4. Install Dependencies

Run:
```bash
flutter pub get
```

### 5. Add Google Logo (Optional)

For a better UI, add a Google logo image:
1. Download the official Google logo
2. Save it as `assets/images/google_logo.png`
3. The button will use it automatically (falls back to icon if not found)

## 📱 How It Works

### For Users:
1. Select their role (Driver, Passenger, Owner, or Admin)
2. Click "Continue with Google" button
3. Sign in with their Google account
4. Automatically creates/updates their profile with the selected role

### Technical Flow:
1. User clicks Google Sign-In button
2. Google Sign-In SDK opens authentication flow
3. User selects Google account
4. Firebase authenticates with Google credential
5. App checks if user exists in Firestore:
   - **New user**: Creates profile with selected role
   - **Existing user**: Adds new role if not already present
6. Navigates to appropriate dashboard

### Role Management:
- Google accounts are **pre-verified** (no email verification needed)
- Users can have multiple roles
- Each Google sign-in can add a new role to existing account
- Active role is set to the most recently selected role

## 🔐 Security Features

1. **Email Pre-Verification**: Google accounts are already verified
2. **Role-Based Access**: Users can only access dashboards for their assigned roles
3. **Secure Token Exchange**: Uses Firebase Authentication for secure token handling
4. **Profile Sync**: Automatically syncs user data between Google and Firestore

## 🧪 Testing

### Test Google Sign-In:
1. Run the app: `flutter run`
2. Select a role (e.g., Driver)
3. Click "Continue with Google"
4. Sign in with a Google account
5. Verify you're redirected to the correct dashboard

### Test Multiple Roles:
1. Sign in as Driver with Google
2. Sign out
3. Select Owner role
4. Sign in with the same Google account
5. Verify the Owner role is added to your profile

## 📝 OAuth Client Configuration

Your OAuth client ID from the JSON you provided:
```
482858582207-cbvsgpu2o0ligt24vh2etbuumdn5358r.apps.googleusercontent.com
```

This is configured in:
- `android/app/google-services.json`
- Firebase Console → Authentication → Sign-in method → Google

## 🐛 Troubleshooting

### "Sign-in failed" error:
- Verify SHA-1 fingerprint is added in Firebase Console
- Ensure google-services.json is properly downloaded and placed
- Check that Google sign-in is enabled in Firebase Console

### "Account not found" error:
- This is normal for first-time users
- The app will automatically create a profile

### Role access denied:
- Verify the user has the selected role in Firestore
- Check the `roles` array in the user document

## 🎨 UI Features

The Google Sign-In button:
- Only appears on **Sign-In** screen (not Sign-Up)
- Styled with Google branding guidelines
- Shows loading state during authentication
- Includes "OR" divider for visual separation

## 📊 Firestore Data Structure

When a user signs in with Google, their profile includes:

```json
{
  "uid": "firebase_user_id",
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
  "photoURL": "https://...",
  "createdAt": "timestamp",
  "lastLogin": "timestamp"
}
```

## ✨ Benefits

1. **Faster Sign-In**: No need to remember passwords
2. **Better Security**: Leverages Google's security infrastructure
3. **No Email Verification**: Google accounts are pre-verified
4. **Seamless Experience**: One-click authentication
5. **Profile Sync**: Automatically gets name and photo from Google

## 🚀 Next Steps

1. Complete Firebase Console configuration
2. Download and replace google-services.json
3. Run `flutter pub get`
4. Test on a real device or emulator
5. (Optional) Add Google logo image for better branding

---

**Status**: ✅ Implementation Complete
**Testing**: Ready for testing after Firebase configuration
**Documentation**: Complete
