import 'package:flutter/material.dart';

import 'progress_stats.dart';
import 'progress_store.dart';

/// Shared progress widgets used by the Copy home screen: status colours, the
/// daily-activity heatmap, the session trend chart, and the item map.
/// Charts are hand-drawn with CustomPainter to avoid extra dependencies.

/// Shared status colours used by the progress page and the home panel.
const Color kMasteredColor = Color(0xFF2E7D32); // green 800
const Color kLearningColor = Color(0xFFF9A825); // amber 800

/// A GitHub-style activity calendar: weekdays as rows (Sun→Sat, top→bottom),
/// weeks as columns (oldest→newest, left→right). Each cell is shaded by how
/// much practice happened that day. [days] is a contiguous oldest→newest run.
class ActivityHeatmap extends StatelessWidget {
  final List<DayActivity> days;
  const ActivityHeatmap({super.key, required this.days});

  static const _weekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S']; // Sun..Sat
  static const _monthAbbr = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Weekday row index, Sunday = 0 .. Saturday = 6. (DateTime: Mon=1..Sun=7.)
  static int _row(DateTime d) => d.weekday % 7;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.primary;
    final empty = theme.disabledColor.withValues(alpha: 0.12);
    final maxItems =
        days.fold<int>(0, (m, d) => d.itemsSeen > m ? d.itemsSeen : m);

    Color cellColor(DayActivity d) {
      if (!d.active) return empty;
      final frac = maxItems == 0 ? 1.0 : (d.itemsSeen / maxItems);
      return base.withValues(alpha: 0.35 + 0.65 * frac.clamp(0.0, 1.0));
    }

    if (days.isEmpty) return const SizedBox.shrink();

    // Build week columns. Each day lands on its real weekday row (Sun=0). A new
    // column begins whenever we reach Sunday (after the first day); leading and
    // trailing gaps are left as nulls (blank slots).
    final columns = <List<DayActivity?>>[];
    var col = List<DayActivity?>.filled(7, null);
    var started = false;
    for (final d in days) {
      final r = _row(d.day);
      if (r == 0 && started) {
        columns.add(col);
        col = List<DayActivity?>.filled(7, null);
      }
      col[r] = d;
      started = true;
    }
    if (started) columns.add(col);

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 3.0;
        const labelW = 16.0;
        final nCols = columns.length;
        // Size cells to fit width; cap so they don't get huge with few weeks.
        final avail = constraints.maxWidth - labelW - gap;
        final cell =
            ((avail - gap * (nCols - 1)) / nCols).clamp(8.0, 18.0);

        // Month labels: show a month abbreviation above the first column whose
        // top-most real day starts a new month.
        int? monthForColumn(int c) {
          final firstDay = columns[c].firstWhere((d) => d != null,
              orElse: () => null);
          if (firstDay == null) return null;
          final m = firstDay.day.month;
          if (c == 0) return m;
          final prev = columns[c - 1].firstWhere((d) => d != null,
              orElse: () => null);
          if (prev == null || prev.day.month != m) return m;
          return null;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Month labels row.
            Padding(
              padding: const EdgeInsets.only(left: labelW + gap, bottom: 3),
              child: Row(
                children: [
                  for (var c = 0; c < nCols; c++) ...[
                    SizedBox(
                      width: cell,
                      child: Text(
                        monthForColumn(c) != null
                            ? _monthAbbr[monthForColumn(c)!]
                            : '',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.hintColor, fontSize: 9),
                        overflow: TextOverflow.visible,
                        softWrap: false,
                      ),
                    ),
                    if (c < nCols - 1) const SizedBox(width: gap),
                  ],
                ],
              ),
            ),
            // Weekday labels column + the grid.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Weekday labels (show M/W/F to reduce clutter).
                SizedBox(
                  width: labelW,
                  child: Column(
                    children: [
                      for (var r = 0; r < 7; r++) ...[
                        SizedBox(
                          height: cell,
                          child: Text(
                            (r == 1 || r == 3 || r == 5) ? _weekdayLabels[r] : '',
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: theme.hintColor, fontSize: 9),
                          ),
                        ),
                        if (r < 6) const SizedBox(height: gap),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: gap),
                // Week columns.
                for (var c = 0; c < nCols; c++) ...[
                  Column(
                    children: [
                      for (var r = 0; r < 7; r++) ...[
                        _cell(theme, columns[c][r], cell, cellColor),
                        if (r < 6) const SizedBox(height: gap),
                      ],
                    ],
                  ),
                  if (c < nCols - 1) const SizedBox(width: gap),
                ],
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _cell(ThemeData theme, DayActivity? d, double size,
      Color Function(DayActivity) colorFor) {
    if (d == null) {
      // Blank slot (padding before first day / after last).
      return SizedBox(width: size, height: size);
    }
    return Tooltip(
      message: _label(d),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: colorFor(d),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }

  String _label(DayActivity d) {
    final date = '${d.day.month}/${d.day.day}';
    if (!d.active) return '$date · no practice';
    return '$date · ${d.sessions} session${d.sessions == 1 ? '' : 's'} · '
        '${d.itemsSeen} items · ${(d.accuracy * 100).round()}%';
  }
}

/// Line chart of accuracy (%) and median recognition speed (ms) across the most
/// recent sessions. Two y-axes conceptually, normalised to the same plot box.
class SessionTrendChart extends StatelessWidget {
  final List<SessionSummary> sessions;
  const SessionTrendChart({super.key, required this.sessions});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Show at most the last 20 sessions, oldest → newest.
    final recent = sessions.length > 20
        ? sessions.sublist(sessions.length - 20)
        : sessions;
    return Column(
      children: [
        SizedBox(
          height: 160,
          child: CustomPaint(
            size: Size.infinite,
            painter: _TrendPainter(
              sessions: recent,
              accuracyColor: kMasteredColor,
              speedColor: theme.colorScheme.primary,
              gridColor: theme.dividerColor,
              textColor: theme.hintColor,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _swatch(kMasteredColor, 'accuracy %', theme),
            const SizedBox(width: 16),
            _swatch(theme.colorScheme.primary, 'speed (ms)', theme),
          ],
        ),
      ],
    );
  }

  Widget _swatch(Color c, String label, ThemeData theme) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 14, height: 3, color: c),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      );
}

class _TrendPainter extends CustomPainter {
  final List<SessionSummary> sessions;
  final Color accuracyColor;
  final Color speedColor;
  final Color gridColor;
  final Color textColor;

