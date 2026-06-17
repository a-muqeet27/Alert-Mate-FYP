import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/user.dart';
import '../models/user_notification_inbox_item.dart';
import '../services/emergency_alert_service.dart';

/// Full-area inbox opened from the sidebar "Notifications" item.
class NotificationsInboxScreen extends StatefulWidget {
  final User user;
  final bool embedded;
  final bool adminSectioned;

  const NotificationsInboxScreen({
    Key? key,
    required this.user,
    this.embedded = false,
    this.adminSectioned = false,
  }) : super(key: key);

  @override
  State<NotificationsInboxScreen> createState() => _NotificationsInboxScreenState();
}

class _NotificationsInboxScreenState extends State<NotificationsInboxScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final EmergencyAlertService _emergencyAlertService = EmergencyAlertService();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _notifSub;
  StreamSubscription<firebase_auth.User?>? _authSub;

  String? _streamUid;
  int _bindGeneration = 0;
  List<UserNotificationInboxItem> _entries = [];
  final Set<String> _busyIds = {};

  String _actorUid() =>
      firebase_auth.FirebaseAuth.instance.currentUser?.uid ?? widget.user.id;

  void _scheduleBindStream(String uid) {
    final gen = ++_bindGeneration;
    unawaited(_bindStreamAsync(uid, gen));
  }

  Future<void> _bindStreamAsync(String uid, int gen) async {
    await _notifSub?.cancel();
    _notifSub = null;
    if (!mounted || gen != _bindGeneration) return;

    _streamUid = uid;

    if (uid.isEmpty) {
      setState(() => _entries = []);
      return;
    }

    if (!mounted || gen != _bindGeneration) return;

    _notifSub = _firestore
        .collection('user_notifications')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .listen(
      (snap) {
        final list = snap.docs.map(UserNotificationInboxItem.fromDoc).toList()
          ..sort((a, b) {
            if (a.unread != b.unread) return a.unread ? -1 : 1;
            return b.createdAt.compareTo(a.createdAt);
          });
        if (mounted) setState(() => _entries = list);
      },
      onError: (e, _) {
        if (kDebugMode) {
          debugPrint('NotificationsInboxScreen stream error: $e');
        }
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _scheduleBindStream(_actorUid());
    _authSub = firebase_auth.FirebaseAuth.instance.authStateChanges().listen((_) {
      final next = _actorUid();
      if (!mounted || next == _streamUid) return;
      _scheduleBindStream(next);
    });
  }

  @override
  void dispose() {
    _bindGeneration++;
    _authSub?.cancel();
    unawaited(_notifSub?.cancel());
    _notifSub = null;
    super.dispose();
  }

  Future<void> _applyRead(
    String docId, {
    required String handledAction,
  }) async {
    try {
      await _firestore.collection('user_notifications').doc(docId).update({
        'read': true,
        'handledAction': handledAction,
        'handledAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> _onAcknowledge(UserNotificationInboxItem e) async {
    setState(() => _busyIds.add(e.docId));
    try {
      if (e.emergencyAlertId != null && e.emergencyAlertId!.isNotEmpty) {
        await _emergencyAlertService.acknowledgeAlert(e.emergencyAlertId!, _actorUid());
      }
      await _applyRead(e.docId, handledAction: 'acknowledged');
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('Acknowledge failed: $err'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busyIds.remove(e.docId));
    }
  }

  Future<void> _onResolved(UserNotificationInboxItem e) async {
    setState(() => _busyIds.add(e.docId));
    try {
      if (e.emergencyAlertId != null && e.emergencyAlertId!.isNotEmpty) {
        await _emergencyAlertService.resolveAlert(e.emergencyAlertId!);
      }
      await _applyRead(e.docId, handledAction: 'resolved');
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('Resolve failed: $err'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busyIds.remove(e.docId));
    }
  }

  Future<void> _onDismiss(UserNotificationInboxItem e) async {
    setState(() => _busyIds.add(e.docId));
    try {
      await _applyRead(e.docId, handledAction: 'read');
    } finally {
      if (mounted) setState(() => _busyIds.remove(e.docId));
    }
  }

  Future<void> _showMarkAsReadConfirmation(UserNotificationInboxItem e) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark as Read'),
        content: const Text('Mark this notification as read?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mark as Read'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _onDismiss(e);
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'emergency_alert':
        return Icons.warning_amber_rounded;
      case 'driver_docs_approved':
      case 'driver_docs_rejected':
        return Icons.badge_outlined;
      case 'owner_vehicle_approved':
      case 'owner_vehicle_rejected':
        return Icons.directions_car_outlined;
      default:
        return Icons.notifications_active_outlined;
    }
  }

  Color _accentForType(String type) {
    switch (type) {
      case 'emergency_alert':
        return Colors.red.shade700;
      case 'driver_docs_rejected':
      case 'owner_vehicle_rejected':
        return Colors.deepOrange;
      case 'driver_docs_approved':
      case 'owner_vehicle_approved':
        return const Color(0xFF2E7D32);
      default:
        return AppColors.primaryDark;
    }
  }

  String _handledRemark(UserNotificationInboxItem e) {
    switch (e.handledAction) {
      case 'acknowledged':
        return 'You acknowledged this alert.';
      case 'resolved':
        return 'You marked this as resolved.';
      case 'read':
        return 'Marked as read.';
      default:
        return '';
    }
  }

  String _formatTime(DateTime t) {
    if (t.millisecondsSinceEpoch <= 0) return '';
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${t.day}/${t.month}/${t.year}';
  }

  List<UserNotificationInboxItem> get _unreadEntries =>
      _entries.where((e) => e.unread).toList();

  List<UserNotificationInboxItem> get _readEntries => _entries
      .where((e) => !e.unread && (e.handledAction == 'read' || e.handledAction == null))
      .toList();

  List<UserNotificationInboxItem> get _acknowledgedEntries =>
      _entries.where((e) => e.handledAction == 'acknowledged').toList();

  List<UserNotificationInboxItem> get _resolvedEntries =>
      _entries.where((e) => e.handledAction == 'resolved').toList();

  Widget _buildTile(UserNotificationInboxItem e) {
    final accent = _accentForType(e.type);
    final busy = _busyIds.contains(e.docId);
    final isEmergency = e.type == 'emergency_alert';
    final hasLinked = e.emergencyAlertId != null && e.emergencyAlertId!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: e.unread ? accent.withOpacity(0.06) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: e.unread ? accent.withOpacity(0.35) : Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: accent.withOpacity(0.15),
                  child: Icon(_iconForType(e.type), color: accent, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.title,
                        style: TextStyle(
                          fontWeight: e.unread ? FontWeight.w700 : FontWeight.w600,
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                      ),
                      if (e.body.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          e.body,
                          style: const TextStyle(fontSize: 13, height: 1.35, color: Colors.black87),
                        ),
                      ],
                      if (_formatTime(e.createdAt).isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          _formatTime(e.createdAt),
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ],
                      if (!e.unread && _handledRemark(e).isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          _handledRemark(e),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[800],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (e.unread)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'New',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: accent),
                    ),
                  ),
              ],
            ),
            if (e.unread) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  if (widget.adminSectioned && isEmergency && hasLinked) ...[
                    OutlinedButton(
                      onPressed: busy ? null : () => _onAcknowledge(e),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: accent,
                        side: BorderSide(color: accent.withOpacity(0.7)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      child: busy
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                            )
                          : const Text('Acknowledge'),
                    ),
                    FilledButton(
                      onPressed: busy ? null : () => _onResolved(e),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      child: const Text('Resolved'),
                    ),
                  ],
                  TextButton(
                    onPressed: busy ? null : () => _showMarkAsReadConfirmation(e),
                    child: const Text('Mark as read'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAdminSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<UserNotificationInboxItem> items,
    String emptyMessage = 'Nothing in this section.',
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: items.isNotEmpty && (title == 'Unread' || items.length <= 3),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: Icon(icon, color: color, size: 22),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.textPrimary,
            ),
          ),
          subtitle: Text(
            '${items.length} Notification${items.length == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          children: [
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(emptyMessage, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              )
            else
              ...items.map(_buildTile),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminSectionedInbox() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAdminSection(
          title: 'Unread',
          icon: Icons.mark_email_unread_outlined,
          color: Colors.red.shade700,
          items: _unreadEntries,
          emptyMessage: 'No unread Notifications.',
        ),
        _buildAdminSection(
          title: 'Read',
          icon: Icons.drafts_outlined,
          color: AppColors.primary,
          items: _readEntries,
          emptyMessage: 'No Read Notifications.',
        ),
        _buildAdminSection(
          title: 'Acknowledged',
          icon: Icons.check_circle_outline,
          color: const Color(0xFF1565C0),
          items: _acknowledgedEntries,
          emptyMessage: 'No Acknowledged Alerts.',
        ),
        _buildAdminSection(
          title: 'Resolved',
          icon: Icons.task_alt_outlined,
          color: const Color(0xFF2E7D32),
          items: _resolvedEntries,
          emptyMessage: 'No Resolved Alerts.',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    final unread = _unreadEntries.length;

    final listPadding = widget.embedded
        ? EdgeInsets.zero
        : EdgeInsets.fromLTRB(isMobile ? 16 : 24, 8, isMobile ? 16 : 24, 24);

    Widget buildList() {
      if (_entries.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: Text(
              'No notifications yet.',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ),
        );
      }

      if (widget.adminSectioned) {
        return Padding(
          padding: listPadding,
          child: _buildAdminSectionedInbox(),
        );
      }

      final listView = ListView.builder(
        padding: listPadding,
        shrinkWrap: widget.embedded,
        physics: widget.embedded
            ? const NeverScrollableScrollPhysics()
            : null,
        itemCount: _entries.length,
        itemBuilder: (context, i) => _buildTile(_entries[i]),
      );

      if (widget.embedded || _entries.length <= 8) {
        return listView;
      }

      return Scrollbar(
        thumbVisibility: true,
        child: listView,
      );
    }

    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (unread > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade100),
                  ),
                  child: Text(
                    '$unread unread',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.red.shade800,
                    ),
                  ),
                ),
              ),
            ),
          buildList(),
        ],
      );
    }

    return Container(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(isMobile ? 16 : 24, isMobile ? 12 : 16, isMobile ? 16 : 24, 8),
            child: Row(
              children: [
                Icon(Icons.notifications_active, color: AppColors.primaryDark, size: 26),
                const SizedBox(width: 12),
                Text(
                  'Notifications',
                  style: TextStyle(
                    fontSize: isMobile ? 22 : 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const Spacer(),
                if (unread > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade100),
                    ),
                    child: Text(
                      '$unread unread',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.red.shade800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: buildList()),
        ],
      ),
    );
  }
}
