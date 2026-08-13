import 'package:flutter/material.dart';

/// Parses a string containing ANSI SGR escape sequences (`ESC[...m`) —
/// exactly what Wings forwards verbatim from the game process' stdout —
/// into styled [InlineSpan]s, instead of showing the raw escape bytes as
/// text (e.g. a line like `ESC[33;1m[15:36:33 WARN]...` rendering
/// literally, including the escape codes, in the console panel).
///
/// Supports what real server consoles actually emit: standard 16-color
/// codes (30-37/90-97 foreground, 40-47/100-107 background), 256-color
/// (`38;5;n`/`48;5;n`), 24-bit truecolor (`38;2;r;g;b`/`48;2;r;g;b` — the
/// form Minecraft/Bukkit consoles use for their own §-color codes), bold
/// (`1`) / normal-intensity (`22`), and reset (`0`, or no digits at all).
/// Any other CSI sequence (cursor movement, erase-line, ...) is dropped
/// silently rather than left as garbage text — this is a scrolling,
/// append-only log view, not a terminal emulator, so those have no
/// meaning here. Any unsupported SGR sub-code is likewise ignored rather
/// than crashing, matching this app's "never crash on unexpected data"
/// rule applied to log content, not just WebSocket frames.
List<InlineSpan> parseAnsiToSpans(String text, TextStyle baseStyle) {
  final spans = <InlineSpan>[];
  var cursor = 0;
  var style = baseStyle;

  for (final match in _csiPattern.allMatches(text)) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match.start), style: style));
    }
    if (match.group(2) == 'm') {
      style = _applySgr(match.group(1) ?? '', baseStyle, style);
    }
    cursor = match.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: style));
  }
  if (spans.isEmpty) {
    spans.add(TextSpan(text: text, style: style));
  }
  return spans;
}

/// Matches a CSI sequence: ESC (U+001B) + `[` + digits/semicolons +
/// exactly one letter terminator.
///
/// The literal ESC byte in the pattern is not optional — without it this
/// would also match ordinary bracketed log text such as `[WARN]` or
/// `[Essentials]` (`[` + zero digits + one letter is otherwise
/// indistinguishable from a real CSI sequence) and corrupt it.
final _csiPattern = RegExp('\x1B\\[([0-9;]*)([a-zA-Z])');

TextStyle _applySgr(String rawCodes, TextStyle baseStyle, TextStyle current) {
  final codes = rawCodes.isEmpty ? const [0] : rawCodes.split(';').map((s) => int.tryParse(s) ?? 0).toList();
  var style = current;

  for (var i = 0; i < codes.length; i++) {
    final code = codes[i];
    switch (code) {
      case 0:
        style = baseStyle;
      case 1:
        style = style.copyWith(fontWeight: FontWeight.w700);
      case 22:
        style = style.copyWith(fontWeight: FontWeight.w400);
      case 39:
        style = style.copyWith(color: baseStyle.color);
      case 49:
        style = style.copyWith(backgroundColor: null);
      case >= 30 && <= 37:
        style = style.copyWith(color: _standardColor(code - 30));
      case >= 90 && <= 97:
        style = style.copyWith(color: _standardColor(code - 90, bright: true));
      case >= 40 && <= 47:
        style = style.copyWith(backgroundColor: _standardColor(code - 40));
      case >= 100 && <= 107:
        style = style.copyWith(backgroundColor: _standardColor(code - 100, bright: true));
      case 38:
      case 48:
        final isBackground = code == 48;
        if (i + 4 < codes.length && codes[i + 1] == 2) {
          final color = Color.fromARGB(
            255,
            codes[i + 2].clamp(0, 255),
            codes[i + 3].clamp(0, 255),
            codes[i + 4].clamp(0, 255),
          );
          style = isBackground ? style.copyWith(backgroundColor: color) : style.copyWith(color: color);
          i += 4;
        } else if (i + 2 < codes.length && codes[i + 1] == 5) {
          final color = _ansi256Color(codes[i + 2]);
          style = isBackground ? style.copyWith(backgroundColor: color) : style.copyWith(color: color);
          i += 2;
        }
      default:
        break;
    }
  }
  return style;
}

/// Classic "Tango" 16-color terminal palette — legible on a dark
/// background (unlike literal ANSI black, which would be invisible on
/// one). [index] is 0-7 (black..white).
Color _standardColor(int index, {bool bright = false}) {
  const normal = [
    Color(0xFF4D4D4D),
    Color(0xFFCC0000),
    Color(0xFF4E9A06),
    Color(0xFFC4A000),
    Color(0xFF3465A4),
    Color(0xFF75507B),
    Color(0xFF06989A),
    Color(0xFFD3D7CF),
  ];
  const brightColors = [
    Color(0xFF555753),
    Color(0xFFEF2929),
    Color(0xFF8AE234),
    Color(0xFFFCE94F),
    Color(0xFF729FCF),
    Color(0xFFAD7FA8),
    Color(0xFF34E2E2),
    Color(0xFFEEEEEC),
  ];
  final palette = bright ? brightColors : normal;
  return palette[index.clamp(0, 7)];
}

/// Standard xterm 256-color palette: 0-15 mirror the 16-color palette,
/// 16-231 are a 6x6x6 color cube, 232-255 are a greyscale ramp.
Color _ansi256Color(int n) {
  if (n < 8) return _standardColor(n);
  if (n < 16) return _standardColor(n - 8, bright: true);
  if (n < 232) {
    final i = n - 16;
    final r = i ~/ 36;
    final g = (i ~/ 6) % 6;
    final b = i % 6;
    int component(int level) => level == 0 ? 0 : 55 + level * 40;
    return Color.fromARGB(255, component(r), component(g), component(b));
  }
  final level = 8 + (n - 232) * 10;
  return Color.fromARGB(255, level, level, level);
}
