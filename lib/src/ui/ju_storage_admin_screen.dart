import 'package:flutter/material.dart';

import '../just_secure_storage.dart';
import '../just_standard_storage.dart';
import 'storage_provider.dart';
import 'tabs/entries_tab.dart';
import 'tabs/info_tab.dart';

/// Full-screen admin UI for inspecting and editing just_storage data.
///
/// Provides three tabs:
///   - **Standard** — plain-text key-value entries
///   - **Secure**   — AES-256-GCM encrypted entries
///   - **Info**     — statistics, backend info, and danger zone
///
/// Usage:
/// ```dart
/// Navigator.of(context).push(MaterialPageRoute(
///   builder: (_) => const JUStorageAdminScreen(),
/// ));
/// ```
///
/// Pass your own storage instances to inspect specific directories:
/// ```dart
/// JUStorageAdminScreen(standard: myStorage, secure: mySecure)
/// ```
///
/// Optionally supply a custom [theme] to override the app's theme:
/// ```dart
/// JUStorageAdminScreen(theme: ThemeData(colorSchemeSeed: Colors.teal))
/// ```
class JUStorageAdminScreen extends StatefulWidget {
  /// Optional custom theme applied around the admin screen.
  final ThemeData? theme;

  /// An existing standard storage instance to inspect.
  /// When null, [JUStorageAdminScreen] creates its own via `JustStorage.standard()`.
  final JustStandardStorage? standard;

  /// An existing secure storage instance to inspect.
  /// When null, [JUStorageAdminScreen] creates its own via `JustStorage.encrypted()`.
  final JustSecureStorage? secure;

  const JUStorageAdminScreen({
    super.key,
    this.theme,
    this.standard,
    this.secure,
  });

  @override
  State<JUStorageAdminScreen> createState() => _JUStorageAdminScreenState();
}

class _JUStorageAdminScreenState extends State<JUStorageAdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final StorageProvider _provider;

  static const _tabs = [
    Tab(icon: Icon(Icons.storage_outlined), text: 'Standard'),
    Tab(icon: Icon(Icons.lock_outlined), text: 'Secure'),
    Tab(icon: Icon(Icons.info_outline), text: 'Info'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _provider = StorageProvider(
      standard: widget.standard,
      secure: widget.secure,
    );
    _provider.addListener(_onProviderChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _provider.init());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _provider.removeListener(_onProviderChange);
    _provider.dispose();
    super.dispose();
  }

  void _onProviderChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_outlined, size: 18),
        ),
        title: const Text('Just Storage'),
        bottom: TabBar(
          controller: _tabController,
          tabs: _tabs,
          indicatorSize: TabBarIndicatorSize.tab,
        ),
        actions: [
          if (_provider.isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _provider.refresh,
            ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          EntriesTab(provider: _provider, isSecure: false),
          EntriesTab(provider: _provider, isSecure: true),
          InfoTab(provider: _provider),
        ],
      ),
    );

    return widget.theme != null
        ? Theme(data: widget.theme!, child: scaffold)
        : scaffold;
  }
}
