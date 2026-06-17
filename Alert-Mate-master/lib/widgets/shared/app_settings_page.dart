import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/app_colors.dart';
import '../../models/user.dart';
import '../../services/user_profile_service.dart';
import '../../utils/dashboard_responsive.dart';
import '../../utils/form_validators.dart';
import '../../widgets/legal_document_dialog.dart';
import 'app_sidebar.dart';
import 'driver_alert_settings_section.dart';

class AppSettingsPage extends StatefulWidget {
  final User user;
  final String? sessionRole;
  final ValueChanged<User>? onUserUpdated;
  final bool showDriverAlerts;
  final bool audioAlertsEnabled;
  final String sensitivityLevel;
  final ValueChanged<bool>? onAudioAlertsChanged;
  final ValueChanged<String>? onSensitivityChanged;

  const AppSettingsPage({
    super.key,
    required this.user,
    this.sessionRole,
    this.onUserUpdated,
    this.showDriverAlerts = false,
    this.audioAlertsEnabled = true,
    this.sensitivityLevel = 'Medium',
    this.onAudioAlertsChanged,
    this.onSensitivityChanged,
  });

  @override
  State<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<AppSettingsPage> {
  final _profileService = UserProfileService();
  final _profileFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();

  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _phoneController;
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _savingProfile = false;
  bool _changingPassword = false;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController(text: widget.user.firstName);
    _lastNameController = TextEditingController(text: widget.user.lastName);
    final phoneDigits = widget.user.phone.replaceAll(RegExp(r'[^0-9]'), '');
    _phoneController = TextEditingController(text: phoneDigits);
  }

