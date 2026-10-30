import 'package:flutter/material.dart';

import '../theme/app_text_styles.dart';

/// The Markdown a chat model writes, rendered rather than shown raw.
///
/// Answers arrived as `**Total spending:** £1,240` and `- Food: …`, asterisks
/// and all. This covers what models actually use in a chat answer — headings,
/// bullet and numbered lists, fenced code, rules, bold, italic, inline code and
/// links (shown as their text) — and leaves anything else, a table for
/// instance, as the text it is. It has to cope with a half-streamed answer, so
/// an unclosed `**` is simply left as typed.
///
/// Written here rather than taken from a package: `flutter_markdown` is
/// discontinued, and this is the whole of what the chat needs.
class MarkdownText extends StatelessWidget {
  const MarkdownText(this.source, {super.key, this.style});

  final String source;

  /// The body style; headings and code are derived from it.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = style ?? theme.textTheme.bodyMedium ?? const TextStyle();
    final blocks = parseBlocks(source);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < blocks.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : blocks[i].gapBefore),
            child: _render(context, blocks[i], base),
          ),
      ],
    );
  }

  Widget _render(BuildContext context, MarkdownBlock block, TextStyle base) {
    final theme = Theme.of(context);
    switch (block.kind) {
      case MarkdownBlockKind.heading:
        final scale = switch (block.level) {
          1 => 1.3,
          2 => 1.18,
          _ => 1.06,
        };
        return Text.rich(
          TextSpan(
            children: inlineSpans(
              block.text,
              base.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: (base.fontSize ?? 14) * scale,
              ),
            ),
          ),
        );
      case MarkdownBlockKind.bullet || MarkdownBlockKind.numbered:
        return Padding(
          padding: EdgeInsets.only(left: 12.0 * block.level),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: block.kind == MarkdownBlockKind.bullet ? 14 : 22,
                child: Text(block.marker, style: base),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(children: inlineSpans(block.text, base)),
                ),
              ),
            ],
          ),
        );
      case MarkdownBlockKind.code:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              block.text,
              style: AppTextStyles.monoSmall.copyWith(color: base.color),
            ),
          ),
        );
      case MarkdownBlockKind.rule:
        return Divider(height: 8, color: theme.colorScheme.outlineVariant);
      case MarkdownBlockKind.paragraph:
        return Text.rich(TextSpan(children: inlineSpans(block.text, base)));
    }
  }

  // ── Parsing ─────────────────────────────────────────────────────────────

  static final _heading = RegExp(r'^(#{1,6})\s+(.*)$');
  static final _bullet = RegExp(r'^(\s*)[-*+•]\s+(.*)$');
  static final _numbered = RegExp(r'^(\s*)(\d{1,3})[.)]\s+(.*)$');
  static final _rule = RegExp(r'^\s*([-*_])(\s*\1){2,}\s*$');
  static final _fence = RegExp(r'^\s*```');

  /// [source] split into blocks. Public for tests.
  static List<MarkdownBlock> parseBlocks(String source) {
    final blocks = <MarkdownBlock>[];
    final lines = source.replaceAll('\r\n', '\n').split('\n');
    final paragraph = <String>[];
    var blankBefore = false;

    double gap() => blocks.isEmpty ? 0 : (blankBefore ? 10 : 4);
    void add(MarkdownBlock b) {
      blocks.add(b);
      blankBefore = false;
    }

    void flush() {
      if (paragraph.isEmpty) return;
      add(
        MarkdownBlock(
          MarkdownBlockKind.paragraph,
          paragraph.join('\n'),
          gapBefore: gap(),
        ),
      );
      paragraph.clear();
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (_fence.hasMatch(line)) {
        flush();
        final code = <String>[];
        // Until the closing fence — or the end, while it is still streaming.
        while (++i < lines.length && !_fence.hasMatch(lines[i])) {
          code.add(lines[i]);
        }
        add(
          MarkdownBlock(
            MarkdownBlockKind.code,
            code.join('\n'),
            gapBefore: gap(),
          ),
        );
        continue;
      }
      if (line.trim().isEmpty) {
        flush();
        blankBefore = true;
        continue;
      }
      if (_rule.hasMatch(line)) {
        flush();
        add(MarkdownBlock(MarkdownBlockKind.rule, '', gapBefore: gap()));
        continue;
      }
      if (_heading.firstMatch(line) case final m?) {
        flush();
        add(
          MarkdownBlock(
            MarkdownBlockKind.heading,
            m.group(2)!.trim(),
            level: m.group(1)!.length,
            gapBefore: blocks.isEmpty ? 0 : 10,
          ),
        );
        continue;
      }
      if (_bullet.firstMatch(line) case final m?) {
        flush();
        add(
          MarkdownBlock(
            MarkdownBlockKind.bullet,
            m.group(2)!,
            level: m.group(1)!.length ~/ 2,
            marker: '•',
            gapBefore: blankBefore ? gap() : (blocks.isEmpty ? 0 : 2),
          ),
        );
        continue;
      }
      if (_numbered.firstMatch(line) case final m?) {
        flush();
        add(
          MarkdownBlock(
            MarkdownBlockKind.numbered,
            m.group(3)!,
            level: m.group(1)!.length ~/ 2,
            marker: '${m.group(2)}.',
            gapBefore: blankBefore ? gap() : (blocks.isEmpty ? 0 : 2),
          ),
        );
        continue;
      }
      paragraph.add(line);
    }
    flush();
    return blocks;
  }

  static final _inline = RegExp(
    r'(\*\*|__)(?=\S)(.+?)(?<=\S)\1' // bold
    r'|`([^`\n]+)`' // code
    r'|\[([^\]\n]+)\]\(([^)\s]+)\)' // link
    r'|\*(?=[^\s*])([^*\n]+?)(?<=\S)\*' // *italic*
    r'|(?<![A-Za-z0-9_])_(?=\S)([^_\n]+?)(?<=\S)_(?![A-Za-z0-9_])', // _italic_
  );

  /// [text]'s inline formatting as spans over [style]. Public for tests.
  static List<InlineSpan> inlineSpans(String text, TextStyle style) {
    final spans = <InlineSpan>[];
    var at = 0;
    for (final m in _inline.allMatches(text)) {
      if (m.start > at) {
        spans.add(TextSpan(text: text.substring(at, m.start), style: style));
      }
      if (m.group(2) != null) {
        spans.addAll(
          inlineSpans(m.group(2)!, style.copyWith(fontWeight: FontWeight.w700)),
        );
      } else if (m.group(3) != null) {
        spans.add(
          TextSpan(
            text: m.group(3),
            style: AppTextStyles.monoSmall.copyWith(
              color: style.color,
              fontSize: (style.fontSize ?? 14) * 0.92,
            ),
          ),
        );
      } else if (m.group(4) != null) {
        spans.addAll(
          inlineSpans(
            m.group(4)!,
            style.copyWith(decoration: TextDecoration.underline),
          ),
        );
      } else {
        final inner = m.group(6) ?? m.group(7)!;
        spans.addAll(
          inlineSpans(inner, style.copyWith(fontStyle: FontStyle.italic)),
        );
      }
      at = m.end;
    }
    if (at < text.length) {
      spans.add(TextSpan(text: text.substring(at), style: style));
    }
    return spans;
  }
}

enum MarkdownBlockKind { paragraph, heading, bullet, numbered, code, rule }

/// One block of a Markdown answer. Public for tests.
class MarkdownBlock {
  const MarkdownBlock(
    this.kind,
    this.text, {
    this.level = 0,
    this.marker = '',
    this.gapBefore = 0,
  });

  final MarkdownBlockKind kind;
  final String text;

  /// Heading level, or list nesting depth.
  final int level;

  /// A list item's bullet or number.
  final String marker;

  /// Space above it, in logical pixels.
  final double gapBefore;
}
