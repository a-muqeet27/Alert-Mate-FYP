# Firebase Security Rules Update

## 🎯 What to Add

You need to add **ONE new section** to your existing Firebase Security Rules for the `tracking_tokens` collection.

---

## 📝 Instructions

### Option 1: Copy Complete File (Recommended)

1. Go to Firebase Console → Firestore Database → Rules
2. **Replace all rules** with the content from `firestore_security_rules_UPDATED.txt`
3. Click **Publish**

This file contains all your existing rules PLUS the new tracking_tokens rules.

---

### Option 2: Add Only New Section

If you prefer to manually add just the new section:

1. Go to Firebase Console → Firestore Database → Rules
2. Scroll to the **bottom** of your rules (after the `emergencyContacts` section)
3. **Add this section** before the final closing braces:

```javascript
    // ── tracking_tokens collection ────────────────────────────────────────────
    // PUBLIC READ for live location tracking (no auth required for recipients)
    // Only authenticated users can create tokens
    // Only the driver who owns the token can update/delete it
    match /tracking_tokens/{tokenId} {
      // Anyone can read tracking tokens (for public tracking links)
      allow read: if true;
      
      // Only authenticated users can create tokens
      allow create: if isAuthenticated();
      
      // Only the driver who owns the token can update/delete
      allow update, delete: if isAuthenticated() 
                            && request.auth.uid == resource.data.driverId;
    }
```

4. Click **Publish**

---

## 📍 Exact Location to Add

Your current rules end with:

```javascript
    // ── emergencyContacts collection ─────────────────────────────────────────
    match /emergencyContacts/{contactId} {
      allow read:   if isAuthenticated();
      allow write:  if isAuthenticated();
    }
  }  // ← This closes the "match /databases/{database}/documents" block
}    // ← This closes the "service cloud.firestore" block
```

**Add the new section BEFORE the two closing braces**, like this:

```javascript
    // ── emergencyContacts collection ─────────────────────────────────────────
    match /emergencyContacts/{contactId} {
      allow read:   if isAuthenticated();
      allow write:  if isAuthenticated();
    }
    
    // ── tracking_tokens collection ────────────────────────────────────────────
    // PUBLIC READ for live location tracking (no auth required for recipients)
    match /tracking_tokens/{tokenId} {
      allow read: if true;
      allow create: if isAuthenticated();
      allow update, delete: if isAuthenticated() 
                            && request.auth.uid == resource.data.driverId;
    }
  }  // ← Closes "match /databases/{database}/documents"
}    // ← Closes "service cloud.firestore"
```

---

## 🔍 What This Does

### `allow read: if true;`
- **Anyone** can read tracking tokens (no authentication required)
- This allows recipients to view live location via the public tracking link
- Recipients don't need to sign in or have an account

### `allow create: if isAuthenticated();`
- Only **signed-in users** can create tracking tokens
- Prevents anonymous users from creating spam tokens
- Passengers must be logged in to share location

### `allow update, delete: if isAuthenticated() && request.auth.uid == resource.data.driverId;`
- Only the **driver who owns the token** can update or delete it
- Prevents other users from modifying someone else's tracking tokens
- Provides security and privacy

---

## ✅ Verification

After publishing the rules:

1. **Test Public Read** (should work):
   - Open tracking link without being logged in
   - Should be able to view location

2. **Test Authenticated Create** (should work):
   - Log in as passenger
   - Click "Share Live Location"
   - Token should be created successfully

3. **Test Unauthorized Create** (should fail):
   - Log out
   - Try to create token via API
   - Should be denied

4. **Test Owner Update** (should work):
   - Driver can deactivate their own token

5. **Test Non-owner Update** (should fail):
   - Different user tries to modify token
   - Should be denied

---

## 🐛 Troubleshooting

### Error: "Missing or insufficient permissions"
**When**: Creating token
**Solution**: Ensure user is authenticated (logged in)

### Error: "Missing or insufficient permissions"
**When**: Reading token (public tracking screen)
**Solution**: Check that `allow read: if true;` is present

### Error: Rules validation failed
**Solution**: Check for syntax errors (missing semicolons, braces)

### Error: Function isAuthenticated() not found
**Solution**: Ensure helper functions are at the top of the rules file

---

## 📋 Quick Checklist

- [ ] Opened Firebase Console
- [ ] Navigated to Firestore Database → Rules
- [ ] Added tracking_tokens section (or replaced entire file)
- [ ] Clicked "Publish"
- [ ] Waited for rules to deploy (~30 seconds)
- [ ] Tested token creation (logged in)
- [ ] Tested public tracking link (not logged in)
- [ ] Verified no errors in console

---

## 🎉 Done!

Once the rules are published, your live location tracking feature will work correctly with proper security.

**Next Step**: Deploy your app to web hosting (see `LIVE_TRACKING_DEPLOYMENT_GUIDE.md`)
