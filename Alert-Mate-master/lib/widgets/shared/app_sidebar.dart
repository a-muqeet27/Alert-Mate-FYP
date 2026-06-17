import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/app_colors.dart';
import '../../models/user.dart';
import '../../utils/sign_out_flow.dart';

/// Support / contact address shown in the app sidebar.
const String kAlertMateSupportEmail = 'alertmate.fyp@gmail.com';

/// Opens Gmail compose with [email] in the To field.
/// On mobile: uses mailto: to open native email app.
/// On web/desktop: uses Gmail web compose URL.
Future<void> launchGmailComposeTo(BuildContext context, String email) async {
  final trimmed = email.trim();
  if (trimmed.isEmpty) return;

  final gmailCompose = Uri.parse(
    'https://mail.google.com/mail/?view=cm&fs=1&to=${Uri.encodeComponent(trimmed)}',
  );
  final mailto = Uri(scheme: 'mailto', path: trimmed);

  final isMobile = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
       defaultTargetPlatform == TargetPlatform.iOS);

  try {
    if (isMobile) {
      if (await canLaunchUrl(mailto)) {
        final opened = await launchUrl(mailto, mode: LaunchMode.externalApplication);
        if (opened) return;
      }
      if (await canLaunchUrl(gmailCompose)) {
        await launchUrl(gmailCompose, mode: LaunchMode.externalApplication);
        return;
      }
    } else {
      if (await canLaunchUrl(gmailCompose)) {
        final opened = await launchUrl(gmailCompose, mode: LaunchMode.externalApplication);
        if (opened) return;
      }
      if (await canLaunchUrl(mailto)) {
        await launchUrl(mailto, mode: LaunchMode.externalApplication);
        return;
      }
    }
    throw Exception('No handler for mail links');
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Could not open email (${e.toString()})')),
      );
    }
  }
}

/// Reusable sidebar widget for all dashboards
/// Eliminates code duplication across admin, driver, owner, and passenger dashboards
class AppSidebar extends StatelessWidget {
  final String role;
  final User? user;
  final int selectedIndex;
  final Function(int) onMenuItemTap;
  final List<MenuItem> menuItems;
  final bool isCollapsible;
  final Color accentColor;
  final Color accentLightColor;
  /// When true, sign out navigates to [AdminAuthScreen] instead of mobile [AuthScreen].
  final bool adminPortal;

