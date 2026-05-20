import 'package:firebase_auth/firebase_auth.dart' as firebase_auth hide User;
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../dashboards/admin_dashboard.dart';
import '../models/user.dart';
import '../services/firebase_auth_service.dart';
import '../utils/form_validators.dart';
import '../utils/page_transitions.dart';

class AdminAuthScreen extends StatefulWidget {
  const AdminAuthScreen({Key? key}) : super(key: key);

  @override
  State<AdminAuthScreen> createState() => _AdminAuthScreenState();
}

class _AdminAuthScreenState extends State<AdminAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final FirebaseAuthService _authService = FirebaseAuthService();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
  }

  Future<void> _checkExistingSession() async {
    final fb = firebase_auth.FirebaseAuth.instance.currentUser;
    if (fb == null) return;
    try {
      final user = await _authService.fetchUserProfile(fb.uid);
      if (user != null && _isAdmin(user) && mounted) {
        await _authService.updateActiveRole(user.id, 'admin');
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          FadeScalePageRoute(page: AdminDashboard(user: user)),
        );
      }
    } catch (_) {}
  }

  bool _isAdmin(User user) {
    final roles = user.roles ?? [];
    return roles.contains('admin') || user.role == 'admin';
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showMessage('Please enter your email and password.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final user = await _authService.signIn(
        email,
        password,
        skipEmailVerification: true,
      );
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (user == null) {
        _showMessage('Invalid email or password. Please try again.');
        return;
      }
      if (!_isAdmin(user)) {
        await _authService.signOut();
        _showMessage('Not authorized for admin portal. Use the mobile app for other roles.');
        return;
      }
      await _authService.updateActiveRole(user.id, 'admin');
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        FadeScalePageRoute(page: AdminDashboard(user: user)),
      );
    } on firebase_auth.FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showMessage(_authErrorMessage(e.code));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      final msg = e.toString().replaceFirst('Exception: ', '');
      if (msg.toLowerCase().contains('invalid') ||
          msg.toLowerCase().contains('password') ||
          msg.toLowerCase().contains('user')) {
        _showMessage('Invalid email or password. Please try again.');
      } else {
        _showMessage(msg);
      }
    }
  }

  String _authErrorMessage(String code) {
    switch (code) {
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'Invalid email or password. Please try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';
      default:
        return 'Sign in failed. Please check your credentials.';
    }
  }

  void _showMessage(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Admin Portal'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 600;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? 32 : 20,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    Center(
                      child: Image.asset(
                        'assets/images/Alert Mate New.png',
                        width: isWide ? 140 : 120,
                        height: isWide ? 105 : 90,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'ALERT MATE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Administrator Portal',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.black54),
                    ),
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              border: OutlineInputBorder(),
                            ),
                            validator: FormValidators.validateEmail,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                            ),
                            validator: (v) =>
                                FormValidators.validatePassword(v, minLength: 6),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _handleSignIn,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Sign In',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Mobile app: Driver, Passenger, and Owner only.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
