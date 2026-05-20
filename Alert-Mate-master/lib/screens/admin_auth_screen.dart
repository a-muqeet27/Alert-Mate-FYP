import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' hide User;
import '../constants/app_colors.dart';
import '../dashboards/admin_dashboard.dart';
import '../models/user.dart';
import '../services/firebase_auth_service.dart';
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

  @override void initState() { super.initState(); _checkExistingSession(); }

  Future<void> _checkExistingSession() async {
    final fb = FirebaseAuth.instance.currentUser;
    if (fb == null) return;
    try {
      final user = await _authService.fetchUserProfile(fb.uid);
      if (user != null && _isAdmin(user) && mounted) {
        await _authService.updateActiveRole(user.id, 'admin');
        if (!mounted) return;
        Navigator.pushReplacement(context, FadeScalePageRoute(page: AdminDashboard(user: user)));
      }
    } catch (_) {}
  }

  bool _isAdmin(User user) {
    final roles = user.roles ?? [];
    return roles.contains('admin') || user.role == 'admin';
  }

  @override void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final user = await _authService.signIn(_emailController.text.trim(), _passwordController.text, skipEmailVerification: true);
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (user == null) { _showMessage('User profile not found.'); return; }
      if (!_isAdmin(user)) {
        await _authService.signOut();
        _showMessage('Not authorized for admin portal. Use the mobile app for other roles.');
        return;
      }
      await _authService.updateActiveRole(user.id, 'admin');
      if (!mounted) return;
      Navigator.pushReplacement(context, FadeScalePageRoute(page: AdminDashboard(user: user)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _showMessage(String message) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Admin Portal'),
      content: Text(message),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('ALERT MATE ADMIN', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Administrator sign in', textAlign: TextAlign.center),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleSignIn,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                      child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('Sign In'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Mobile app: Driver, Passenger, Owner only.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
