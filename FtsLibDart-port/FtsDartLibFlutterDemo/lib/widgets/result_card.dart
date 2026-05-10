import 'package:flutter/material.dart';

import '../services/index_service.dart';

/// Renders one search result row — mirrors the C# ResultCardTemplate.
///
/// Layout:
///   Book title  (blue, Google-style, selectable)
///   Snippet     (gray, with <mark> tags rendered as bold black)
///   Thin separator line at the bottom
class ResultCard extends StatelessWidget {
  final SearchResultItem item;

  const ResultCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEBEBEB))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title — selectable, blue link style
          SelectableText(
            item.bookTitle,
            style: const TextStyle(
              fontSize: 18,
              color: Color(0xFF1A0DAB),
            ),
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 3),

          // Snippet — rendered with <mark> highlights as bold spans
          _SnippetText(html: item.snippet),
        ],
      ),
    );
  }
}

/// Renders a snippet string that may contain <mark>…</mark> tags.
/// Highlighted segments are shown in bold black; plain text is gray.
/// Uses a [SelectableText.rich] so the user can copy the text.
class _SnippetText extends StatelessWidget {
  final String html;

  const _SnippetText({required this.html});

  @override
  Widget build(BuildContext context) {
    return SelectableText.rich(
      _parseSnippet(html),
      textDirection: TextDirection.rtl,
      style: const TextStyle(
        fontSize: 13,
        color: Color(0xFF4D5156),
        height: 1.54,
      ),
    );
  }

  /// Parses a snippet string with <mark>…</mark> tags into a [TextSpan].
  /// Odd segments (inside <mark>) are bold black; even segments are plain gray.
  static TextSpan _parseSnippet(String raw) {
    const open = '<mark>';
    const close = '</mark>';

    final spans = <InlineSpan>[];
    int pos = 0;
    bool inMark = false;

    while (pos < raw.length) {
      final tag = inMark ? close : open;
      final tagIdx = raw.toLowerCase().indexOf(tag, pos);

      final segment = tagIdx < 0 ? raw.substring(pos) : raw.substring(pos, tagIdx);

      // Decode the two entities the renderer emits
      final text = segment.replaceAll('&amp;', '&').replaceAll('&gt;', '>');

      if (text.isNotEmpty) {
        spans.add(TextSpan(
          text: text,
          style: inMark
              ? const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                )
              : null, // inherits parent style (gray)
        ));
      }

      if (tagIdx < 0) break;
      pos = tagIdx + tag.length;
      inMark = !inMark;
    }

    return TextSpan(children: spans);
  }
}
