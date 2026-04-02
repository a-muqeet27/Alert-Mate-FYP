import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';

import '../auth_screen.dart';
import '../utils/page_transitions.dart';

/// Ensures Firebase Auth reports a verified email before the user can stay on a dashboard.
/// Redirects to [AuthScreen] if the session exists but the address is not verified (e.g. stale state).
class EmailVerifiedGuard extends StatefulWidget {
  final Widget child;

  const EmailVerifiedGuard({super.key, required this.child});

  @override
  State<EmailVerifiedGuard> createState() => _EmailVerifiedGuardState();
}

class _EmailVerifiedGuardState extends State<EmailVerifiedGuard> {
  StreamSubscription<firebase_auth.User?>? _authSub;

  @override
  void initState() {
    super.initState();
    _check();
    _authSub = firebase_auth.FirebaseAuth.instance.authStateChanges().listen((_) => _check());
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    final u = firebase_auth.FirebaseAuth.instance.currentUser;
    if (u == null) return;
    try {
      await u.reload();
      await u.getIdToken(true);
      await u.reload();
    } catch (_) {
      return;
    }
    final fresh = firebase_auth.FirebaseAuth.instance.currentUser;
    if (!mounted) return;
    if (fresh != null && !fresh.emailVerified) {
      Navigator.of(context).pushAndRemoveUntil(
        FadeScalePageRoute(page: const AuthScreen(initialIsSignIn: true)),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
