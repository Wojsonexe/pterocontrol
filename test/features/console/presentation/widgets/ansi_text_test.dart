import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pterodactyl_mobile/features/console/presentation/widgets/ansi_text.dart';

const esc = '\x1B';
const base = TextStyle(color: Color(0xFFC9D1D9), fontSize: 13);

String plainText(List<InlineSpan> spans) {
  final buffer = StringBuffer();
  for (final span in spans) {
    if (span is TextSpan && span.text != null) buffer.write(span.text);
  }
  return buffer.toString();
}

void main() {
  group('parseAnsiToSpans — plain text', () {
    test('text with no escape codes is returned as a single span in the base style', () {
      final spans = parseAnsiToSpans('Server started', base);

      expect(spans, hasLength(1));
      expect((spans.single as TextSpan).text, 'Server started');
      expect((spans.single as TextSpan).style, base);
    });

    test('empty string produces a single empty span, not an empty list', () {
      final spans = parseAnsiToSpans('', base);

      expect(spans, hasLength(1));
      expect((spans.single as TextSpan).text, '');
    });
  });

  group('parseAnsiToSpans — does not corrupt ordinary bracketed log text', () {
    test('"[WARN]" without a preceding ESC byte is left untouched', () {
      final spans = parseAnsiToSpans('[15:36:33 WARN]: [Essentials]', base);

      expect(plainText(spans), '[15:36:33 WARN]: [Essentials]');
    });
  });

  group('parseAnsiToSpans — truecolor (what Minecraft/Bukkit consoles emit)', () {
    test('24-bit foreground color is applied to the following text', () {
      final spans = parseAnsiToSpans('$esc[38;2;170;0;0mDARK RED TEXT', base);

      expect(spans, hasLength(1));
      final span = spans.single as TextSpan;
      expect(span.text, 'DARK RED TEXT');
      expect(span.style?.color, const Color(0xFFAA0000));
    });

    test('reset ("ESC[m", no digits) returns to the base style', () {
      final spans = parseAnsiToSpans('$esc[38;2;170;0;0mred$esc[mnormal', base);

      expect(spans, hasLength(2));
      expect((spans[0] as TextSpan).text, 'red');
      expect((spans[0] as TextSpan).style?.color, const Color(0xFFAA0000));
      expect((spans[1] as TextSpan).text, 'normal');
      expect((spans[1] as TextSpan).style, base);
    });

    test('full text content is preserved across multiple color changes', () {
      final input = '$esc[33;1mWARN$esc[m: $esc[38;2;255;85;85msomething broke';
      final spans = parseAnsiToSpans(input, base);

      expect(plainText(spans), 'WARN: something broke');
    });
  });

  group('parseAnsiToSpans — bold', () {
    test('bold (1) then normal-intensity (22)', () {
      final spans = parseAnsiToSpans('$esc[1mBold$esc[22mNormal', base);

      expect((spans[0] as TextSpan).style?.fontWeight, FontWeight.w700);
      expect((spans[1] as TextSpan).style?.fontWeight, FontWeight.w400);
    });

    test('combined SGR codes in one sequence ("33;1" = yellow + bold)', () {
      final spans = parseAnsiToSpans('$esc[33;1mWARN', base);
      final style = (spans.single as TextSpan).style;

      expect(style?.fontWeight, FontWeight.w700);
      expect(style?.color, isNotNull);
    });
  });

  group('parseAnsiToSpans — standard 16-color codes', () {
    test('standard foreground red (31)', () {
      final spans = parseAnsiToSpans('$esc[31mred text', base);
      expect((spans.single as TextSpan).style?.color, isNotNull);
    });

    test('bright foreground colors (90-97) differ from standard (30-37)', () {
      final standard = parseAnsiToSpans('$esc[31mtext', base).single as TextSpan;
      final bright = parseAnsiToSpans('$esc[91mtext', base).single as TextSpan;
      expect(standard.style?.color, isNot(bright.style?.color));
    });
  });

  group('parseAnsiToSpans — 256-color', () {
    test('"38;5;196" (256-color red) is applied', () {
      final spans = parseAnsiToSpans('$esc[38;5;196mtext', base);
      expect((spans.single as TextSpan).style?.color, isNotNull);
    });
  });

  group('parseAnsiToSpans — safety', () {
    test('an unsupported SGR sub-code (e.g. underline = 4) does not throw and is ignored', () {
      expect(() => parseAnsiToSpans('$esc[4munderlined?', base), returnsNormally);
      final spans = parseAnsiToSpans('$esc[4munderlined?', base);
      expect(plainText(spans), 'underlined?');
    });

    test('a non-SGR CSI sequence (cursor movement) is dropped, not shown as garbage', () {
      final spans = parseAnsiToSpans('before$esc[2Kafter', base);
      expect(plainText(spans), 'beforeafter');
    });
  });
}
