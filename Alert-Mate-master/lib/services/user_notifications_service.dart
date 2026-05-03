import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

/// Firestore `user_notifications` helpers shared by sidebar badge and inbox.
class UserNotificationsService {
  UserNotificationsService._();

  static final Map<String, _UnreadCountHub> _hubs = {};

  static String effectiveUid(String fallbackUserId) =>
      firebase_auth.FirebaseAuth.instance.currentUser?.uid ?? fallbackUserId;

  static bool documentIsUnread(Map<String, dynamic> m) {
    final r = m['read'];
    final readTrue = r == true || (r is String && r.toLowerCase().trim() == 'true');
    return !readTrue;
  }

  /// One broadcast stream per [fallbackUserId] (app user id); rebinding follows auth uid.
  static Stream<int> unreadCountStream(String fallbackUserId) {
    return _hubs.putIfAbsent(fallbackUserId, () => _UnreadCountHub(fallbackUserId)).stream;
  }
}

class _UnreadCountHub {
  _UnreadCountHub(this.fallbackUserId);

  final String fallbackUserId;
  final StreamController<int> _controller = StreamController<int>.broadcast();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _notifSub;
  StreamSubscription<firebase_auth.User?>? _authSub;
  int _bindGeneration = 0;

  Stream<int> get stream {
    _ensureListening();
    return _controller.stream;
  }

  bool _listening = false;

  void _ensureListening() {
    if (_listening) return;
    _listening = true;
    _authSub = firebase_auth.FirebaseAuth.instance.authStateChanges().listen((_) => _scheduleBind());
    _scheduleBind();
  }

  void _scheduleBind() {
    final gen = ++_bindGeneration;
    unawaited(_bindAsync(gen));
  }

  Future<void> _bindAsync(int gen) async {
    await _notifSub?.cancel();
    _notifSub = null;
    if (gen != _bindGeneration) return;

    final uid = UserNotificationsService.effectiveUid(fallbackUserId);
    if (uid.isEmpty) {
      if (!_controller.isClosed) _controller.add(0);
      return;
    }

    if (gen != _bindGeneration) return;

    _notifSub = FirebaseFirestore.instance
        .collection('user_notifications')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .listen(
      (snap) {
        var count = 0;
        for (final d in snap.docs) {
          if (UserNotificationsService.documentIsUnread(d.data())) count++;
        }
        if (!_controller.isClosed) _controller.add(count);
      },
      onError: (_, __) {
        if (!_controller.isClosed) _controller.add(0);
      },
    );
  }
}
