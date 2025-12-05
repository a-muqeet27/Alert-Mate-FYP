// COMPLETE FIXED AUTH_SCREEN.DART
// Replace your _handleAuth() method with this updated version

import 'package:flutter/material.dart';
import 'models/user.dart';
import 'package:country_picker/country_picker.dart';
import 'services/firebase_auth_service.dart';
import 'services/vehicle_service.dart';
import 'dashboards/driver_dashboard.dart';
import 'dashboards/passenger_dashboard.dart';
import 'dashboards/owner_dashboard.dart';
import 'dashboards/admin_dashboard.dart';
import 'utils/page_transitions.dart';

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

  // ... all your existing helper methods stay the same ...
  String _getSelectedRole() {
    switch (_selectedDashboard) {
      case 0: return 'driver';
      case 1: return 'passenger';
      case 2: return 'owner';
      case 3: return 'admin';
      default: return 'driver';
    }
  }

  String _getSelectedRoleLabel() {
    switch (_selectedDashboard) {
      case 0: return 'Driver';
      case 1: return 'Passenger';
      case 2: return 'Owner';
      case 3: return 'Admin';
      default: return 'Driver';
    }
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
          final user = await _authService.signIn(email, _passwordController.text);
          setState(() { _isLoading = false; });
          
          if (user != null) {
            // NEW: Check if driver and assign vehicle if needed
            if (user.role == 'driver' || (user.roles?.contains('driver') ?? false)) {
              final vehicleService = VehicleService();
              
              // Check if this is owner becoming driver
              if (widget.isOwnerBecomingDriver) {
                // Assign vehicles waiting specifically for this owner
                await vehicleService.assignOwnerPendingVehicles(
                  user.id,
                  user.email,
                );
        } else {
                // Regular driver - assign general pending vehicles
                await vehicleService.assignGeneralPendingVehiclesToNewDriver(
                  user.id,
                  user.email,
                );
              }
            }
            _navigateToDashboard(user);
          } else {
            _showErrorDialog('User data not found');
          }
        } catch (e) {
          setState(() { _isLoading = false; });
          _showErrorDialog(e.toString().replaceFirst('Exception: ', ''));
        }
      } else {
        // SIGN UP FLOW
        try {
          final user = await _authService.signUp(
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          email: email,
          phone: '$_selectedDialCode ${_phoneController.text.trim()}',
          password: _passwordController.text,
            roles: [_getSelectedRole()],
          );
          
          setState(() { _isLoading = false; });
          
          // NEW: Auto-assign vehicles after successful driver registration
          if (selectedRole == 'driver' && user != null) {
            final vehicleService = VehicleService();
            
            // Check if this is owner becoming driver
            if (widget.isOwnerBecomingDriver) {
              print('🎯 Owner completing driver registration');
              
              // Assign vehicles waiting specifically for THIS owner
              List<String> assignedVehicles = await vehicleService.assignOwnerPendingVehicles(
                user.uid,
                email,
              );
              
              if (assignedVehicles.isNotEmpty) {
                // Show success with vehicle count
                _showVehicleAssignedDialog(
                  'Vehicle${assignedVehicles.length > 1 ? 's' : ''} Assigned!',
                  'Your ${assignedVehicles.length} vehicle${assignedVehicles.length > 1 ? 's have' : ' has'} been automatically assigned to you. You can now see ${assignedVehicles.length > 1 ? 'them' : 'it'} in your driver dashboard.',
                );
        } else {
                _showSuccessDialog('Driver account created! Please verify your email.');
              }
            } else {
              print('🚗 Regular driver signup');
              
              // Regular driver - assign any pending vehicle
              bool vehicleAssigned = await vehicleService.assignGeneralPendingVehiclesToNewDriver(
                user.uid,
                email,
              );
              
              if (vehicleAssigned) {
                _showVehicleAssignedDialog(
                  'Vehicle Assigned!',
                  'A vehicle has been automatically assigned to you.',
                );
              } else {
                _showSuccessDialog('Driver account created! Please verify your email.');
              }
            }
          } else {
            _showSuccessDialog('Account created! Please verify your email.');
          }
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
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                isSignIn = true;
                _firstNameController.clear();
                _lastNameController.clear();
                _phoneController.clear();
                _passwordController.clear();
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 45),
            ),
            child: const Text('Continue to Sign In'),
          ),
        ],
      ),
    );
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
              onPressed: () async {
                Navigator.pop(context);
                setState(() {
                  _isLoading = true;
                });
                final result = await _authService.resendVerificationEmail();
                setState(() {
                  _isLoading = false;
                });
                _showErrorDialog('Password reset email sent! Check your inbox.');
              },
              child: const Text('Resend Verification Email'),
            ),
          ],
        ),
        actions: [
          TextButton(
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
                'Enter your email address and we\'ll send you a password reset link.'),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
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
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty) {
                _showErrorDialog('Please enter your email');
                return;
              }

              Navigator.pop(context);
              setState(() {
                _isLoading = true;
              });

              try {
                await _authService.sendPasswordResetEmail(email);
                setState(() { _isLoading = false; });
                _showErrorDialog('Password reset email sent! Check your inbox.');
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
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                isSignIn = true;
                _firstNameController.clear();
                _lastNameController.clear();
                _phoneController.clear();
                _passwordController.clear();
              });
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _navigateToDashboard(User user) {
    Widget dashboardScreen;

    switch (_selectedDashboard) {
      case 0:
        dashboardScreen = DriverDashboard(user: user);
        break;
      case 1:
        dashboardScreen = PassengerDashboard(user: user);
        break;
      case 2:
        dashboardScreen = OwnerDashboard(user: user);
        break;
      case 3:
        dashboardScreen = AdminDashboard(user: user);
        break;
      default:
        dashboardScreen = DriverDashboard(user: user);
    }

    Navigator.pushReplacement(
      context,
      FadeScalePageRoute(page: dashboardScreen),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                        const SizedBox(height: 20),
                        Column(
                          children: [
                            Image.asset(
                              'assets/images/Alert Mate.png',
                              width: 80,
                              height: 60,
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'ALERT MATE',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 4,
                                color: Color(0xFF2C3E50),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Drowsiness Detection',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF7F8C8D),
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildNavIcon(Icons.directions_car, 0, 'Driver'),
                            const SizedBox(width: 16),
                            _buildNavIcon(Icons.people, 1, 'Passenger'),
                            const SizedBox(width: 16),
                            _buildNavIcon(
                                Icons.admin_panel_settings, 2, 'Owner'),
                            const SizedBox(width: 16),
                            _buildNavIcon(Icons.settings, 3, 'Admin'),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F4FD),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Selected Role: ${_getSelectedRoleLabel()}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF3498DB),
                            ),
                            textAlign: TextAlign.center,
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
                              padding: const EdgeInsets.all(40),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 20,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isSignIn ? 'Welcome!' : 'Create Account',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF2C3E50),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    isSignIn
                                        ? 'Sign-in to access your ${_getSelectedRoleLabel()} Dashboard'
                                        : 'Register as ${_getSelectedRoleLabel()} to get started',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF7F8C8D),
                                    ),
                                  ),
                                  const SizedBox(height: 30),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildToggleButton(
                                            'Sign-In', isSignIn, () {
                                          if (!isSignIn) _toggleAuthMode();
                                        }),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: _buildToggleButton(
                                            'Sign-Up', !isSignIn, () {
                                          if (isSignIn) _toggleAuthMode();
                                        }),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 30),
                                  if (!isSignIn) ...[
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _buildTextField(
                                            'First Name',
                                            '(e.g., Wahb)',
                                            _firstNameController,
                                            validator: (value) {
                                              if (value == null ||
                                                  value.isEmpty) {
                                                return 'Required';
                                              }
                                              return null;
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: _buildTextField(
                                            'Last Name',
                                            '(e.g., Muqeet)',
                                            _lastNameController,
                                            validator: (value) {
                                              if (value == null ||
                                                  value.isEmpty) {
                                                return 'Required';
                                              }
                                              return null;
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                  ],
                                  _buildTextField(
                                    'Email',
                                    'Email (e.g., abc@example.com)',
                                    _emailController,
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Email is Required';
                                      }
                                      if (!RegExp(
                                              r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                                          .hasMatch(value)) {
                                        return 'Enter a valid Email!';
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
                                  if (isSignIn && _selectedDashboard != 3) ...[
                                    // Don't show forgot password for admin (index 3)
                                    const SizedBox(height: 12),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: _showForgotPasswordDialog,
                                        child: const Text(
                                          'Forgot Password?',
                                          style: TextStyle(
                                            color: Color(0xFF3498DB),
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
                                        backgroundColor:
                                            const Color(0xFF3498DB),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
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
                color: isActive ? const Color(0xFFE8F4FD) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isActive
                      ? const Color(0xFF3498DB)
                      : const Color(0xFFE0E0E0),
                  width: 2,
                ),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: const Color(0xFF3498DB).withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: AnimatedRotation(
                turns: isActive ? 0.1 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  icon,
                  color: isActive
                      ? const Color(0xFF3498DB)
                      : const Color(0xFF95A5A6),
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
                    ? const Color(0xFF3498DB)
                    : const Color(0xFF7F8C8D),
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
            color: isActive ? const Color(0xFFE8F4FD) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: const Color(0xFF3498DB).withValues(alpha: 0.2),
                      blurRadius: 4,
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
                fontWeight: FontWeight.w500,
                color: isActive
                    ? const Color(0xFF3498DB)
                    : const Color(0xFF7F8C8D),
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
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF2C3E50),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFFBDC3C7)),
            filled: true,
            fillColor: const Color(0xFFF8F9FA),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF3498DB), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.red),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.red, width: 2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Phone Number',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF2C3E50),
          ),
        ),
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
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE0E0E0)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$_selectedDialCode ($_selectedCountryIso)',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_down,
                        size: 18, color: Color(0xFF7F8C8D)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _phoneController,
                validator: (value) {
                  if (!isSignIn && (value == null || value.isEmpty)) {
                    return 'Phone Number is Required';
                  }
                  return null;
                },
                decoration: InputDecoration(
                  hintText: 'Phone (e.g., 321 1234567)',
                  hintStyle: const TextStyle(color: Color(0xFFBDC3C7)),
                  filled: true,
                  fillColor: const Color(0xFFF8F9FA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: Color(0xFF3498DB), width: 2),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.red),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.red, width: 2),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Password',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF2C3E50),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
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
          decoration: InputDecoration(
            hintText: isSignIn 
                ? 'Enter a password' 
                : 'Mix of letters, numbers & special chars (min 8)',
            hintStyle: const TextStyle(color: Color(0xFFBDC3C7), fontSize: 13),
            filled: true,
            fillColor: const Color(0xFFF8F9FA),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: const Color(0xFF7F8C8D),
              ),
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF3498DB), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.red),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.red, width: 2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
            color: Color(0xFF7F8C8D),
          ),
          children: [
            const TextSpan(text: "Don't have an account? "),
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
                    color: Color(0xFF3498DB),
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