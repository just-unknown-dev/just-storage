import 'package:flutter/material.dart';

import '../core/core.dart';
import 'storage_admin_controller.dart';
import 'tabs/entries_tab.dart';
import 'tabs/info_tab.dart';

/// A screen for looking at and editing what just_storage keeps, while the
/// app runs. Meant for development: it can show secure values in plain
/// text.
///
/// Three tabs:
///   - **Standard**: the plain values.
///   - **Secure**: the encrypted values, hidden until shown.
///   - **Info**: counts, where the values are kept, and clearing them.
///
/// ```dart
/// Navigator.of(context).push(MaterialPageRoute<void>(
///   builder: (_) => const JustStorageAdminScreen(),
/// ));
/// ```
///
/// Pass the storages your app uses, if they aren't the defaults:
/// ```dart
/// JustStorageAdminScreen(standard: myStorage, secure: mySecure)
/// ```
class JustStorageAdminScreen extends StatefulWidget {
  /// A screen over [standard] and [secure] (default: `JustStorage.standard()`
  /// and `JustStorage.encrypted()`), in [theme] if given.
  const JustStorageAdminScreen({
    super.key,
    this.theme,
    this.standard,
    this.secure,
  });

  /// A theme for the screen, in place of the app's.
  final ThemeData? theme;

  /// The standard storage to show; `JustStorage.standard()` when `null`.
  final JustStandardStorage? standard;

  /// The secure storage to show; `JustStorage.encrypted()` when `null`.
  final JustSecureStorage? secure;

  @override
  State<JustStorageAdminScreen> createState() => _JustStorageAdminScreenState();
}

class _JustStorageAdminScreenState extends State<JustStorageAdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final StorageAdminController _controller;

  static const _tabs = [
    Tab(icon: Icon(Icons.storage_outlined), text: 'Standard'),
    Tab(icon: Icon(Icons.lock_outlined), text: 'Secure'),
    Tab(icon: Icon(Icons.info_outline), text: 'Info'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _controller = StorageAdminController(
      standard: widget.standard,
      secure: widget.secure,
    )..addListener(_changed);
    _controller.refresh();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _controller
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('Just Storage'),
        bottom: TabBar(
          controller: _tabController,
          tabs: _tabs,
          indicatorSize: TabBarIndicatorSize.tab,
        ),
        actions: [
          if (_controller.isLoading)
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
              onPressed: _controller.refresh,
            ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          EntriesTab(controller: _controller, secure: false),
          EntriesTab(controller: _controller, secure: true),
          InfoTab(controller: _controller),
        ],
      ),
    );
    final theme = widget.theme;
    return theme == null ? scaffold : Theme(data: theme, child: scaffold);
  }
}
