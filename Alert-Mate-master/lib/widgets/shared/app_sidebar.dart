import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../models/user.dart';
import '../../auth_screen.dart';
import '../../utils/page_transitions.dart';

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
          width: shouldCollapse ? 80 : (isInDrawer ? null : 290),
          color: AppColors.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(shouldCollapse),
              const SizedBox(height: 16),
              ...menuItems.asMap().entries.map((entry) {
                return _buildMenuItem(
                  entry.value.icon,
                  entry.value.title,
                  entry.key,
                  shouldCollapse,
                );
              }).toList(),
              const Spacer(),
              _buildUserProfile(context, shouldCollapse),
            ],
          ),
        );
      },
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
      padding: EdgeInsets.fromLTRB(collapsed ? 12 : 24, 32, collapsed ? 12 : 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!collapsed) ...[
            Row(
              children: [
                Image.asset(
                  'assets/images/Alert Mate.png',
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
              'assets/images/Alert Mate.png',
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

  Widget _buildMenuItem(IconData icon, String title, int index, bool collapsed) {
    final bool isSelected = selectedIndex == index;
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
            child: Row(
              mainAxisSize: collapsed ? MainAxisSize.min : MainAxisSize.max,
              children: [
                AnimatedRotation(
                  turns: isSelected ? 0.1 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    icon,
                    color: isSelected ? accentColor : Colors.grey[700],
                    size: 20,
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
                      child: Text(title),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserProfile(BuildContext context, bool collapsed) {
    return Column(
      children: [
        Container(
          margin: EdgeInsets.all(collapsed ? 8 : 16),
          padding: EdgeInsets.all(collapsed ? 8 : 12),
          child: Column(
            children: [
              Row(
                mainAxisSize: collapsed ? MainAxisSize.min : MainAxisSize.max,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: accentColor,
                    child: Text(
                      user?.firstName[0].toUpperCase() ?? 'U',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (!collapsed) ...[
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
                    Icon(Icons.notifications_outlined, size: 20, color: Colors.grey[600]),
                  ],
                ],
              ),
              if (!collapsed) ...[
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Sign Out'),
                        content: const Text('Are you sure you want to sign out? You will need to sign in again to access your dashboard.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Sign Out'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      Navigator.pushReplacement(
                        context,
                        FadeScalePageRoute(page: const AuthScreen()),
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.exit_to_app, size: 18, color: Colors.grey[700]),
                        const SizedBox(width: 10),
                        const Text(
                          'Sign Out',
                          style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                        ),
                      ],
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

  const MenuItem({
    required this.icon,
    required this.title,
  });
}
