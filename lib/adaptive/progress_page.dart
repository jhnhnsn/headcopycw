import 'package:flutter/material.dart';

import 'progress_stats.dart';
import 'progress_store.dart';
import 'srs.dart';

/// Full progress view: a session trend chart (accuracy + recognition speed)
/// and a curriculum item map colour-coded mastered / learning / locked.
/// Charts are hand-drawn with CustomPainter to avoid extra dependencies.
class ProgressPage extends StatelessWidget {
  final SrsScheduler scheduler;
  final List<SessionSummary> sessions;

  const ProgressPage({
    super.key,
    required this.scheduler,
    required this.sessions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = summarize(scheduler);
    final items = itemProgressList(scheduler);

    return Scaffold(
      appBar: AppBar(title: const Text('Your Progress')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _summaryHeader(theme, summary),
          const SizedBox(height: 24),
          Text('Recent sessions', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (sessions.isEmpty)
            _emptyNote(theme, 'Finish a timed session to see your trend here.')
          else
            SessionTrendChart(sessions: sessions),
          const SizedBox(height: 24),
          Text('What you\'ve unlocked', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _legendDot(theme, kMasteredColor, 'mastered'),
              _legendDot(theme, kLearningColor, 'learning'),
              _legendDot(theme, theme.disabledColor.withValues(alpha: 0.3), 'locked'),
            ],
          ),
          const SizedBox(height: 12),
          _ItemMap(items: items),
        ],
      ),
    );
  }

  Widget _summaryHeader(ThemeData theme, ProgressSummary s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${s.unlocked} of ${s.total} items unlocked',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 10,
            child: Row(
              children: [
                Expanded(
                  flex: (s.masteredFraction * 1000).round().clamp(0, 1000),
                  child: Container(color: kMasteredColor),
                ),
                Expanded(
                  flex: ((s.unlockedFraction - s.masteredFraction) * 1000)
                      .round()
                      .clamp(0, 1000),
                  child: Container(color: kLearningColor),
                ),
                Expanded(
                  flex: ((1 - s.unlockedFraction) * 1000).round().clamp(0, 1000),
                  child: Container(color: theme.disabledColor.withValues(alpha: 0.15)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('${s.mastered} mastered · ${s.learning} learning · ${s.locked} locked',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor)),
      ],
    );
  }

  Widget _emptyNote(ThemeData theme, String text) => Container(
        padding: const EdgeInsets.all(20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor)),
      );

  Widget _legendDot(ThemeData theme, Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      );
}

/// Shared status colours used by the progress page and the home panel.
const Color kMasteredColor = Color(0xFF2E7D32); // green 800
const Color kLearningColor = Color(0xFFF9A825); // amber 800

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

    _drawLine(canvas, plot, sessions.length, xFor,
        (i) => yAcc(sessions[i].accuracy), accuracyColor);
    _drawLine(canvas, plot, sessions.length, xFor,
        (i) => ySpeed(sessions[i].medianLatencyMs), speedColor);
  }

  void _drawLine(Canvas canvas, Rect plot, int n, double Function(int) xFor,
      double Function(int) yFor, Color color) {
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
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.sessions != sessions;
}

/// Grid of every curriculum item, colour-coded by status. Tapping shows the
/// item's accuracy and recognition speed.
class _ItemMap extends StatelessWidget {
  final List<ItemProgress> items;
  const _ItemMap({required this.items});

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
