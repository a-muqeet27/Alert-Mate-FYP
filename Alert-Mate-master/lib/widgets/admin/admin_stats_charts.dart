import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';

/// Lightweight bar chart for admin statistics (no extra packages).
class AdminBarChart extends StatelessWidget {
  const AdminBarChart({
    super.key,
    required this.labels,
    required this.values,
    this.colors,
    this.height = 160,
    this.title,
    this.showBarValues = false,
  });

  final List<String> labels;
  final List<double> values;
  final List<Color>? colors;
  final double height;
  final String? title;
  final bool showBarValues;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty || values.isEmpty || labels.length != values.length) {
      return const SizedBox.shrink();
    }

    final maxVal = values.fold<double>(0, (a, b) => b > a ? b : a);
    final safeMax = maxVal <= 0 ? 1.0 : maxVal;
    final palette = colors ??
        [
          AppColors.primary,
          const Color(0xFF2196F3),
          const Color(0xFF9C27B0),
          AppColors.warning,
          AppColors.success,
        ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final chartHeight = compact ? 120.0 : height;
        final labelReserve = showBarValues ? 40.0 : 28.0;

        final chart = SizedBox(
          height: chartHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(labels.length, (i) {
              final v = values[i];
              final ratio = (v / safeMax).clamp(0.0, 1.0);
              final barHeight = (chartHeight - labelReserve) * ratio;
              final color = palette[i % palette.length];
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 4, right: i == labels.length - 1 ? 0 : 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (showBarValues)
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: compact ? 10 : 11,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                        ),
                      if (showBarValues) const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        height: barHeight < 4 && v > 0 ? 4 : barHeight,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.85),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        labels[i],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: compact ? 9 : 10,
                          color: AppColors.textSecondary,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(
                title!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (compact)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: labels.length * 72.0, child: chart),
              )
            else
              chart,
          ],
        );
      },
    );
  }
}

/// Donut-style distribution chart for admin statistics.
class AdminDonutChart extends StatelessWidget {
  const AdminDonutChart({
    super.key,
    required this.segments,
    this.size = 120,
    this.title,
    this.showLegendCounts = false,
  });

  final List<AdminChartSegment> segments;
  final double size;
  final String? title;
  final bool showLegendCounts;

  static const List<Color> _defaultPalette = [
    Color(0xFF4CAF50),
    Color(0xFF2196F3),
    Color(0xFF9C27B0),
    Color(0xFFFF9800),
    AppColors.primary,
    AppColors.danger,
  ];

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<double>(0, (s, e) => s + e.value);
    if (total <= 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'No data for chart',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
      );
    }

    final legend = segments.asMap().entries.map((entry) {
      final s = entry.value;
      final pct = (s.value / total * 100).round();
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: s.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
              ),
            ),
            Text(
              showLegendCounts ? '${s.value.round()} ($pct%)' : '$pct%',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackVertically = constraints.maxWidth < 480;
        final chartSize = stackVertically ? size * 0.9 : size;

        final donut = SizedBox(
          width: chartSize,
          height: chartSize,
          child: CustomPaint(
            painter: _DonutPainter(segments: segments, total: total),
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(
                title!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (stackVertically) ...[
              Center(child: donut),
              const SizedBox(height: 14),
              ...legend,
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  donut,
                  const SizedBox(width: 16),
                  Expanded(child: Column(children: legend)),
                ],
              ),
          ],
        );
      },
    );
  }

  static List<AdminChartSegment> segmentsFromCounts(Map<String, int> counts) {
    var i = 0;
    return counts.entries
        .map(
          (e) => AdminChartSegment(
            label: e.key,
            value: e.value.toDouble(),
            color: _defaultPalette[i++ % _defaultPalette.length],
          ),
        )
        .toList();
  }
}

class AdminChartSegment {
  const AdminChartSegment({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.segments, required this.total});

  final List<AdminChartSegment> segments;
  final double total;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    const stroke = 20.0;
    var start = -3.1415926535 / 2;

    for (final s in segments) {
      if (s.value <= 0) continue;
      final sweep = (s.value / total) * 2 * 3.1415926535;
      final paint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - stroke / 2),
        start,
        sweep,
        false,
        paint,
      );
      start += sweep;
    }

    final hole = Paint()..color = Colors.white;
    canvas.drawCircle(center, radius - stroke - 4, hole);
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.segments != segments || oldDelegate.total != total;
}