  @override
  void didUpdateWidget(covariant AppSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.id != widget.user.id) {
      _firstNameController.text = widget.user.firstName;
      _lastNameController.text = widget.user.lastName;
      final phoneDigits = widget.user.phone.replaceAll(RegExp(r'[^0-9]'), '');
      _phoneController.text = phoneDigits;
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_profileFormKey.currentState!.validate()) return;
    setState(() => _savingProfile = true);
    try {
      final updated = await _profileService.updateProfile(
        userId: widget.user.id,
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
        phone: _phoneController.text,
      );
      widget.onUserUpdated?.call(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _changePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;
    if (_newPasswordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New passwords do not match.')),
      );
      return;
    }

    setState(() => _changingPassword = true);
    try {
      await _profileService.changePassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
      );
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password changed successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _changingPassword = false);
    }
  }

  String? _validateStrongPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Password must contain at least one uppercase letter';
    }
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Password must contain at least one lowercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Password must contain at least one number';
    }
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(value)) {
      return 'Password must contain at least one special character';
    }
    return null;
  }

  String _calculatePasswordStrength(String password) {
    if (password.isEmpty) return 'none';
    if (password.length < 8) return 'weak';

    int strength = 0;
    if (RegExp(r'[A-Z]').hasMatch(password)) strength++;
    if (RegExp(r'[a-z]').hasMatch(password)) strength++;
    if (RegExp(r'[0-9]').hasMatch(password)) strength++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) strength++;
    if (password.length >= 12) strength++;

    if (strength >= 4) return 'strong';
    if (strength >= 2) return 'medium';
    return 'weak';
  }

  String _getPasswordRequirements(String password) {
    List<String> missing = [];
    if (password.length < 8) missing.add('8+ characters');
    if (!RegExp(r'[A-Z]').hasMatch(password)) missing.add('uppercase letter');
    if (!RegExp(r'[a-z]').hasMatch(password)) missing.add('lowercase letter');
    if (!RegExp(r'[0-9]').hasMatch(password)) missing.add('number');
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) missing.add('special character');
    if (missing.isEmpty) return '';
    return 'Missing: ${missing.join(', ')}';
  }

  String _userInitials() {
    final first = widget.user.firstName.trim();
    final last = widget.user.lastName.trim();
    if (first.isNotEmpty && last.isNotEmpty) {
      return '${first[0]}${last[0]}'.toUpperCase();
    }
    if (first.isNotEmpty) return first[0].toUpperCase();
    if (widget.user.email.isNotEmpty) return widget.user.email[0].toUpperCase();
    return '?';
  }

  String _resolveLoggedInRole() {
    final session = widget.sessionRole?.trim();
    if (session != null && session.isNotEmpty) return session;

    final active = widget.user.role?.trim();
    if (active != null && active.isNotEmpty) return active;

    final roles = widget.user.roles;
    if (roles != null && roles.isNotEmpty) return roles.first;

    return 'user';
  }

  IconData _roleIcon(String role) {
    switch (role.toLowerCase()) {
      case 'driver':
        return Icons.directions_car_filled_outlined;
      case 'passenger':
        return Icons.person_outline;
      case 'owner':
        return Icons.business_center_outlined;
      case 'admin':
        return Icons.admin_panel_settings_outlined;
      default:
        return Icons.badge_outlined;
    }
  }

  String _formatRole(String? role) {
    if (role == null || role.isEmpty) return 'User';
    return role[0].toUpperCase() + role.substring(1).toLowerCase();
  }

  Color _roleColor(String role) {
    switch (role.toLowerCase()) {
      case 'driver':
        return AppColors.driverPrimary;
      case 'passenger':
        return AppColors.passengerPrimary;
      case 'owner':
        return AppColors.azure;
      case 'admin':
        return const Color(0xFF9C27B0);
      default:
        return AppColors.primary;
    }
  }

  Widget _buildPasswordStrengthIndicator() {
    final password = _newPasswordController.text;
    final strength = _calculatePasswordStrength(password);

    Color strengthColor;
    String strengthText;
    double strengthValue;

    switch (strength) {
      case 'strong':
        strengthColor = AppColors.success;
        strengthText = 'Strong';
        strengthValue = 1.0;
        break;
      case 'medium':
        strengthColor = AppColors.warning;
        strengthText = 'Medium';
        strengthValue = 0.6;
        break;
      case 'weak':
        strengthColor = AppColors.danger;
        strengthText = 'Weak';
        strengthValue = 0.3;
        break;
      default:
        strengthColor = AppColors.lightGray;
        strengthText = '';
        strengthValue = 0.0;
    }

    if (password.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: strengthValue,
                  minHeight: 6,
                  backgroundColor: AppColors.border,
                  valueColor: AlwaysStoppedAnimation<Color>(strengthColor),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              strengthText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: strengthColor,
              ),
            ),
          ],
        ),
        if (strength != 'strong') ...[
          const SizedBox(height: 6),
          Text(
            _getPasswordRequirements(password),
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = DashboardLayout.isMobile(context);
    final gap = isMobile ? 14.0 : 18.0;
    final role = _resolveLoggedInRole();
    final roleLabel = _formatRole(role);
    final roleColor = _roleColor(role);

    return DashboardLayout.scrollPage(
      context: context,
      desktopTitle: 'Settings',
      desktopSubtitle: 'Manage your account, security, and preferences',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildProfileHeader(isMobile: isMobile, roleLabel: roleLabel, roleColor: roleColor),
          SizedBox(height: gap),
          _buildSection(
            isMobile: isMobile,
            icon: Icons.person_outline_rounded,
            title: 'Account',
            subtitle: 'Update your Profile Information',
            child: Form(
              key: _profileFormKey,
              child: Column(
                children: [
                  _readOnlyField(
                    label: 'Email',
                    value: widget.user.email,
                    icon: Icons.email_outlined,
                  ),
                  const SizedBox(height: 14),
                  if (isMobile) ...[
                    _textField(
                      controller: _firstNameController,
                      label: 'First Name',
                      icon: Icons.badge_outlined,
                      validator: FormValidators.validateFirstName,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
                      ],
                      keyboardType: TextInputType.name,
                    ),
                    const SizedBox(height: 14),
                    _textField(
                      controller: _lastNameController,
                      label: 'Last Name',
                      icon: Icons.badge_outlined,
                      validator: FormValidators.validateLastName,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
                      ],
                      keyboardType: TextInputType.name,
                    ),
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _textField(
                            controller: _firstNameController,
                            label: 'First Name',
                            icon: Icons.badge_outlined,
                            validator: FormValidators.validateFirstName,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
                            ],
                            keyboardType: TextInputType.name,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _textField(
                            controller: _lastNameController,
                            label: 'Last Name',
                            icon: Icons.badge_outlined,
                            validator: FormValidators.validateLastName,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
                            ],
                            keyboardType: TextInputType.name,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 14),
                  _textField(
                    controller: _phoneController,
                    label: 'Phone Number',
                    icon: Icons.phone_outlined,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Phone number is required';
                      }
                      if (value.trim().length < 7) {
                        return 'Phone number must be at least 7 digits';
                      }
                      return null;
                    },
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(15),
                    ],
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 18),
                  _primaryButton(
                    label: 'Save Profile',
                    icon: Icons.save_outlined,
                    loading: _savingProfile,
                    onPressed: _savingProfile ? null : _saveProfile,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: gap),
          _buildSection(
            isMobile: isMobile,
            icon: Icons.lock_outline_rounded,
            title: 'Security',
            subtitle: 'Change your Account Password',
            child: Form(
              key: _passwordFormKey,
              child: Column(
                children: [
                  _passwordField(
                    controller: _currentPasswordController,
                    label: 'Current Password',
                    icon: Icons.vpn_key_outlined,
                    obscure: _obscureCurrentPassword,
                    onToggle: () => setState(() => _obscureCurrentPassword = !_obscureCurrentPassword),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Current password is required';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  _passwordField(
                    controller: _newPasswordController,
                    label: 'New Password',
                    icon: Icons.lock_reset_rounded,
                    hintText: 'Mix of letters, numbers & symbols (min 8)',
                    obscure: _obscureNewPassword,
                    onToggle: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
                    onChanged: (_) => setState(() {}),
                    validator: _validateStrongPassword,
                  ),
                  _buildPasswordStrengthIndicator(),
                  const SizedBox(height: 14),
                  _passwordField(
                    controller: _confirmPasswordController,
                    label: 'Confirm New Password',
                    icon: Icons.verified_user_outlined,
                    obscure: _obscureConfirmPassword,
                    onToggle: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Please confirm your new password';
                      if (value != _newPasswordController.text) return 'Passwords do not match';
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),
                  _primaryButton(
                    label: 'Change Password',
                    icon: Icons.shield_outlined,
                    loading: _changingPassword,
                    onPressed: _changingPassword ? null : _changePassword,
                  ),
                ],
              ),
            ),
          ),
          if (widget.showDriverAlerts &&
              widget.onAudioAlertsChanged != null &&
              widget.onSensitivityChanged != null) ...[
            SizedBox(height: gap),
            _buildSection(
              isMobile: isMobile,
              icon: Icons.notifications_active_outlined,
              title: 'Driver Alerts',
              subtitle: 'Drowsiness Monitoring Preferences',
              child: DriverAlertSettingsSection(
                isMobile: isMobile,
                audioAlertsEnabled: widget.audioAlertsEnabled,
                sensitivityLevel: widget.sensitivityLevel,
                onAudioAlertsChanged: widget.onAudioAlertsChanged!,
                onSensitivityChanged: widget.onSensitivityChanged!,
              ),
            ),
          ],
          SizedBox(height: gap),
          _buildSection(
            isMobile: isMobile,
            icon: Icons.gavel_outlined,
            title: 'Legal',
            subtitle: 'Review our Policies',
            child: _buildGroupedLinks(
              children: [
                _linkTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy Policy',
                  subtitle: 'How we handle your data',
                  onTap: () => showPrivacyPolicyDialog(context),
                ),
                _divider(),
                _linkTile(
                  icon: Icons.description_outlined,
                  title: 'Terms and Conditions',
                  subtitle: 'Rules for using Alert Mate',
                  onTap: () => showTermsDialog(context),
                ),
              ],
            ),
          ),
          SizedBox(height: gap),
          _buildSection(
            isMobile: isMobile,
            icon: Icons.support_agent_outlined,
            title: 'Support',
            subtitle: 'Get Help from the Alert Mate Team',
            child: _buildGroupedLinks(
              children: [
                _linkTile(
                  icon: Icons.mail_outline_rounded,
                  title: 'Email Support',
                  subtitle: kAlertMateSupportEmail,
                  onTap: () => launchGmailComposeTo(context, kAlertMateSupportEmail),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleChip({required String roleLabel, required Color roleColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: roleColor.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        roleLabel,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildProfileHeader({
    required bool isMobile,
    required String roleLabel,
    required Color roleColor,
  }) {
    final displayName = widget.user.fullName.trim().isNotEmpty
        ? widget.user.fullName.trim()
        : widget.user.email;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 18 : 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primaryDark,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: isMobile ? 56 : 64,
            height: isMobile ? 56 : 64,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.45), width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              _userInitials(),
              style: TextStyle(
                color: Colors.white,
                fontSize: isMobile ? 20 : 24,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      displayName,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isMobile ? 18 : 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    _buildRoleChip(roleLabel: roleLabel, roleColor: roleColor),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.email_outlined,
                      size: isMobile ? 14 : 15,
                      color: Colors.white.withValues(alpha: 0.82),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.user.email,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: isMobile ? 13 : 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      _roleIcon(roleLabel),
                      size: isMobile ? 14 : 15,
                      color: Colors.white.withValues(alpha: 0.82),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Logged in as $roleLabel',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: isMobile ? 12 : 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!isMobile)
            Icon(
              Icons.settings_rounded,
              color: Colors.white.withValues(alpha: 0.35),
              size: 48,
            ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required bool isMobile,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: isMobile ? 16 : 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: isMobile ? 12 : 13,
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  Widget _buildGroupedLinks({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
      ),
      child: Column(children: children),
    );
  }

  Widget _divider() => Divider(
        height: 1,
        thickness: 1,
        color: AppColors.border.withValues(alpha: 0.8),
        indent: 56,
      );

  Widget _linkTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required bool loading,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Icon(icon, size: 20),
        label: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    IconData? icon,
    String? hintText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      hintStyle: TextStyle(fontSize: 12, color: AppColors.textSecondary.withValues(alpha: 0.85)),
      filled: true,
      fillColor: AppColors.background.withValues(alpha: 0.45),
      prefixIcon: icon != null ? Icon(icon, color: AppColors.primary, size: 20) : null,
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.border.withValues(alpha: 0.9)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.border.withValues(alpha: 0.9)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _readOnlyField({
    required String label,
    required String value,
    IconData? icon,
  }) {
    return TextFormField(
      initialValue: value,
      readOnly: true,
      decoration: _fieldDecoration(label: label, icon: icon).copyWith(
        fillColor: AppColors.primaryLight.withValues(alpha: 0.35),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String? Function(String?) validator,
    IconData? icon,
    List<TextInputFormatter>? inputFormatters,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      inputFormatters: inputFormatters,
      keyboardType: keyboardType,
      decoration: _fieldDecoration(label: label, icon: icon),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
    IconData? icon,
    String? hintText,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      onChanged: onChanged,
      decoration: _fieldDecoration(
        label: label,
        icon: icon,
        hintText: hintText,
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: AppColors.primary,
            size: 20,
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }
}
