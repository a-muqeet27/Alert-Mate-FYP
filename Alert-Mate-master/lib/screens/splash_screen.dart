import 'package:flutter/material.dart';
import 'dart:async';
import '../auth_screen.dart';
import '../constants/app_colors.dart';
import '../utils/page_transitions.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Animation Controllers
  late AnimationController _logoController;
  late AnimationController _textController;
  late AnimationController _progressController;
  late AnimationController _backgroundController;
  late AnimationController _dotsController;
  
  // Animations
  late Animation<double> _logoScaleAnimation;
  late Animation<double> _logoFadeAnimation;
  late Animation<Offset> _textSlideAnimation;
  late Animation<double> _textFadeAnimation;
  late Animation<double> _progressAnimation;
  late Animation<double> _backgroundAnimation;
  late Animation<double> _dotsAnimation;

  @override
  void initState() {
    super.initState();
    
    // Logo animations
    _logoController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _logoScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );
    
    _logoFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
      ),
    );
    
    // Text animations
    _textController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    
    _textSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _textController,
        curve: Curves.easeOutCubic,
      ),
    );
    
    _textFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _textController,
        curve: Curves.easeIn,
      ),
    );
    
    // Progress animation
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    
    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _progressController,
        curve: Curves.easeInOut,
      ),
    );
    
    // Background animation
    _backgroundController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
    
    _backgroundAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _backgroundController,
        curve: Curves.linear,
      ),
    );
    
    // Dots animation
    _dotsController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    
    _dotsAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _dotsController,
        curve: Curves.easeInOut,
      ),
    );
    
    // Start animations
    _startAnimations();
  }

  void _startAnimations() async {
    // Start logo animation
    _logoController.forward();
    
    // Start text animation after delay
    await Future.delayed(const Duration(milliseconds: 400));
    _textController.forward();
    
    // Start progress animation
    await Future.delayed(const Duration(milliseconds: 600));
    _progressController.forward();
    
    // Navigate to auth screen after animations complete
    await Future.delayed(const Duration(milliseconds: 2500));
    if (mounted) {
      Navigator.pushReplacement(
        context,
        FadeScalePageRoute(page: const AuthScreen()),
      );
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _progressController.dispose();
    _backgroundController.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: _backgroundController,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white,
                  Colors.grey[50]!,
                  Colors.white,
                ],
                stops: [
                  0.0,
                  0.5 + (_backgroundAnimation.value * 0.3),
                  1.0,
                ],
              ),
            ),
            child: Stack(
              children: [
                // Animated background shapes
                _buildAnimatedShapes(),
                
                // Main content
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo with animations
                      FadeTransition(
                        opacity: _logoFadeAnimation,
                        child: ScaleTransition(
                          scale: _logoScaleAnimation,
                            child: AnimatedBuilder(
                              animation: _logoController,
                              builder: (context, child) {
                                final pulseValue = (_logoController.value > 0.6)
                                    ? 1.0 + (0.05 * ((_logoController.value - 0.6) / 0.4))
                                    : 1.0;
                                return Transform.scale(
                                  scale: pulseValue,
                                  child: Container(
                                    width: 120,
                                    height: 120,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primary.withValues(alpha: 0.2),
                                          blurRadius: 20 * pulseValue,
                                          spreadRadius: 5 * pulseValue,
                                        ),
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.08),
                                          blurRadius: 30,
                                          spreadRadius: 5,
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Image.asset(
                                        'assets/images/Alert Mate.png',
                                        width: 100,
                                        height: 80,
                                        fit: BoxFit.contain,
                                        errorBuilder: (context, error, stackTrace) {
                                          return const Icon(
                                            Icons.security,
                                            size: 60,
                                            color: AppColors.primary,
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ),
                      
                      const SizedBox(height: 40),
                      
                      // App name with slide and fade
                      SlideTransition(
                        position: _textSlideAnimation,
                        child: FadeTransition(
                          opacity: _textFadeAnimation,
                          child: Column(
                            children: [
                              Text(
                                'ALERT MATE',
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 4,
                                  color: AppColors.primary,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 10,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Drowsiness Detection System',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[700],
                                  letterSpacing: 1.5,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 60),
                      
                      // Progress indicator with modern design
                      FadeTransition(
                        opacity: _textFadeAnimation,
                        child: SizedBox(
                          width: 200,
                          child: Column(
                            children: [
                              AnimatedBuilder(
                                animation: _progressAnimation,
                                builder: (context, child) {
                                  return Container(
                                    height: 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.grey[200],
                    ),
                                    child: Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: LinearProgressIndicator(
                                            value: _progressAnimation.value,
                                            minHeight: 6,
                                            backgroundColor: Colors.transparent,
                                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                                          ),
                                        ),
                                        // Shimmer effect
                                        if (_progressAnimation.value > 0)
                                          Positioned(
                                            left: (_progressAnimation.value * 200) - 30,
                                            child: Container(
                                              width: 30,
                                              height: 6,
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    Colors.transparent,
                                                    Colors.white.withValues(alpha: 0.5),
                                                    Colors.transparent,
                                                  ],
                                                ),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 20),
                              AnimatedBuilder(
                                animation: _dotsAnimation,
                                builder: (context, child) {
                                  final dotCount = ((_dotsAnimation.value * 3).toInt() % 4);
                                  final dots = List.filled(dotCount, '.').join('');
                                  return Text(
                                    'Loading$dots',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w300,
                                      letterSpacing: 2,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAnimatedShapes() {
    return AnimatedBuilder(
      animation: _backgroundController,
      builder: (context, child) {
        return Stack(
          children: [
            // Floating circles
            Positioned(
              top: 100 + (50 * _backgroundAnimation.value),
              left: 50,
              child: Opacity(
                opacity: 0.05,
                child: Transform.scale(
                  scale: 1.0 + (0.3 * _backgroundAnimation.value),
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 150 + (30 * (1 - _backgroundAnimation.value)),
              right: 80,
              child: Opacity(
                opacity: 0.05,
                child: Transform.scale(
                  scale: 1.0 + (0.2 * (1 - _backgroundAnimation.value)),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).size.height * 0.4,
              right: 30,
              child: Opacity(
                opacity: 0.04,
                child: Transform.rotate(
                  angle: _backgroundAnimation.value * 3.14,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 200,
              left: 30,
              child: Opacity(
                opacity: 0.04,
                child: Transform.rotate(
                  angle: -_backgroundAnimation.value * 3.14,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

