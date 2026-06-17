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
  final ValueChanged<User>? onUserUpdated;
  final bool showDriverAlerts;
  final bool audioAlertsEnabled;
  final String sensitivityLevel;
  final ValueChanged<bool>? onAudioAlertsChanged;
  final ValueChanged<String>? onSensitivityChanged;

  const AppSettingsPage({
    super.key,
    required this.user,
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

  Widget _buildPasswordStrengthIndicator() {
    final password = _newPasswordController.text;
    final strength = _calculatePasswordStrength(password);

    Color strengthColor;
    String strengthText;
    double strengthValue;

    switch (strength) {
      case 'strong':
        strengthColor = Colors.green;
        strengthText = 'Strong';
        strengthValue = 1.0;
        break;
      case 'medium':
        strengthColor = Colors.orange;
        strengthText = 'Medium';
        strengthValue = 0.6;
        break;
      case 'weak':
        strengthColor = Colors.red;
        strengthText = 'Weak';
        strengthValue = 0.3;
        break;
      default:
        strengthColor = Colors.grey;
        strengthText = '';
        strengthValue = 0.0;
    }

    if (password.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: strengthValue,
                  minHeight: 6,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(strengthColor),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              strengthText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: strengthColor,
              ),
            ),
          ],
        ),
        if (strength != 'strong') ...[
          const SizedBox(height: 6),
          Text(
            _getPasswordRequirements(password),
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = DashboardLayout.isMobile(context);
    return DashboardLayout.scrollPage(
      context: context,
      desktopTitle: 'Settings',
      desktopSubtitle: 'Manage your account, security, and preferences',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSection(
            title: 'Account',
            subtitle: 'Update your profile information',
            child: Form(
              key: _profileFormKey,
              child: Column(
                children: [
                  _readOnlyField(label: 'Email', value: widget.user.email),
                  const SizedBox(height: 14),
                  _textField(
                    controller: _firstNameController,
                    label: 'First Name',
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
                    validator: FormValidators.validateLastName,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
                    ],
                    keyboardType: TextInputType.name,
                  ),
                  const SizedBox(height: 14),
                  _textField(
                    controller: _phoneController,
                    label: 'Phone (digits only)',
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
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: _savingProfile ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: _savingProfile
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Save Profile'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: isMobile ? 14 : 18),
          _buildSection(
            title: 'Security',
            subtitle: 'Change your account password',
            child: Form(
              key: _passwordFormKey,
              child: Column(
                children: [
                  _passwordField(
                    controller: _currentPasswordController,
                    label: 'Current Password',
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
                    hintText: 'Mix of letters, numbers & special characters (min 8)',
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
                    obscure: _obscureConfirmPassword,
                    onToggle: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Please confirm your new password';
                      if (value != _newPasswordController.text) return 'Passwords do not match';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: _changingPassword ? null : _changePassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: _changingPassword
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Change Password'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.showDriverAlerts &&
              widget.onAudioAlertsChanged != null &&
              widget.onSensitivityChanged != null) ...[
            SizedBox(height: isMobile ? 14 : 18),
            _buildSection(
              title: 'Driver Alerts',
              subtitle: 'Drowsiness monitoring preferences',
              child: DriverAlertSettingsSection(
                audioAlertsEnabled: widget.audioAlertsEnabled,
                sensitivityLevel: widget.sensitivityLevel,
                onAudioAlertsChanged: widget.onAudioAlertsChanged!,
                onSensitivityChanged: widget.onSensitivityChanged!,
              ),
            ),
          ],
          SizedBox(height: isMobile ? 14 : 18),
          _buildSection(
            title: 'Legal',
            subtitle: 'Review our policies',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton(
                  onPressed: () => showPrivacyPolicyDialog(context),
                  child: const Text('Privacy Policy'),
                ),
                OutlinedButton(
                  onPressed: () => showTermsDialog(context),
                  child: const Text('Terms and Conditions'),
                ),
              ],
            ),
          ),
          SizedBox(height: isMobile ? 14 : 18),
          _buildSection(
            title: 'Support',
            subtitle: 'Get help from the Alert Mate team',
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => launchGmailComposeTo(context, kAlertMateSupportEmail),
                icon: const Icon(Icons.mail_outline),
                label: Text(kAlertMateSupportEmail),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _readOnlyField({required String label, required String value}) {
    return TextFormField(
      initialValue: value,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String? Function(String?) validator,
    List<TextInputFormatter>? inputFormatters,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      inputFormatters: inputFormatters,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
    String? hintText,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        hintStyle: TextStyle(fontSize: 12, color: Colors.grey[500]),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, color: AppColors.primary),
          onPressed: onToggle,
        ),
      ),
    );
  }
}