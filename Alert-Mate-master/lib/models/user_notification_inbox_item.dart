import 'package:cloud_firestore/cloud_firestore.dart';

/// One row in `user_notifications` for the inbox UI.
class UserNotificationInboxItem {
  UserNotificationInboxItem({
    required this.docId,
    required this.title,
    required this.body,
    required this.type,
    required this.unread,
    required this.createdAt,
    this.emergencyAlertId,
    this.handledAction,
    this.handledAt,
  });

  final String docId;
  final String title;
  final String body;
  final String type;
  final bool unread;
  final DateTime createdAt;
  final String? emergencyAlertId;
  /// Set when the user taps Acknowledge / Resolved / Mark read (Firestore).
  final String? handledAction;
  final DateTime? handledAt;

  factory UserNotificationInboxItem.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final r = m['read'];
    final readTrue = r == true || (r is String && r.toLowerCase().trim() == 'true');
    DateTime when = DateTime.fromMillisecondsSinceEpoch(0);
    final ca = m['createdAt'];
    if (ca is Timestamp) when = ca.toDate();
    DateTime? handledWhen;
    final ha = m['handledAt'];
    if (ha is Timestamp) handledWhen = ha.toDate();

    return UserNotificationInboxItem(
      docId: d.id,
      title: m['title'] as String? ?? 'Notification',
      body: m['body'] as String? ?? '',
      type: m['type'] as String? ?? 'general',
      unread: !readTrue,
      createdAt: when,
      emergencyAlertId: m['emergencyAlertId'] as String?,
      handledAction: m['handledAction'] as String?,
      handledAt: handledWhen,
    );
  }
}
