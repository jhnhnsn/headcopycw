import 'package:flutter/widgets.dart';

/// The HeadCopy wordmark, drawn natively from vector outlines (Manrope
/// ExtraBold, tightly tracked; the capital C carries the accent). No font
/// dependency, no bundled asset — the glyph paths are baked in below.
///
/// Give it a [height]; width is derived from the mark's aspect ratio. [inkColor]
/// draws "Head" + "opy" (defaults to the ambient DefaultTextStyle color, so it
/// themes automatically); [accentColor] draws the "C".
class HeadCopyWordmark extends StatelessWidget {
  final double height;
  final Color? inkColor;
  final Color accentColor;

  const HeadCopyWordmark({
    super.key,
    this.height = 24,
    this.inkColor,
    this.accentColor = const Color(0xFFEA6A1E),
  });

  // Tight bounding box of the outlines, in font units (y-up).
  // maxY is the cap top; minY is the descender bottom (below the baseline).
  static const double _minX = 140;
  static const double _minY = -480;   // "y" descender
  static const double _maxX = 9744.0;
  static const double _maxY = 1470;   // cap top

  static const double _fullH = _maxY - _minY;        // cap top → descender
  static const double _capH = _maxY;                 // baseline (0) → cap top
  // A little vertical breathing room baked in so no ink ever touches the box
  // edge (which the anti-aliased rasteriser would otherwise shave).
  static const double _padUnits = 90;

  // [height] is the CAP height (the visible letter height you'd expect). The
  // widget's box is taller than that to hold the descender plus padding.
  double get _boxH => height * (_fullH + 2 * _padUnits) / _capH;
  double get _boxW => height * (_maxX - _minX) / _capH;

  @override
  Widget build(BuildContext context) {
    final ink = inkColor ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFF1A1712);
    return SizedBox(
      height: _boxH,
      width: _boxW,
      child: CustomPaint(
        size: Size(_boxW, _boxH),
        painter: _WordmarkPainter(ink, accentColor),
      ),
    );
  }
}

