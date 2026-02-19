import 'dart:ui';
import 'package:foxcloud/common/common.dart';
import 'package:foxcloud/state.dart';
import 'package:foxcloud/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

class PublicIP extends ConsumerStatefulWidget {
  const PublicIP({super.key});

  @override
  ConsumerState<PublicIP> createState() => _PublicIPState();
}

class _PublicIPState extends ConsumerState<PublicIP> {
  String? _ip;
  bool _isBlurred = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchIP();
  }

  Future<void> _fetchIP() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.ipify.org'),
      ).timeout(const Duration(seconds: 5));
      if (mounted && response.statusCode == 200) {
        setState(() {
          _ip = response.body.trim();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _ip = null;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: getWidgetHeight(1),
      child: CommonCard(
        info: Info(
          label: 'IP',
          iconData: Icons.language,
        ),
        onPressed: () {
          setState(() => _isBlurred = !_isBlurred);
        },
        child: Container(
          padding: baseInfoEdgeInsets.copyWith(top: 0),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SizedBox(
                height: globalState.measure.bodyMediumHeight + 2,
                child: _loading
                    ? Container(
                        padding: const EdgeInsets.all(2),
                        child: const AspectRatio(
                          aspectRatio: 1,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : GestureDetector(
                        onTap: () {
                          setState(() => _isBlurred = !_isBlurred);
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: ImageFiltered(
                                imageFilter: _isBlurred
                                    ? ImageFilter.blur(sigmaX: 6, sigmaY: 6)
                                    : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                                child: Text(
                                  _ip ?? '—',
                                  style: context.textTheme.bodyMedium
                                      ?.toLight
                                      .adjustSize(1),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              _isBlurred
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              size: 14,
                              color: cs.onSurface.withValues(alpha: 0.5),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
