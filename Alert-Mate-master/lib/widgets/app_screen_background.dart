import 'dart:ui';

import 'package:flutter/material.dart';

/// Subtle full-screen background image layer for dashboard pages.
class AppScreenBackground extends StatelessWidget {
  const AppScreenBackground({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    final imageOpacity = isMobile ? 0.24 : 0.16;
    final overlayOpacity = isMobile ? 0.22 : 0.38;
    final blurSigma = isMobile ? 1.0 : 1.5;

    return Stack(
      children: [
        Positioned.fill(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
            child: Opacity(
              opacity: imageOpacity,
              child: Image.asset(
                'assets/images/app_background.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  // Fallback if the image asset is missing.
                  return Container(color: const Color(0xFF101827));
                },
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Container(color: Colors.black.withValues(alpha: overlayOpacity)),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}
