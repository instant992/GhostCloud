import 'package:foxcloud/services/purchase_service.dart';
import 'package:foxcloud/state.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Widget that fetches active announcements from the server admin panel
/// and displays them in a card at the top of the dashboard.
/// Supports: custom bg/text colors, dismiss, buttons, rich text
/// (bold **text**, italic _text_, underline __text__, strikethrough ~~text~~).
class AnnounceWidget extends ConsumerStatefulWidget {
  const AnnounceWidget({super.key});

  @override
  ConsumerState<AnnounceWidget> createState() => _AnnounceWidgetState();
}

class _AnnounceWidgetState extends ConsumerState<AnnounceWidget> {
  List<ServerAnnouncement> _announcements = [];
  Set<int> _dismissedIds = {};
  bool _loaded = false;

  static const String _prefsDismissedKey = 'dismissed_announcement_ids';

  @override
  void initState() {
    super.initState();
    _loadDismissed().then((_) => _loadAnnouncements());
  }

  Future<void> _loadDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsDismissedKey) ?? [];
    _dismissedIds = list.map((s) => int.tryParse(s) ?? 0).toSet();
  }

  Future<void> _saveDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _prefsDismissedKey, _dismissedIds.map((id) => id.toString()).toList());
  }

  Future<void> _loadAnnouncements() async {
    final result = await PurchaseService.instance.fetchAnnouncements();
    if (mounted) {
      setState(() {
        _announcements = result;
        _loaded = true;
      });
    }
  }

  void _dismiss(int id) {
    setState(() {
      _dismissedIds.add(id);
    });
    _saveDismissed();
  }

  /// Parse color string like "#FF8C42" to Color.
  Color? _parseColor(String hex) {
    if (hex.isEmpty) return null;
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length == 8) {
      final val = int.tryParse(hex, radix: 16);
      if (val != null) return Color(val);
    }
    return null;
  }

  /// Build rich text spans supporting **bold**, _italic_, __underline__, ~~strike~~, plus URL detection.
  List<InlineSpan> _buildRichSpans(
      BuildContext context, String text, Color? textColor) {
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: textColor,
        );

    // First split by URLs, then apply formatting within each non-URL segment.
    final urlPattern = RegExp(r'https?://[^\s]+', caseSensitive: false);
    final spans = <InlineSpan>[];
    var lastIndex = 0;

    for (final match in urlPattern.allMatches(text)) {
      if (match.start > lastIndex) {
        _addFormattedSpans(
            spans, text.substring(lastIndex, match.start), style);
      }
      final url = match.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: style?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () => globalState.openUrl(url),
      ));
      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      _addFormattedSpans(spans, text.substring(lastIndex), style);
    }

    return spans;
  }

  /// Parse markdown-like formatting within a text segment.
  void _addFormattedSpans(
      List<InlineSpan> spans, String text, TextStyle? baseStyle) {
    // Pattern: **bold**, __underline__, ~~strikethrough~~, _italic_
    final fmtPattern = RegExp(
      r'\*\*(.+?)\*\*|__(.+?)__|~~(.+?)~~|_(.+?)_',
    );

    var lastIndex = 0;
    for (final match in fmtPattern.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(
            text: text.substring(lastIndex, match.start), style: baseStyle));
      }

      if (match.group(1) != null) {
        // **bold**
        spans.add(TextSpan(
            text: match.group(1),
            style: baseStyle?.copyWith(fontWeight: FontWeight.bold)));
      } else if (match.group(2) != null) {
        // __underline__
        spans.add(TextSpan(
            text: match.group(2),
            style: baseStyle?.copyWith(decoration: TextDecoration.underline)));
      } else if (match.group(3) != null) {
        // ~~strikethrough~~
        spans.add(TextSpan(
            text: match.group(3),
            style:
                baseStyle?.copyWith(decoration: TextDecoration.lineThrough)));
      } else if (match.group(4) != null) {
        // _italic_
        spans.add(TextSpan(
            text: match.group(4),
            style: baseStyle?.copyWith(fontStyle: FontStyle.italic)));
      }

      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(
          TextSpan(text: text.substring(lastIndex), style: baseStyle));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _announcements.isEmpty) {
      return const SizedBox.shrink();
    }

    final visible = _announcements
        .where((a) => !_dismissedIds.contains(a.id))
        .toList();

    if (visible.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: visible.map((a) {
        final bgColor = _parseColor(a.bgColor);
        final textColor = _parseColor(a.textColor);
        final theme = Theme.of(context);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: bgColor ?? theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: bgColor != null
                    ? bgColor.withValues(alpha: 0.3)
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: a.isDismissible ? 36 : 16,
                    top: 12,
                    bottom: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          children:
                              _buildRichSpans(context, a.text, textColor),
                        ),
                      ),
                      if (a.buttons.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: a.buttons.map((btn) {
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: btn.url.isNotEmpty
                                    ? () => globalState.openUrl(btn.url)
                                    : null,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: (textColor ?? Colors.white)
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    btn.label,
                                    style: TextStyle(
                                      color: textColor ??
                                          theme.colorScheme.onSurface,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                if (a.isDismissible)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: (textColor ?? theme.colorScheme.onSurface)
                            .withValues(alpha: 0.6),
                      ),
                      onPressed: () => _dismiss(a.id),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                    ),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