  _TrendPainter({
    required this.sessions,
    required this.accuracyColor,
    required this.speedColor,
    required this.gridColor,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 4.0, rightPad = 4.0, topPad = 8.0, bottomPad = 8.0;
    final plot = Rect.fromLTRB(
        leftPad, topPad, size.width - rightPad, size.height - bottomPad);

    // Gridlines (accuracy reference at 0/50/100%).
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = plot.top + plot.height * (i / 2);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
    }

    if (sessions.isEmpty) return;

    // X positions across sessions (single point centred if only one).
    double xFor(int i) {
      if (sessions.length == 1) return plot.center.dx;
      return plot.left + plot.width * (i / (sessions.length - 1));
    }

    // Accuracy: 0..1 → bottom..top.
    double yAcc(double acc) => plot.bottom - plot.height * acc.clamp(0, 1);

    // Speed: normalise ms to a 0..1200ms window (lower is better → higher line).
    const speedMax = 1200.0;
    double ySpeed(int ms) {
      final norm = (1 - (ms.clamp(0, speedMax.toInt()) / speedMax)).clamp(0.0, 1.0);
      return plot.bottom - plot.height * norm;
    }

    // Label every point when there are few; thin out when crowded so the
    // numbers stay readable. Always label the most recent point.
    final n = sessions.length;
    final step = n <= 6 ? 1 : (n <= 12 ? 2 : 3);
    bool labelAt(int i) => i == n - 1 || i % step == 0;

    _drawLine(canvas, plot, n, xFor,
        (i) => yAcc(sessions[i].accuracy), accuracyColor,
        labelAt: labelAt,
        labelFor: (i) => '${(sessions[i].accuracy * 100).round()}%',
        labelAbove: true);
    _drawLine(canvas, plot, n, xFor,
        (i) => ySpeed(sessions[i].medianLatencyMs), speedColor,
        labelAt: labelAt,
        labelFor: (i) => '${sessions[i].medianLatencyMs}',
        labelAbove: false);
  }

  void _drawLine(Canvas canvas, Rect plot, int n, double Function(int) xFor,
      double Function(int) yFor, Color color,
      {bool Function(int)? labelAt,
      String Function(int)? labelFor,
      bool labelAbove = true}) {
    final line = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final dot = Paint()..color = color;
    final path = Path();
    for (var i = 0; i < n; i++) {
      final p = Offset(xFor(i), yFor(i));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawCircle(p, 3, dot);
    }
    canvas.drawPath(path, line);

    // Value labels near each (selected) point.
    if (labelFor != null && labelAt != null) {
      for (var i = 0; i < n; i++) {
        if (!labelAt(i)) continue;
        _drawLabel(canvas, plot, Offset(xFor(i), yFor(i)), labelFor(i), color,
            above: labelAbove, isLast: i == n - 1);
      }
    }
  }

  void _drawLabel(Canvas canvas, Rect plot, Offset at, String text, Color color,
      {required bool above, required bool isLast}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx - tp.width / 2;
    // Keep labels inside the plot horizontally.
    dx = dx.clamp(plot.left, plot.right - tp.width);
    final dy = above ? at.dy - tp.height - 5 : at.dy + 5;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.sessions != sessions;
}

/// Grid of every curriculum item, colour-coded by status. Tapping shows the
/// item's accuracy and recognition speed.
class ItemMap extends StatelessWidget {
  final List<ItemProgress> items;
  const ItemMap({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final ip in items) _chip(context, theme, ip),
      ],
    );
  }

  Widget _chip(BuildContext context, ThemeData theme, ItemProgress ip) {
    final Color bg;
    final Color fg;
    switch (ip.status) {
      case ItemStatus.mastered:
        bg = kMasteredColor;
        fg = Colors.white;
        break;
      case ItemStatus.learning:
        bg = kLearningColor;
        fg = Colors.black87;
        break;
      case ItemStatus.locked:
        bg = theme.disabledColor.withValues(alpha: 0.12);
        fg = theme.disabledColor;
        break;
    }
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: ip.status == ItemStatus.locked ? null : () => _showDetail(context, ip),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(
          ip.item.text,
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontFamily: 'monospace', color: fg, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, ItemProgress ip) {
    final acc = ip.accuracy == null ? '—' : '${(ip.accuracy! * 100).round()}%';
    final speed = ip.medianLatencyMs == null ? '—' : '${ip.medianLatencyMs}ms';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ip.item.text, style: const TextStyle(fontFamily: 'monospace')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Status', ip.status.name),
            _row('Accuracy', acc),
            _row('Recognition', speed),
            _row('Times seen', '${ip.reps}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );
}
