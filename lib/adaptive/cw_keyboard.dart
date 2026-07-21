import 'package:flutter/material.dart';

/// An on-screen keyboard exposing only the characters that can be sent in
/// Morse — letters, digits, the four supported punctuation/prosign glyphs, a
/// space (phrases contain them), plus backspace and enter. The system keyboard
/// is suppressed so the learner isn't distracted by autocorrect or keys that
/// could never be a valid answer.
class CwKeyboard extends StatelessWidget {
  /// Append a character to the answer.
  final ValueChanged<String> onKey;

  /// Delete the last character.
  final VoidCallback onBackspace;

  /// Submit the answer.
  final VoidCallback onEnter;

  const CwKeyboard({
    super.key,
    required this.onKey,
    required this.onBackspace,
    required this.onEnter,
  });

  // Letter/digit rows. Punctuation + controls live on the last row.
  static const _rows = <String>[
    'ABCDEFGHIJ',
    'KLMNOPQRST',
    'UVWXYZ',
    '0123456789',
    '.,/?', // supported punctuation / prosign glyphs
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in _rows) _buildRow(theme, row),
        // Controls row: space (wide), backspace, enter.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: _key(theme, label: 'space', onTap: () => onKey(' ')),
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 2,
                child: _key(theme, icon: Icons.backspace_outlined,
                    onTap: onBackspace),
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 3,
                child: _key(theme, label: 'enter', icon: Icons.keyboard_return,
                    onTap: onEnter, filled: true),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRow(ThemeData theme, String chars) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final c in chars.split('')) ...[
            Expanded(child: _key(theme, label: c, onTap: () => onKey(c))),
            const SizedBox(width: 4),
          ],
        ]..removeLast(), // drop trailing gap
      ),
    );
  }

  Widget _key(ThemeData theme,
      {String? label,
      IconData? icon,
      required VoidCallback onTap,
      bool filled = false}) {
    final bg = filled
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final fg = filled ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          child: icon != null && label == null
              ? Icon(icon, size: 20, color: fg)
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 16, color: fg),
                      const SizedBox(width: 4),
                    ],
                    Text(label ?? '',
                        style: TextStyle(
                          color: fg,
                          fontFamily: 'monospace',
                          fontSize: label!.length > 1 ? 13 : 17,
                          fontWeight: FontWeight.w600,
                        )),
                  ],
                ),
        ),
      ),
    );
  }
}