  const AppSidebar({
    Key? key,
    required this.role,
    this.user,
    required this.selectedIndex,
    required this.onMenuItemTap,
    required this.menuItems,
    this.isCollapsible = true,
    this.accentColor = AppColors.primary,
    this.accentLightColor = AppColors.primaryLight,
    this.adminPortal = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Check if we're inside a Drawer - if so, always expand
        final isInDrawer = _isInDrawer(context);
        // Responsive: collapse sidebar on small screens if enabled, but not if in drawer
        final shouldCollapse = isCollapsible && !isInDrawer && MediaQuery.of(context).size.width < 768;
        
        return Container(
          width: shouldCollapse ? 80 : (isInDrawer ? null : 280),
          color: AppColors.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(shouldCollapse),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  children: _buildMenuEntries(shouldCollapse),
                ),
              ),
              _buildUserProfile(context, shouldCollapse),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildMenuEntries(bool collapsed) {
    final widgets = <Widget>[];
    String? lastSection;
    for (var i = 0; i < menuItems.length; i++) {
      final item = menuItems[i];
      final section = item.section?.trim();
      if (!collapsed && section != null && section.isNotEmpty && section != lastSection) {
        widgets.add(_buildSectionHeader(section));
        lastSection = section;
      }
      widgets.add(_buildMenuItem(item, i, collapsed));
    }
    return widgets;
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 2),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  // Helper to check if we're inside a Drawer widget
  bool _isInDrawer(BuildContext context) {
    // Check if we're in a Drawer by looking up the widget tree
    try {
      final drawer = context.findAncestorWidgetOfExactType<Drawer>();
      return drawer != null;
    } catch (e) {
      return false;
    }
  }

  Widget _buildHeader(bool collapsed) {
    return Padding(
      padding: EdgeInsets.fromLTRB(collapsed ? 12 : 20, 20, collapsed ? 12 : 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!collapsed) ...[
            Row(
              children: [
                Image.asset(
                  'assets/images/Alert Mate New.png',
                  width: 32,
                  height: 24,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      Icons.security,
                      size: 24,
                      color: accentColor,
                    );
                  },
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ALERT MATE',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 3,
                            color: AppColors.azure
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Drowsiness Detection',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          if (collapsed) ...[
            Image.asset(
              'assets/images/Alert Mate New.png',
              width: 32,
              height: 24,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Text(
                  'AM',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: accentColor,
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 16),
          Container(
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 8 : 14, vertical: 4),
            decoration: BoxDecoration(
              color: accentLightColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              collapsed 
                ? (role == 'owner' ? 'VO' : role[0].toUpperCase())
                : (role == 'owner' ? 'Vehicle Owner' : role),
              style: TextStyle(
                color: accentColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  String _badgeText(int count) {
    if (count <= 0) return '';
    if (count > 99) return '99+';
    return '$count';
  }

  Widget _buildMenuItem(MenuItem item, int index, bool collapsed) {
    final bool isSelected = selectedIndex == index;
    final stream = item.unreadBadgeStream;

    Widget rowContent(int badgeCount) {
      final label = _badgeText(badgeCount);
      return Row(
        mainAxisSize: collapsed ? MainAxisSize.min : MainAxisSize.max,
        children: [
          AnimatedRotation(
            turns: isSelected ? 0.1 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  item.icon,
                  color: isSelected ? accentColor : Colors.grey[700],
                  size: 20,
                ),
                if (collapsed && label.isNotEmpty)
                  Positioned(
                    right: -10,
                    top: -8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.red.shade600,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      alignment: Alignment.center,
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!collapsed) ...[
            const SizedBox(width: 12),
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  color: isSelected ? accentColor : AppColors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 15,
                ),
                child: Text(item.title),
              ),
            ),
            if (label.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.shade600,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ],
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 12 : 18, vertical: 2),
      child: AnimatedScale(
        scale: isSelected ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: InkWell(
          onTap: () => onMenuItemTap(index),
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? accentLightColor : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: stream == null
                ? rowContent(0)
                : StreamBuilder<int>(
                    stream: stream,
                    initialData: 0,
                    builder: (context, snapshot) {
                      final c = snapshot.data ?? 0;
                      return rowContent(c);
                    },
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleSignOut(BuildContext context) {
    if (adminPortal) {
      return performSignOutAndGoToAdminAuth(context);
    }
    return performSignOutAndGoToAuth(context);
  }

  String _profileInitial() {
    final n = (user?.firstName ?? '').trim();
    if (n.isEmpty) return 'U';
    return n[0].toUpperCase();
  }

  Widget _buildUserProfile(BuildContext context, bool collapsed) {
    return Column(
      children: [
        Container(
          margin: EdgeInsets.all(collapsed ? 8 : 16),
          padding: EdgeInsets.all(collapsed ? 8 : 12),
          child: Column(
            children: [
              collapsed
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: accentColor,
                          child: Text(
                            _profileInitial(),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        IconButton(
                          tooltip: 'Sign Out',
                          onPressed: () => _handleSignOut(context),
                          icon: const Icon(Icons.logout_rounded, size: 20, color: AppColors.primary),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: accentColor,
                          child: Text(
                            _profileInitial(),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user?.fullName ?? 'User',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                user?.email ?? 'user@example.com',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Sign Out',
                          onPressed: () => _handleSignOut(context),
                          icon: const Icon(Icons.logout_rounded, size: 20, color: AppColors.primary),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                        ),
                      ],
                    ),
              if (!collapsed) ...[
                const SizedBox(height: 16),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => launchGmailComposeTo(context, kAlertMateSupportEmail),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.email_outlined, size: 18, color: AppColors.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              kAlertMateSupportEmail,
                              style: const TextStyle(fontSize: 13, color: AppColors.primary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Menu item model for sidebar
class MenuItem {
  final IconData icon;
  final String title;
  /// Optional section label shown above the first item in a group.
  final String? section;
  final Stream<int>? unreadBadgeStream;

  const MenuItem({
    required this.icon,
    required this.title,
    this.section,
    this.unreadBadgeStream,
  });
}
