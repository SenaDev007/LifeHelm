import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Graphiques LifeHelm — peints à la main (CustomPainter), sans dépendance
/// externe : donut de répartition, barres groupées mensuelles, courbe de
/// tendance et barres horizontales classées.

class ChartSlice {
  const ChartSlice(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;
}

/// Donut de répartition (catégories) avec pourcentage au centre.
class LhDonutChart extends StatelessWidget {
  const LhDonutChart({
    super.key,
    required this.slices,
    this.size = 200,
    this.centerLabel,
    this.centerValue,
    this.stroke = 26,
  });

  final List<ChartSlice> slices;
  final double size;
  final String? centerLabel;
  final String? centerValue;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = slices.fold<double>(0, (s, x) => s + x.value);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(
          size: Size.square(size),
          painter: _DonutPainter(
            slices: total > 0 ? slices : const [],
            track: theme.colorScheme.outline.withValues(alpha: 0.35),
            stroke: stroke,
          ),
        ),
        if (total > 0 && centerValue != null)
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text(centerValue!,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            if (centerLabel != null)
              Text(centerLabel!,
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
          ]),
      ]),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.slices, required this.track, this.stroke = 26});
  final List<ChartSlice> slices;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final total = slices.fold<double>(0, (s, x) => s + x.value);

    // Piste.
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = track);

    if (total <= 0) return;
    var start = -math.pi / 2;
    for (final s in slices) {
      final sweep = 2 * math.pi * (s.value / total);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..color = s.color;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.slices != slices || old.track != track;
}

/// Point mensuel : recettes, dépenses (et budget éventuel).
class MonthlyPoint {
  const MonthlyPoint(this.label,
      {this.income = 0, this.expense = 0, this.budget});
  final String label;
  final double income;
  final double expense;
  final double? budget;
}

/// Barres groupées mensuelles : recettes (émeraude) vs dépenses (rouge),
/// avec ligne optionnelle du budget prévisionnel (or).
class LhMonthlyBars extends StatelessWidget {
  const LhMonthlyBars({super.key, required this.points, this.height = 220});

  final List<MonthlyPoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        size: Size.infinite,
        painter: _MonthlyBarsPainter(
          points: points,
          income: LHColors.financePositif,
          expense: LHColors.financeNegatif,
          budget: theme.brightness == Brightness.dark
              ? LHColors.or
              : LHColors.orDeep,
          grid: theme.colorScheme.outline.withValues(alpha: 0.3),
          labelStyle: TextStyle(
            fontSize: 10,
            color: theme.colorScheme.onSurfaceVariant,
            fontFamily: LHFonts.texte,
          ),
          valueStyle: TextStyle(
            fontSize: 9,
            color: theme.colorScheme.onSurfaceVariant,
            fontFamily: LHFonts.texte,
          ),
        ),
      ),
    );
  }
}

class _MonthlyBarsPainter extends CustomPainter {
  _MonthlyBarsPainter({
    required this.points,
    required this.income,
    required this.expense,
    required this.budget,
    required this.grid,
    required this.labelStyle,
    required this.valueStyle,
  });

  final List<MonthlyPoint> points;
  final Color income;
  final Color expense;
  final Color budget;
  final Color grid;
  final TextStyle labelStyle;
  final TextStyle valueStyle;

  static const _leftPad = 6.0;
  static const _bottomPad = 18.0;
  static const _topPad = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final plotW = size.width - _leftPad * 2;
    final plotH = size.height - _bottomPad - _topPad;
    final maxValue = points.fold<double>(
        0,
        (m, p) => math.max(
            m, math.max(p.income, math.max(p.expense, p.budget ?? 0))));
    if (maxValue <= 0) return;

    // Lignes de grille horizontales (4 niveaux).
    for (var i = 1; i <= 4; i++) {
      final y = _topPad + plotH * (1 - i / 4);
      canvas.drawLine(Offset(_leftPad, y), Offset(size.width - _leftPad, y),
          Paint()
            ..color = grid
            ..strokeWidth = 0.6);
    }

    final slot = plotW / points.length;
    final barW = math.min(14.0, slot / 3.2);

    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final cx = _leftPad + slot * i + slot / 2;

      // Barres recettes / dépenses.
      if (p.income > 0) {
        final h = plotH * (p.income / maxValue);
        final rect = Rect.fromLTWH(cx - barW - 2, _topPad + plotH - h, barW, h);
        canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(3)),
            Paint()..color = income);
      }
      if (p.expense > 0) {
        final h = plotH * (p.expense / maxValue);
        final rect = Rect.fromLTWH(cx + 2, _topPad + plotH - h, barW, h);
        canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(3)),
            Paint()..color = expense);
      }

      // Ligne du budget prévisionnel.
      if (p.budget != null && p.budget! > 0) {
        final y = _topPad + plotH * (1 - p.budget! / maxValue);
        final paint = Paint()
          ..color = budget
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(cx - slot / 2 + 4, y),
            Offset(cx + slot / 2 - 4, y), paint);
      }

      // Libellé du mois.
      final tp = TextPainter(
          text: TextSpan(text: p.label, style: labelStyle),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas,
          Offset(cx - tp.width / 2, size.height - _bottomPad + 4));
    }
  }

  @override
  bool shouldRepaint(_MonthlyBarsPainter old) => old.points != points;
}

/// Barre horizontale classée (top catégories).
class LhRankBar extends StatelessWidget {
  const LhRankBar({
    super.key,
    required this.label,
    required this.value,
    required this.ratio,
    required this.color,
    this.trailing,
  });

  final String label;
  final String value;
  final double ratio; // 0..1 par rapport au max
  final Color color;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium),
            ),
            const SizedBox(width: 8),
            Text(value,
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            if (trailing != null) ...[
              const SizedBox(width: 6),
              Text(trailing!,
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ],
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(LHRadius.full),
            child: SizedBox(
              height: 6,
              child: Stack(children: [
                Container(
                    color: theme.colorScheme.outline.withValues(alpha: 0.35)),
                FractionallySizedBox(
                  widthFactor: ratio.clamp(0.0, 1.0),
                  child: Container(color: color),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Légende colorée compacte.
class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.entries});
  final List<ChartSlice> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        for (final e in entries)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: e.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(e.label,
                style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
          ]),
      ],
    );
  }
}
