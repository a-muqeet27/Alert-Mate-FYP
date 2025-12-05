import 'package:flutter/material.dart';

/// A page route that fades and scales the incoming page.
class FadeScalePageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  final Duration duration;

  FadeScalePageRoute({
    required this.page,
    this.duration = const Duration(milliseconds: 400),
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            var curve = Curves.easeInOut;
            var tween = Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: curve));
            var scaleTween = Tween(begin: 0.95, end: 1.0).chain(CurveTween(curve: curve));

            return FadeTransition(
              opacity: animation.drive(tween),
              child: ScaleTransition(
                scale: animation.drive(scaleTween),
                child: child,
              ),
            );
          },
          transitionDuration: duration,
        );
}

/// A page route that slides the incoming page from the right.
class SlidePageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  final Duration duration;
  final Offset beginOffset;

  SlidePageRoute({
    required this.page,
    this.duration = const Duration(milliseconds: 300),
    this.beginOffset = const Offset(1.0, 0.0),
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            var curve = Curves.easeOutCubic;
            var tween = Tween(begin: beginOffset, end: Offset.zero)
                .chain(CurveTween(curve: curve));

            return SlideTransition(
              position: animation.drive(tween),
              child: child,
            );
          },
          transitionDuration: duration,
        );
}