class _WordmarkPainter extends CustomPainter {
  final Color ink;
  final Color accent;
  const _WordmarkPainter(this.ink, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    // Scale font units → pixels using the cap height, so a given widget height
    // yields the expected letter height. The box is (fullH + 2*pad) tall.
    const pad = HeadCopyWordmark._padUnits;
    const totalUnitsH = HeadCopyWordmark._fullH + 2 * pad;
    final scale = size.height / totalUnitsH;

    canvas.save();
    // Map font units (y-up) into the widget box (y-down), inset by pad so the
    // cap top and the descender bottom each sit `pad` units from the edges.
    canvas.translate(
      -HeadCopyWordmark._minX * scale,
      (HeadCopyWordmark._maxY + pad) * scale,
    );
    canvas.scale(scale, -scale);

    final inkPaint = Paint()..color = ink..isAntiAlias = true..style = PaintingStyle.fill;
    final accentPaint = Paint()..color = accent..isAntiAlias = true..style = PaintingStyle.fill;

    for (final g in _inkGlyphs) {
      canvas.drawPath(g, inkPaint);
    }
    for (final g in _accentGlyphs) {
      canvas.drawPath(g, accentPaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WordmarkPainter old) => old.ink != ink || old.accent != accent;
}

// ---- baked glyph outlines -------------------------------------------------

final List<Path> _inkGlyphs = [
      _glyph(r'M140 0V1440H412V848H1056V1440H1328V0H1056V594H412V0Z', 0),
      _glyph(r'M642 -30Q476 -30 349.5 41.5Q223 113 151.5 238.5Q80 364 80 526Q80 703 150.0 834.0Q220 965 343.0 1037.5Q466 1110 626 1110Q796 1110 915.0 1030.0Q1034 950 1091.0 805.0Q1148 660 1131 464H862V564Q862 729 809.5 801.5Q757 874 638 874Q499 874 433.5 789.5Q368 705 368 540Q368 389 433.5 306.5Q499 224 626 224Q706 224 763.0 259.0Q820 294 850 360L1122 282Q1061 134 929.5 52.0Q798 -30 642 -30ZM284 464V666H1000V464Z', 1398.0),
      _glyph(r'M440 -30Q324 -30 243.5 14.5Q163 59 121.5 133.5Q80 208 80 298Q80 373 103.0 435.0Q126 497 177.5 544.5Q229 592 316 624Q376 646 459.0 663.0Q542 680 647.0 695.5Q752 711 878 730L780 676Q780 772 734.0 817.0Q688 862 580 862Q520 862 455.0 833.0Q390 804 364 730L118 808Q159 942 272.0 1026.0Q385 1110 580 1110Q723 1110 834.0 1066.0Q945 1022 1002 914Q1034 854 1040.0 794.0Q1046 734 1046 660V0H808V222L842 176Q763 67 671.5 18.5Q580 -30 440 -30ZM498 184Q573 184 624.5 210.5Q676 237 706.5 271.0Q737 305 748 328Q769 372 772.5 430.5Q776 489 776 528L856 508Q735 488 660.0 474.5Q585 461 539.0 450.0Q493 439 458 426Q418 410 393.5 391.5Q369 373 357.5 351.0Q346 329 346 302Q346 265 364.5 238.5Q383 212 417.0 198.0Q451 184 498 184Z', 2544.0),
      _glyph(r'M578 -30Q429 -30 317.0 45.0Q205 120 142.5 249.0Q80 378 80 540Q80 705 143.5 833.5Q207 962 322.0 1036.0Q437 1110 592 1110Q746 1110 851.0 1035.0Q956 960 1010.0 831.0Q1064 702 1064 540Q1064 378 1009.5 249.0Q955 120 847.0 45.0Q739 -30 578 -30ZM622 212Q713 212 767.5 253.0Q822 294 846.0 368.0Q870 442 870 540Q870 638 846.0 712.0Q822 786 769.5 827.0Q717 868 632 868Q541 868 482.5 823.5Q424 779 396.0 704.5Q368 630 368 540Q368 449 395.0 374.5Q422 300 478.0 256.0Q534 212 622 212ZM870 0V740H836V1440H1110V0Z', 3640.0),
      _glyph(r'M626 -30Q463 -30 340.0 43.0Q217 116 148.5 244.5Q80 373 80 540Q80 709 150.0 837.5Q220 966 343.0 1038.0Q466 1110 626 1110Q789 1110 912.5 1037.0Q1036 964 1105.0 835.5Q1174 707 1174 540Q1174 372 1104.5 243.5Q1035 115 911.5 42.5Q788 -30 626 -30ZM626 224Q757 224 821.5 312.5Q886 401 886 540Q886 684 820.5 770.0Q755 856 626 856Q537 856 480.0 816.0Q423 776 395.5 705.0Q368 634 368 540Q368 395 433.5 309.5Q499 224 626 224Z', 6242.0),
      _glyph(r'M670 -30Q509 -30 401.0 45.0Q293 120 238.5 249.0Q184 378 184 540Q184 702 238.0 831.0Q292 960 397.0 1035.0Q502 1110 656 1110Q811 1110 926.0 1036.0Q1041 962 1104.5 833.5Q1168 705 1168 540Q1168 378 1105.5 249.0Q1043 120 931.0 45.0Q819 -30 670 -30ZM138 -480V1080H378V340H412V-480ZM626 212Q714 212 770.0 256.0Q826 300 853.0 374.5Q880 449 880 540Q880 630 852.0 704.5Q824 779 765.5 823.5Q707 868 616 868Q531 868 478.5 827.0Q426 786 402.0 712.0Q378 638 378 540Q378 442 402.0 368.0Q426 294 480.5 253.0Q535 212 626 212Z', 7426.0),
      _glyph(r'M278 -480 486 92 490 -76 20 1080H302L618 262H554L868 1080H1140L530 -480Z', 8604.0),
];

final List<Path> _accentGlyphs = [
      _glyph(r'M758 -30Q542 -30 385.5 64.0Q229 158 144.5 327.0Q60 496 60 720Q60 944 144.5 1113.0Q229 1282 385.5 1376.0Q542 1470 758 1470Q1006 1470 1174.5 1347.0Q1343 1224 1412 1014L1138 938Q1098 1069 1003.0 1141.5Q908 1214 758 1214Q621 1214 529.5 1153.0Q438 1092 392.0 981.0Q346 870 346 720Q346 570 392.0 459.0Q438 348 529.5 287.0Q621 226 758 226Q908 226 1003.0 299.0Q1098 372 1138 502L1412 426Q1343 216 1174.5 93.0Q1006 -30 758 -30Z', 4820.0),
];

/// Builds a [Path] from an absolute SVG "d" string (subset: M L H V Q Z),
/// translated by [dx] in font units. These outlines use only those commands.
Path _glyph(String d, double dx) {
  final path = Path();
  final tokens = _tokenize(d);
  int i = 0;
  double cx = 0, cy = 0, sx = 0, sy = 0;
  String cmd = '';
  double num() => tokens[i++] as double;
  while (i < tokens.length) {
    final t = tokens[i];
    if (t is String) { cmd = t; i++; }
    switch (cmd) {
      case 'M':
        cx = num() + dx; cy = num(); sx = cx; sy = cy;
        path.moveTo(cx, cy);
        // Per SVG: coordinate pairs following the initial moveto are treated
        // as implicit lineto commands until the next command letter. Without
        // this, glyphs like "y" (M x y  x y  x y ...) get drawn as a series of
        // movetos and lose their shape.
        cmd = 'L';
        break;
      case 'L':
        cx = num() + dx; cy = num();
        path.lineTo(cx, cy);
        break;
      case 'H':
        cx = num() + dx;
        path.lineTo(cx, cy);
        break;
      case 'V':
        cy = num();
        path.lineTo(cx, cy);
        break;
      case 'Q':
        final x1 = num() + dx, y1 = num();
        cx = num() + dx; cy = num();
        path.quadraticBezierTo(x1, y1, cx, cy);
        break;
      case 'Z':
        path.close();
        cx = sx; cy = sy;
        break;
      default:
        i++; // skip anything unexpected
    }
  }
  return path;
}

/// Splits an SVG path string into command letters (String) and numbers (double).
List<Object> _tokenize(String d) {
  final out = <Object>[];
  final re = RegExp(r'[MLHVQZ]|-?\d*\.?\d+');
  for (final m in re.allMatches(d)) {
    final s = m.group(0)!;
    if (s.length == 1 && RegExp(r'[MLHVQZ]').hasMatch(s)) {
      out.add(s);
    } else {
      out.add(double.parse(s));
    }
  }
  return out;
}
