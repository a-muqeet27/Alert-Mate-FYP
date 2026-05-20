import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'screens/public_live_tracking_screen.dart';
import 'constants/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase, handling duplicate initialization gracefully
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // If Firebase is already initialized (duplicate-app error), ignore it
    // This can happen during hot reload or if Firebase was auto-initialized
    final errorString = e.toString().toLowerCase();
    if (errorString.contains('duplicate-app') || 
        errorString.contains('already exists') ||
        errorString.contains('[default]')) {
      // Firebase is already initialized, continue
      print('Firebase already initialized, continuing...');
    } else {
      // Re-throw other errors
      print('Firebase initialization error: $e');
      rethrow;
    }
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Alert Mate',
      debugShowCheckedModeBanner: false,
      theme: buildAlertMateTheme(),
      home: const SplashScreen(),
      // Route handling for tracking links
      onGenerateRoute: (settings) {
        // Handle /track/:tokenId route
        if (settings.name != null && settings.name!.startsWith('/track/')) {
          final tokenId = settings.name!.substring(7); // Remove '/track/' prefix
          return MaterialPageRoute(
            builder: (context) => PublicLiveTrackingScreen(tokenId: tokenId),
          );
        }
        
        // Default route
        return MaterialPageRoute(
          builder: (context) => const SplashScreen(),
        );
      },
    );
  }
}
