import 'package:flutter/material.dart';

/// Shared layout breakpoints and helpers for role dashboards.
class DashboardLayout {
  DashboardLayout._();

  static const double mobileBreakpoint = 768;
  static const double tabletBreakpoint = 1024;
  static const double narrowContentBreakpoint = 600;

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < mobileBreakpoint;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= mobileBreakpoint && w < tabletBreakpoint;
  }

  static bool isNarrow(BuildContext context) =>
      MediaQuery.sizeOf(context).width < narrowContentBreakpoint;

  static EdgeInsets pagePadding(BuildContext context) {
    if (isMobile(context)) return const EdgeInsets.fromLTRB(16, 12, 16, 16);
    if (isTablet(context)) return const EdgeInsets.fromLTRB(24, 16, 24, 20);
    return const EdgeInsets.fromLTRB(24, 20, 24, 24);
  }

  static EdgeInsets cardPadding(BuildContext context) =>
      EdgeInsets.all(isMobile(context) ? 14 : 18);

  /// Scrollable page body aligned to top (avoids vertical centering on desktop).
  static Widget scrollPage({
    required BuildContext context,
    required Widget child,
    String? desktopTitle,
    String? desktopSubtitle,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = isMobile(context);
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: constraints.maxWidth,
              minHeight: constraints.maxHeight,
            ),
            child: Padding(
              padding: pagePadding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  if (!mobile && desktopTitle != null) ...[
                    Text(
                      desktopTitle,
                      style: TextStyle(
                        fontSize: isTablet(context) ? 26 : 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    if (desktopSubtitle != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        desktopSubtitle,
                        style: const TextStyle(fontSize: 15, color: Colors.black54),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                  child,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Sidebar + main content for tablet/desktop; full-width body on mobile.
  static Widget scaffoldBody({
    required BuildContext context,
    required Widget sidebar,
    required Widget body,
    Widget? desktopHeader,
  }) {
    if (isMobile(context)) return body;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sidebar,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (desktopHeader != null) desktopHeader,
              Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: body,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static double liveMapHeight(BuildContext context, {double desktopHeaderReserve = 160}) {
    final h = MediaQuery.sizeOf(context).height;
    final mobile = isMobile(context);
    return (h - (mobile ? 110 : desktopHeaderReserve))
        .clamp(mobile ? 260.0 : 300.0, mobile ? 420.0 : 720.0);
  }

  /// Header row that stacks on mobile (e.g. title + action button).
  static Widget sectionHeader({
    required BuildContext context,
    required Widget title,
    Widget? action,
    double spacing = 12,
  }) {
    if (action == null) return title;
    if (isMobile(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          SizedBox(height: spacing),
          action,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: title),
        action,
      ],
    );
  }

  /// Horizontal scroll wrapper for wide data tables on tablet/desktop.
  static Widget horizontalTable({
    required BuildContext context,
    required Widget table,
    double minWidth = 720,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width >= minWidth) return table;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minWidth),
            child: table,
          ),
        );
      },
    );
  }
}