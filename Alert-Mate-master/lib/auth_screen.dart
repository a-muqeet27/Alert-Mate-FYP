// COMPLETE FIXED AUTH_SCREEN.DART
// Replace your _handleAuth() method with this updated version

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart' hide User;
import 'models/user.dart';
import 'package:country_picker/country_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/firebase_auth_service.dart';
import 'dashboards/driver_dashboard.dart';
import 'dashboards/passenger_dashboard.dart';
import 'dashboards/owner_dashboard.dart';
import 'screens/driver_documents_gate_screen.dart';
import 'utils/page_transitions.dart';
import 'constants/app_colors.dart';
import 'utils/form_validators.dart';
import 'widgets/alert_mate_branding.dart';

class AuthScreen extends StatefulWidget {
  final int? initialDashboardIndex;
  final bool? initialIsSignIn;
  final bool isOwnerBecomingDriver; // NEW: Added this parameter

  const AuthScreen({
    Key? key,
    this.initialDashboardIndex,
    this.initialIsSignIn,
    this.isOwnerBecomingDriver = false, // NEW: Default to false
  }) : super(key: key);

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with TickerProviderStateMixin {
  // ... all your existing variables stay the same ...
  bool isSignIn = true;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  int _selectedDashboard = 0;
  late AnimationController _animationController;
  late AnimationController _slideController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  String _selectedDialCode = '+1';
  String _selectedCountryIso = 'US';

  final _formKey = GlobalKey<FormState>();
  final FirebaseAuthService _authService = FirebaseAuthService();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  // ... all your existing helper methods stay the same ...
  String _getSelectedRole() {
    switch (_selectedDashboard) {
      case 0: return 'driver';
      case 1: return 'passenger';
      case 2: return 'owner';
      default: return 'driver';
    }
  }

  bool _hasRole(User user, String role) {
    final roles = user.roles ?? [];
    return roles.contains(role) || user.role == role;
  }

  Future<bool> _validateAndPrepareRoleAccess(User user) async {
    final selectedRole = _getSelectedRole();

    // Owner -> driver edge case: allowed only when coming from owner flow.
    if (selectedRole == 'driver' &&
        widget.isOwnerBecomingDriver &&
        _hasRole(user, 'owner')) {
      await _authService.addDriverRoleForOwner(user.id);
      return true;
    }

    // Regular role access must already exist.
    if (!_hasRole(user, selectedRole)) {
      return false;
    }

    // Keep active role aligned with selected login role.
    try {
      await _authService.updateActiveRole(user.id, selectedRole);
    } catch (_) {}
    return true;
  }

  String _getSelectedRoleLabel() {
    switch (_selectedDashboard) {
      case 0: return 'Driver';
      case 1: return 'Passenger';
      case 2: return 'Vehicle Owner';
      default: return 'Driver';
    }
  }

  String _phoneHintForCountry() {
    switch (_selectedCountryIso.toUpperCase()) {
      case 'PK':
        return '03XX-XXXXXXX';
      case 'US':
      case 'CA':
        return '(XXX) XXX-XXXX';
      case 'GB':
        return '07XXX XXXXXX';
      case 'IN':
        return 'XXXXX-XXXXX';
      default:
        return 'Enter local phone number';
    }
  }

  String? _validatePhoneByCountry(String value) {
    return FormValidators.validatePhone(value, countryIso: _selectedCountryIso);
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );

    _animationController.forward();
    _slideController.forward();
    _scaleController.forward();

    // Initialize with passed parameters
    if (widget.initialDashboardIndex != null) {
      _selectedDashboard = widget.initialDashboardIndex!;
    }
    if (widget.initialIsSignIn != null) {
      isSignIn = widget.initialIsSignIn!;
    }

    // NEW: If owner becoming driver, set to driver role and signup mode
    if (widget.isOwnerBecomingDriver) {
      _selectedDashboard = 0; // Driver
      isSignIn = false; // Sign-up mode
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _slideController.dispose();
    _scaleController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ... your existing methods stay the same ...
  void _toggleAuthMode() {
    setState(() {
      isSignIn = !isSignIn;
    });
    _animationController.reset();
    _animationController.forward();
  }

  void _onRoleSelected(int index) {
    if (_selectedDashboard != index) {
      setState(() {
        _selectedDashboard = index;
        _firstNameController.clear();
        _lastNameController.clear();
        _emailController.clear();
        _phoneController.clear();
        _passwordController.clear();
        _confirmPasswordController.clear();
        isSignIn = true;
      });
      _animationController.reset();
      _animationController.forward();
    }
  }

  // ============================================
  // UPDATED: Main authentication handler
  // ============================================
  Future<void> _handleAuth() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      final selectedRole = _getSelectedRole();
      final email = _emailController.text.trim();

      if (isSignIn) {
        // SIGN IN FLOW
        try {
          final user = await _authService.signIn(
            email,
            _passwordController.text,
          );
          setState(() { _isLoading = false; });

          if (user != null) {
            final hasAccess = await _validateAndPrepareRoleAccess(user);
            if (!hasAccess) {
              _showErrorDialog(
                'This account is not registered for ${_getSelectedRoleLabel()}. Please sign in with your registered role.',
              );
              return;
            }
            await _navigateToDashboard(user);
          } else {
            _showErrorDialog('User data not found');
          }
        } catch (e) {
          setState(() { _isLoading = false; });
          final msg = e.toString().replaceFirst('Exception: ', '');
          if (msg.toLowerCase().contains('verify your email')) {
            _showVerificationDialog();
          } else {
            _showErrorDialog(msg);
          }
        }
      } else {
        // SIGN UP FLOW
        try {
          await _authService.signUp(
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            email: email,
            phone: '$_selectedDialCode ${_phoneController.text.trim()}',
            password: _passwordController.text,
            roles: [_getSelectedRole()],
          );

          setState(() { _isLoading = false; });

          _showPostSignupVerifyEmailDialog(selectedRole);
        } catch (e) {
          setState(() { _isLoading = false; });
          _showErrorDialog(e.toString().replaceFirst('Exception: ', ''));
        }
      }
    }
  }

