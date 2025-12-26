import 'dart:io';
import 'package:flutter/material.dart';

// Platform-specific imports
import 'package:webview_flutter/webview_flutter.dart' as mobile_webview;
import 'package:webview_windows/webview_windows.dart' as windows_webview;
import 'package:url_launcher/url_launcher.dart';

class PlatformWebView extends StatefulWidget {
  final String url;
  final String title;

  const PlatformWebView({
    super.key,
    required this.url,
    this.title = 'WebView',
  });

  @override
  State<PlatformWebView> createState() => _PlatformWebViewState();
}

class _PlatformWebViewState extends State<PlatformWebView> {
  late mobile_webview.WebViewController? _mobileController;
  windows_webview.WebviewController? _windowsController;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  Future<void> _initializeWebView() async {
    try {
      if (Platform.isWindows) {
        await _initializeWindowsWebView();
      } else {
        _initializeMobileWebView();
      }
    } catch (e) {
      debugPrint('Error initializing WebView: $e');
      setState(() {
        _error = 'فشل في تهيئة WebView: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _initializeWindowsWebView() async {
    try {
      debugPrint('Initializing Windows WebView...');
      _windowsController = windows_webview.WebviewController();

      await _windowsController!.initialize();
      debugPrint('Windows WebView initialized successfully');

      await _windowsController!.loadUrl(widget.url);
      debugPrint('Windows WebView loaded URL: ${widget.url}');

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Windows WebView initialization failed: $e');
      setState(() {
        _error = 'فشل في تشغيل WebView على Windows: $e';
        _isLoading = false;
      });
    }
  }

  void _initializeMobileWebView() {
    try {
      debugPrint('Initializing Mobile WebView...');
      _mobileController = mobile_webview.WebViewController()
        ..setJavaScriptMode(mobile_webview.JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          mobile_webview.NavigationDelegate(
            onProgress: (int progress) {
              debugPrint('WebView loading progress: $progress%');
            },
            onPageStarted: (String url) {
              debugPrint('WebView started loading: $url');
              setState(() {
                _isLoading = true;
              });
            },
            onPageFinished: (String url) {
              debugPrint('WebView finished loading: $url');
              setState(() {
                _isLoading = false;
              });
            },
            onWebResourceError: (mobile_webview.WebResourceError error) {
              debugPrint('WebView resource error: ${error.description}');
              setState(() {
                _error = 'خطأ في تحميل الصفحة: ${error.description}';
                _isLoading = false;
              });
            },
          ),
        )
        ..loadRequest(Uri.parse(widget.url));

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Mobile WebView initialization failed: $e');
      setState(() {
        _error = 'فشل في تشغيل WebView: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _openInExternalBrowser() async {
    try {
      final uri = Uri.parse(widget.url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch ${widget.url}';
      }
    } catch (e) {
      debugPrint('Failed to open external browser: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل في فتح المتصفح الخارجي: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows && _windowsController != null) {
      _windowsController!.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: 'فتح في متصفح خارجي',
            onPressed: _openInExternalBrowser,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'إعادة تحميل',
            onPressed: () {
              if (Platform.isWindows && _windowsController != null) {
                _windowsController!.reload();
              } else if (_mobileController != null) {
                _mobileController!.reload();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoading) const LinearProgressIndicator(),
          Expanded(
            child: _buildWebViewContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildWebViewContent() {
    if (_error != null) {
      return _buildErrorWidget();
    }

    if (Platform.isWindows) {
      return _buildWindowsWebView();
    } else {
      return _buildMobileWebView();
    }
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(fontSize: 16, color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _openInExternalBrowser,
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('فتح في متصفح خارجي'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _isLoading = true;
                    });
                    _initializeWebView();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ExpansionTile(
              title: const Text('معلومات التشخيص'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('المنصة: ${Platform.operatingSystem}'),
                      Text('الرابط: ${widget.url}'),
                      if (_error != null) Text('الخطأ: $_error'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWindowsWebView() {
    if (_windowsController == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return windows_webview.Webview(_windowsController!);
  }

  Widget _buildMobileWebView() {
    if (_mobileController == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return mobile_webview.WebViewWidget(controller: _mobileController!);
  }
}
