import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'constants/app_theme.dart';
import 'screens/admin_auth_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    final errorString = e.toString().toLowerCase();
    if (errorString.contains('duplicate-app') ||
        errorString.contains('already exists') ||
        errorString.contains('[default]')) {
      print('Firebase already initialized, continuing...');
    } else {
      print('Firebase initialization error: ');
      rethrow;
    }
  }
  runApp(const AdminWebApp());
}

class AdminWebApp extends StatelessWidget {
  const AdminWebApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Alert Mate Admin',
      debugShowCheckedModeBanner: false,
      theme: buildAlertMateTheme(),
      home: const AdminAuthScreen(),
    );
  }
}
