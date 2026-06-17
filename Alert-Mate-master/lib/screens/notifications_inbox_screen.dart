import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/user.dart';
import '../models/user_notification_inbox_item.dart';
import '../services/emergency_alert_service.dart';
import '../utils/dashboard_responsive.dart';
import '../widgets/dashboard_detail_dialog_theme.dart';

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
        backgroundColor: DashboardDetailDialogTheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.mark_email_read_outlined, color: AppColors.primary),
        ),
        title: const Text('Mark as Read'),
        content: const Text(
          'Mark this notification as read? You can still find it in your inbox later.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
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
        return AppColors.danger;
      case 'driver_docs_rejected':
      case 'owner_vehicle_rejected':
        return AppColors.warning;
      case 'driver_docs_approved':
      case 'owner_vehicle_approved':
        return AppColors.success;
      default:
        return AppColors.primary;
    }
  }

  Color _accentLightForType(String type) {
    switch (type) {
      case 'emergency_alert':
        return AppColors.dangerLight;
      case 'driver_docs_rejected':
      case 'owner_vehicle_rejected':
        return AppColors.warningLight;
      case 'driver_docs_approved':
      case 'owner_vehicle_approved':
        return AppColors.secondaryLight;
      default:
        return AppColors.primaryLight;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'emergency_alert':
        return 'Emergency';
      case 'driver_docs_approved':
        return 'Docs Approved';
      case 'driver_docs_rejected':
        return 'Docs Rejected';
      case 'owner_vehicle_approved':
        return 'Vehicle Approved';
      case 'owner_vehicle_rejected':
        return 'Vehicle Rejected';
      default:
        return 'Alert';
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
    if (diff.inDays < 7) return '${diff.inDays}d ago';
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

  Widget _buildSummaryBanner({required bool isMobile}) {
    final unread = _unreadEntries.length;
    final total = _entries.length;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.all(isMobile ? 14 : 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primaryDark,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.notifications_active_outlined, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unread > 0 ? '$unread unread notification${unread == 1 ? '' : 's'}' : 'All caught up',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isMobile ? 15 : 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  total == 0 ? 'No messages in your inbox yet' : '$total total in inbox',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: isMobile ? 12 : 13,
                  ),
                ),
              ],
            ),
          ),
          if (unread > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$unread',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.75)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.notifications_none_rounded, color: AppColors.primary, size: 36),
          ),
          const SizedBox(height: 14),
          const Text(
            'No notifications yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Alerts about emergencies, approvals, and account updates will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String title, {int? count}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: 0.2,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTile(UserNotificationInboxItem e, {required bool isMobile}) {
    final accent = _accentForType(e.type);
    final accentLight = _accentLightForType(e.type);
    final busy = _busyIds.contains(e.docId);
    final isEmergency = e.type == 'emergency_alert';
    final hasLinked = e.emergencyAlertId != null && e.emergencyAlertId!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: e.unread ? accent.withValues(alpha: 0.35) : AppColors.border.withValues(alpha: 0.8),
        ),
        boxShadow: [
          BoxShadow(
            color: e.unread ? accent.withValues(alpha: 0.08) : AppColors.shadowLight,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                color: e.unread ? accent : Colors.transparent,
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(isMobile ? 12 : 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: accentLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(_iconForType(e.type), color: accent, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: accentLight,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        _typeLabel(e.type),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: accent,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ),
                                    if (e.unread)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: AppColors.dangerLight,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Text(
                                          'NEW',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.danger,
                                            letterSpacing: 0.4,
                                          ),
                                        ),
                                      ),
                                    if (_formatTime(e.createdAt).isNotEmpty)
                                      Text(
                                        _formatTime(e.createdAt),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  e.title,
                                  style: TextStyle(
                                    fontWeight: e.unread ? FontWeight.w700 : FontWeight.w600,
                                    fontSize: isMobile ? 15 : 16,
                                    color: AppColors.textPrimary,
                                    height: 1.25,
                                  ),
                                ),
                                if (e.body.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    e.body,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      height: 1.45,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                                if (!e.unread && _handledRemark(e).isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: AppColors.background.withValues(alpha: 0.7),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          e.handledAction == 'resolved'
                                              ? Icons.task_alt_outlined
                                              : e.handledAction == 'acknowledged'
                                                  ? Icons.check_circle_outline
                                                  : Icons.done_all_outlined,
                                          size: 16,
                                          color: AppColors.textSecondary,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            _handledRemark(e),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (e.unread) ...[
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.end,
                          children: [
                            if (widget.adminSectioned && isEmergency && hasLinked) ...[
                              OutlinedButton.icon(
                                onPressed: busy ? null : () => _onAcknowledge(e),
                                icon: busy
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                                      )
                                    : const Icon(Icons.check_circle_outline, size: 18),
                                label: const Text('Acknowledge'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: accent,
                                  side: BorderSide(color: accent.withValues(alpha: 0.7)),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                              FilledButton.icon(
                                onPressed: busy ? null : () => _onResolved(e),
                                icon: const Icon(Icons.task_alt_outlined, size: 18),
                                label: const Text('Resolved'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: accent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ],
                            TextButton.icon(
                              onPressed: busy ? null : () => _showMarkAsReadConfirmation(e),
                              icon: const Icon(Icons.mark_email_read_outlined, size: 18),
                              label: const Text('Mark as read'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdminSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<UserNotificationInboxItem> items,
    required bool isMobile,
    String emptyMessage = 'Nothing in this section.',
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.75)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: items.isNotEmpty && (title == 'Unread' || items.length <= 3),
          tilePadding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 4),
          childrenPadding: EdgeInsets.fromLTRB(isMobile ? 10 : 14, 0, isMobile ? 10 : 14, 14),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.textPrimary,
            ),
          ),
          subtitle: Text(
            '${items.length} notification${items.length == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          children: [
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  emptyMessage,
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              )
            else
              ...items.map((e) => _buildTile(e, isMobile: isMobile)),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminSectionedInbox({required bool isMobile}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSummaryBanner(isMobile: isMobile),
        _buildAdminSection(
          title: 'Unread',
          icon: Icons.mark_email_unread_outlined,
          color: AppColors.danger,
          items: _unreadEntries,
          isMobile: isMobile,
          emptyMessage: 'No unread notifications.',
        ),
        _buildAdminSection(
          title: 'Read',
          icon: Icons.drafts_outlined,
          color: AppColors.primary,
          items: _readEntries,
          isMobile: isMobile,
          emptyMessage: 'No read notifications.',
        ),
        _buildAdminSection(
          title: 'Acknowledged',
          icon: Icons.check_circle_outline,
          color: AppColors.azure,
          items: _acknowledgedEntries,
          isMobile: isMobile,
          emptyMessage: 'No acknowledged alerts.',
        ),
        _buildAdminSection(
          title: 'Resolved',
          icon: Icons.task_alt_outlined,
          color: AppColors.success,
          items: _resolvedEntries,
          isMobile: isMobile,
          emptyMessage: 'No resolved alerts.',
        ),
      ],
    );
  }

  Widget _buildStandardInbox({required bool isMobile}) {
    final unread = _unreadEntries;
    final read = _entries.where((e) => !e.unread).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSummaryBanner(isMobile: isMobile),
        if (unread.isNotEmpty) ...[
          _buildSectionLabel('Unread', count: unread.length),
          ...unread.map((e) => _buildTile(e, isMobile: isMobile)),
          if (read.isNotEmpty) const SizedBox(height: 6),
        ],
        if (read.isNotEmpty) ...[
          _buildSectionLabel(read.isEmpty ? 'Inbox' : 'Earlier', count: read.length),
          ...read.map((e) => _buildTile(e, isMobile: isMobile)),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = DashboardLayout.isMobile(context);
    final unread = _unreadEntries.length;

    final listPadding = widget.embedded
        ? EdgeInsets.zero
        : EdgeInsets.fromLTRB(isMobile ? 16 : 24, 8, isMobile ? 16 : 24, 24);

    Widget buildList() {
      if (_entries.isEmpty) {
        return Padding(
          padding: listPadding,
          child: _buildEmptyState(),
        );
      }

      if (widget.adminSectioned) {
        return Padding(
          padding: listPadding,
          child: _buildAdminSectionedInbox(isMobile: isMobile),
        );
      }

      final content = Padding(
        padding: listPadding,
        child: _buildStandardInbox(isMobile: isMobile),
      );

      if (widget.embedded) {
        return content;
      }

      return Scrollbar(
        thumbVisibility: _entries.length > 8,
        child: SingleChildScrollView(child: content),
      );
    }

    if (widget.embedded) {
      return buildList();
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
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.notifications_active_outlined, color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notifications',
                        style: TextStyle(
                          fontSize: isMobile ? 22 : 26,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        unread > 0 ? '$unread unread' : 'All caught up',
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (unread > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.dangerLight,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      '$unread',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.danger,
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
