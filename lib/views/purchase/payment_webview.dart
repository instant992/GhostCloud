import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// In-app WebView for YooKassa payment page.
///
/// Shows the payment URL inside the app and pops when the user
/// finishes (or presses back). The caller continues polling independently.
class PaymentWebView extends StatefulWidget {
  final String url;

  const PaymentWebView({super.key, required this.url});

  /// Opens the payment URL in an in-app WebView.
  /// Returns `true` if the user interacted with the page, `null` on back.
  static Future<bool?> show(BuildContext context, String url) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PaymentWebView(url: url)),
    );
  }

  @override
  State<PaymentWebView> createState() => _PaymentWebViewState();
}

class _PaymentWebViewState extends State<PaymentWebView> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String _currentTitle = 'Оплата';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) async {
            if (!mounted) return;
            final title = await _controller.getTitle();
            setState(() {
              _isLoading = false;
              if (title != null && title.isNotEmpty) {
                _currentTitle = title;
              }
            });
          },
          onNavigationRequest: (request) {
            final url = request.url;
            // Handle custom URL schemes (sberpay://, tinkoff://, etc.)
            // by launching them externally to open the bank app
            if (!url.startsWith('http://') && !url.startsWith('https://')) {
              launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalApplication,
              );
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(true),
        ),
        bottom: _isLoading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