  // NEW: Success dialog specifically for vehicle assignment
  void _showVehicleAssignedDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle, color: Colors.green.shade600, size: 48),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Please verify your email to continue.',
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 45),
            ),
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                isSignIn = true;
                _firstNameController.clear();
                _lastNameController.clear();
                _phoneController.clear();
                _passwordController.clear();
                _confirmPasswordController.clear();
              });
            },
            child: const Text('Continue to Sign In'),
          ),
        ],
      ),
    );
  }

  // Google Sign-In Handler
  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final selectedRole = _getSelectedRole();
      
      // Call Google Sign-In with the selected role
      final user = await _authService.signInWithGoogle(roles: [selectedRole]);
      
      setState(() {
        _isLoading = false;
      });

      if (user != null) {
        final hasAccess = await _validateAndPrepareRoleAccess(user);
        if (!hasAccess) {
          _showErrorDialog(
            'This account is not registered for ${_getSelectedRoleLabel()}. Please sign in with your registered role.',
          );
          return;
        }
        await _navigateToDashboard(user);
      } else {
        _showErrorDialog('Google Sign-In was cancelled');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorDialog(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  // ... all your existing helper methods stay the same ...
  void _showVerificationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Email Not Verified'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Please verify your email before signing in. Check your inbox for the verification link.'),
            const SizedBox(height: 16),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
              ),
              onPressed: () async {
                Navigator.pop(context);
                setState(() {
                  _isLoading = true;
                });
                try {
                  await _authService.resendVerificationEmail();
                  if (mounted) {
                    _showErrorDialog('Verification email sent. Check your inbox and spam folder.');
                  }
                } catch (e) {
                  if (mounted) {
                    _showErrorDialog(e.toString().replaceFirst('Exception: ', ''));
                  }
                } finally {
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                    });
                  }
                }
              },
              child: const Text('Resend Verification Email'),
            ),
          ],
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showForgotPasswordDialog() {
    final emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Enter your Email Address and We\'ll send you a Password Reset Link.'),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              cursorColor: AppColors.primary,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),

          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty) {
                _showErrorDialog('Please Enter Your Email');
                return;
              }

              Navigator.pop(context);
              setState(() {
                _isLoading = true;
              });

              try {
                await _authService.sendPasswordResetEmail(email);
                setState(() { _isLoading = false; });
                _showErrorDialog('Password Reset Email Sent! Check Your Inbox.');
              } catch (e) {
                setState(() { _isLoading = false; });
                _showErrorDialog(e.toString().replaceFirst('Exception: ', ''));
              }
            },
            child: const Text('Send Reset Link'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Message'),
        content: Text(message),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Success'),
        content: Text(message),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
            ),
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                isSignIn = true;
                _firstNameController.clear();
                _lastNameController.clear();
                _phoneController.clear();
                _passwordController.clear();
                _confirmPasswordController.clear();
              });
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// After sign-up the Firebase session is ended; user must verify email, then use Sign In.
  void _showPostSignupVerifyEmailDialog(String selectedRole) {
    String tip = '';
    if (selectedRole == 'driver') {
      tip = ' After you sign in, complete driver verification for vehicle access.';
    } else if (selectedRole == 'owner') {
      tip = ' After you sign in, you can add vehicles from your dashboard.';
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Verify your email'),
        content: Text(
          'We sent a link to your inbox—open it to verify, then sign in here. '
          'Check spam if you do not see it.$tip',
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
            ),
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                isSignIn = true;
                _firstNameController.clear();
                _lastNameController.clear();
                _phoneController.clear();
                _passwordController.clear();
                _confirmPasswordController.clear();
              });
            },
            child: const Text('Continue to Sign In'),
          ),
        ],
      ),
    );
  }

  Future<void> _navigateToDashboard(User user) async {
    final fb = FirebaseAuth.instance.currentUser;
    if (fb == null) {
      _showErrorDialog('Session expired. Please sign in again.');
      return;
    }
    await fb.reload();
    await fb.getIdToken(true);
    await fb.reload();
    final fresh = FirebaseAuth.instance.currentUser;
    if (fresh == null || !fresh.emailVerified) {
      if (mounted) {
        _showVerificationDialog();
      }
      return;
    }

    Widget dashboardScreen;

    switch (_selectedDashboard) {
      case 0:
        // Gate until docs approved; first sign-in after approval requires Continue once.
        dashboardScreen = StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('users').doc(user.id).snapshots(),
          builder: (context, snap) {
            final data = snap.data?.data();
            final approved = (data?['driverDocsApproved'] as bool?) ?? false;
            final gateCompleted = (data?['driverDocsGateCompleted'] as bool?) ?? false;
            if (!approved || !gateCompleted) {
              return DriverDocumentsGateScreen(user: user);
            }
            return DriverDashboard(user: user);
          },
        );
        break;
      case 1:
        dashboardScreen = PassengerDashboard(user: user);
        break;
      case 2:
        dashboardScreen = OwnerDashboard(user: user);
        break;
      default:
        dashboardScreen = DriverDashboard(user: user);
    }

    Navigator.pushReplacement(
      context,
      FadeScalePageRoute(page: dashboardScreen),
    );
  }
  static const BorderRadius _authRadius = BorderRadius.all(Radius.circular(12));

  InputDecoration _authFieldDecoration({
    required String hintText,
    Widget? suffixIcon,
    int? errorMaxLines,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        fontSize: 14,
        color: AppColors.textSecondary.withValues(alpha: 0.85),
      ),
      filled: true,
      fillColor: Colors.white,
      suffixIcon: suffixIcon,
      errorMaxLines: errorMaxLines,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: _authRadius,
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: _authRadius,
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: _authRadius,
        borderSide: BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: _authRadius,
        borderSide: BorderSide(color: AppColors.danger),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: _authRadius,
        borderSide: BorderSide(color: AppColors.danger, width: 2),
      ),
    );
  }

  Widget _authFieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    );
  }

  BoxDecoration _authPanelDecoration() {
    return BoxDecoration(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
    );
  }

  BoxDecoration _authCardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
      boxShadow: [
        BoxShadow(
          color: AppColors.shadowLight,
          blurRadius: 14,
          offset: const Offset(0, 5),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 768;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Column(
                      children: [
                        SizedBox(
                          height: MediaQuery.paddingOf(context).top +
                              (isMobile ? 20 : 32),
                        ),
                        const AlertMateBranding(
                          size: AlertMateBrandingSize.auth,
                        ),
                        SizedBox(height: isMobile ? 14 : 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildNavIcon(Icons.directions_car, 0, 'Driver'),
                            const SizedBox(width: 16),
                            _buildNavIcon(Icons.people, 1, 'Passenger'),
                            const SizedBox(width: 16),
                            _buildNavIcon(
                                Icons.admin_panel_settings, 2, 'Vehicle Owner'),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: _authPanelDecoration(),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.badge_outlined, color: AppColors.primary, size: 22),
                              const SizedBox(width: 10),
                              Text(
                                'Selected Role: ${_getSelectedRoleLabel()}',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        FadeTransition(
                          opacity: _fadeAnimation,
                          child: Center(
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 500),
                              margin:
                              const EdgeInsets.symmetric(horizontal: 20),
                              padding: EdgeInsets.all(isMobile ? 22 : 32),
                              decoration: _authCardDecoration(),
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
                                        child: Icon(
                                          isSignIn ? Icons.login_rounded : Icons.person_add_outlined,
                                          color: AppColors.primary,
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              isSignIn ? 'Welcome Back' : 'Create Account',
                                              style: TextStyle(
                                                fontSize: isMobile ? 20 : 24,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              isSignIn
                                                  ? 'Sign In To Access Your ${_getSelectedRoleLabel()} Dashboard'
                                                  : 'Register As ${_getSelectedRoleLabel()} to Get Started',
                                              style: const TextStyle(
                                                fontSize: 14,
                                                color: AppColors.textSecondary,
                                                height: 1.35,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: _authPanelDecoration(),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: _buildToggleButton(
                                              'Sign-In', isSignIn, () {
                                            if (!isSignIn) _toggleAuthMode();
                                          }),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: _buildToggleButton(
                                              'Sign-Up', !isSignIn, () {
                                            if (isSignIn) _toggleAuthMode();
                                          }),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 30),
                                  if (!isSignIn) ...[
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _buildTextField(
                                            'First Name',
                                            '(e.g. Wahb)',
                                            _firstNameController,
                                            validator: FormValidators.validateFirstName,
                                            inputFormatters: [
                                              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: _buildTextField(
                                            'Last Name',
                                            '(e.g. Muqeet)',
                                            _lastNameController,
                                            validator: FormValidators.validateLastName,
                                            inputFormatters: [
                                              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                  ],
                                  _buildTextField(
                                    'Email',
                                    'abc@example.com',
                                    _emailController,
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Email is Required';
                                      }
                                      if (!RegExp(
                                          r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                                          .hasMatch(value)) {
                                        return 'Enter a Valid Email!';
                                      }
                                      return null;
                                    },
                                  ),
                                  if (!isSignIn) ...[
                                    const SizedBox(height: 20),
                                    _buildPhoneField(),
                                  ],
                                  const SizedBox(height: 20),
                                  _buildPasswordField(),
                                  if (!isSignIn) ...[
                                    const SizedBox(height: 20),
                                    _buildConfirmPasswordField(),
                                  ],
                                  if (isSignIn) ...[
                                    const SizedBox(height: 12),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: _showForgotPasswordDialog,
                                        child: const Text(
                                          'Forgot Password?',
                                          style: TextStyle(
                                            color: AppColors.primary,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 30),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 50,
                                    child: ElevatedButton(
                                      onPressed: _isLoading ? null : _handleAuth,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: _isLoading
                                          ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                          : Text(
                                        isSignIn
                                            ? 'Sign-In as ${_getSelectedRoleLabel()}'
                                            : 'Sign-Up as ${_getSelectedRoleLabel()}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (isSignIn) ...[
                                    const SizedBox(height: 20),
                                    Row(
                                      children: [
                                        Expanded(child: Divider(color: AppColors.border)),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16),
                                          child: Text(
                                            'OR',
                                            style: TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        Expanded(child: Divider(color: AppColors.border)),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 50,
                                      child: OutlinedButton.icon(
                                        onPressed: _isLoading ? null : _handleGoogleSignIn,
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppColors.textPrimary,
                                          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
                                          backgroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                        icon: Image.asset(
                                          'assets/images/google_logo.png',
                                          height: 24,
                                          width: 24,
                                          errorBuilder: (context, error, stackTrace) {
                                            return const Icon(Icons.g_mobiledata, size: 24);
                                          },
                                        ),
                                        label: const Text(
                                          'Continue with Google',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (isSignIn) ...[
                                    const SizedBox(height: 16),
                                    _buildSignUpLink(),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavIcon(IconData icon, int index, String label) {
    bool isActive = _selectedDashboard == index;

    return GestureDetector(
      onTap: () => _onRoleSelected(index),
      child: AnimatedScale(
        scale: isActive ? 1.1 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: isActive ? AppColors.primaryLight : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isActive
                      ? AppColors.primary
                      : AppColors.border.withValues(alpha: 0.8),
                  width: isActive ? 2 : 1.5,
                ),
                boxShadow: isActive
                    ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
                    : [
                  BoxShadow(
                    color: AppColors.shadowLight,
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: AnimatedRotation(
                turns: isActive ? 0.1 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  icon,
                  color: isActive
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: 6),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleButton(String text, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: isActive ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isActive
                ? Border.all(color: AppColors.primary.withValues(alpha: 0.35))
                : null,
            boxShadow: isActive
                ? [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.15),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ]
                : null,
          ),
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 15,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
              child: Text(text),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
      String label,
      String hint,
      TextEditingController controller, {
        String? Function(String?)? validator,
        List<TextInputFormatter>? inputFormatters,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _authFieldLabel(label),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          validator: validator,
          inputFormatters: inputFormatters,
          cursorColor: AppColors.primary,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: _authFieldDecoration(hintText: hint),
        ),
      ],
    );
  }

  Widget _buildPhoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _authFieldLabel('Phone Number'),
        const SizedBox(height: 8),
        Row(
          children: [
            InkWell(
              onTap: () {
                showCountryPicker(
                  context: context,
                  showPhoneCode: true,
                  onSelect: (Country country) {
                    setState(() {
                      _selectedDialCode = '+${country.phoneCode}';
                      _selectedCountryIso = country.countryCode;
                    });
                  },
                );
              },
              child: Container(
                width: 140,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: _authRadius,
                  border: Border.all(color: Colors.grey.shade300),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$_selectedDialCode ($_selectedCountryIso)',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_down,
                        size: 22, color: AppColors.primary),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _phoneController,
                cursorColor: AppColors.primary,
                validator: (value) {
                  if (!isSignIn && (value == null || value.trim().isEmpty)) {
                    return 'Please enter a valid phone number';
                  }
                  if (!isSignIn && value != null && value.trim().isNotEmpty) {
                    return _validatePhoneByCountry(value.trim());
                  }
                  return null;
                },
                maxLines: 1,
                style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                decoration: _authFieldDecoration(
                  hintText: _phoneHintForCountry(),
                  errorMaxLines: 3,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildConfirmPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _authFieldLabel('Confirm Password'),
        const SizedBox(height: 8),
        TextFormField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirmPassword,
          cursorColor: AppColors.primary,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please Confirm Your Password';
            }
            if (value != _passwordController.text) {
              return 'Passwords Do Not Match';
            }
            return null;
          },
          decoration: _authFieldDecoration(
            hintText: 'Re-Enter Your Password',
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                color: AppColors.primary,
              ),
              onPressed: () {
                setState(() {
                  _obscureConfirmPassword = !_obscureConfirmPassword;
                });
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _authFieldLabel('Password'),
        const SizedBox(height: 8),
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          cursorColor: AppColors.primary,
          onChanged: (value) {
            if (!isSignIn) {
              setState(() {}); // Trigger rebuild to update strength indicator
            }
          },
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Password is Required!';
            }
            if (!isSignIn) {
              // Strong password validation for signup
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
            }
            return null;
          },
          decoration: _authFieldDecoration(
            hintText: isSignIn
                ? 'Enter a Password'
                : 'Mix of Letters, Numbers & Special Characters (minimum 8)',
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: AppColors.primary,
              ),
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
          ),
        ),
        if (!isSignIn) ...[
          const SizedBox(height: 8),
          _buildPasswordStrengthIndicator(),
        ],
      ],
    );
  }

  // Password strength indicator
  Widget _buildPasswordStrengthIndicator() {
    final password = _passwordController.text;
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

    if (password.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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

  String _calculatePasswordStrength(String password) {
    if (password.isEmpty) return 'none';
    if (password.length < 8) return 'weak';

    int strength = 0;

    // Check for uppercase
    if (RegExp(r'[A-Z]').hasMatch(password)) strength++;
    // Check for lowercase
    if (RegExp(r'[a-z]').hasMatch(password)) strength++;
    // Check for numbers
    if (RegExp(r'[0-9]').hasMatch(password)) strength++;
    // Check for special characters
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) strength++;
    // Check length
    if (password.length >= 12) strength++;

    if (strength >= 4) return 'strong';
    if (strength >= 2) return 'medium';
    return 'weak';
  }

  String _getPasswordRequirements(String password) {
    List<String> missing = [];

    if (password.length < 8) {
      missing.add('8+ characters');
    }
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      missing.add('uppercase letter');
    }
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      missing.add('lowercase letter');
    }
    if (!RegExp(r'[0-9]').hasMatch(password)) {
      missing.add('number');
    }
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) {
      missing.add('special character');
    }

    if (missing.isEmpty) return '';
    return 'Missing: ${missing.join(', ')}';
  }

  Widget _buildSignUpLink() {
    return Center(
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
          children: [
            const TextSpan(text: "Don't Have An Account? "),
            WidgetSpan(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    isSignIn = false;
                  });
                  _animationController.reset();
                  _animationController.forward();
                },
                child: const Text(
                  'Sign-Up',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}