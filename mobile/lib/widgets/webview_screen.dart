// Écran WebView réutilisable — affiche une URL dans une WebView in-app.
// Utilisé pour les rapports PDF mensuels (endpoint /exports/monthly/:year/:month)
// et le checkout FedaPay si besoin.
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme/theme.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({
    super.key,
    required this.url,
    this.title,
    this.allowedActions = const [WebViewAction.openExternal, WebViewAction.reload],
  });

  final String url;
  final String? title;
  final List<WebViewAction> allowedActions;

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

enum WebViewAction { openExternal, reload, share }

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  String? _error;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF8F6F1))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            setState(() => _progress = p);
          },
          onPageStarted: (_) {
            setState(() {
              _loading = true;
              _error = null;
            });
          },
          onPageFinished: (_) {
            setState(() => _loading = false);
          },
          onWebResourceError: (e) {
            setState(() {
              _loading = false;
              _error = e.description;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'Chargement...'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (widget.allowedActions.contains(WebViewAction.reload))
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _controller.reload(),
              tooltip: 'Recharger',
            ),
        ],
        bottom: _loading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress / 100 : null,
                  backgroundColor: LifeHelmColors.textTertiary.withValues(alpha: 0.2),
                  color: LifeHelmColors.primary,
                  minHeight: 3,
                ),
              )
            : null,
      ),
      body: _error != null
          ? _ErrorView(
              error: _error!,
              onRetry: () {
                setState(() => _error = null);
                _controller.reload();
              },
            )
          : WebViewWidget(controller: _controller),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: LifeHelmColors.textTertiary),
            const SizedBox(height: 16),
            const Text(
              'Impossible de charger la page',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: LifeHelmColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
