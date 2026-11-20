import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'admin_style.dart';
import 'shell/compact_pages.dart';
import 'shell/store_sidebar.dart';
import 'shell/store_workspace.dart';
import 'storage_admin_controller.dart';
import 'widgets/admin_widgets.dart';

/// A workbench for what just_storage keeps, while the app runs: every
/// storage it is given, their entries, searched and sorted, each value as
/// text, formatted JSON or a tree, edited in place; adding, renaming,
/// duplicating and deleting entries, one or many; export and import as
/// JSON; where each storage keeps its values; clearing and wiping.
///
/// On a wide screen (840 logical pixels or more) it shows a sidebar of
/// storages beside the selected one's entries, with the selected value in a
/// panel beside them when there is room. On a phone the same pieces are
/// pages you drill into. It follows each storage's changes, so what the app
/// writes while it is open shows up at once, marked for a moment.
///
/// ```dart
/// Navigator.of(context).push(MaterialPageRoute<void>(
///   builder: (_) => const JustStorageAdminScreen(),
/// ));
/// ```
///
/// It shows `JustStorage.standard()` and `JustStorage.encrypted()` unless
/// given [stores]:
///
/// ```dart
/// JustStorageAdminScreen(stores: [
///   StorageAdminStore.standard(),
///   StorageAdminStore.secure(),
///   StorageAdminStore('Game saves', savesStorage),
/// ])
/// ```
///
/// Secure values are hidden until shown, but the screen can show them and
/// export them decrypted: keep it out of release builds, or pass
/// `readOnly: true` for a screen that can't change anything.
class JustStorageAdminScreen extends StatefulWidget {
  /// The screen over [stores], or over [controller].
  const JustStorageAdminScreen({
    super.key,
    this.controller,
    this.stores,
    this.readOnly = false,
    this.theme,
    this.title = 'Just Storage',
  });

  /// The state to show. When null the screen makes its own, over [stores]
  /// and with [readOnly], and disposes it when it goes away.
  final StorageAdminController? controller;

  /// The storages to show, when the screen makes its own controller: the
  /// app's standard and secure storages when null.
  final List<StorageAdminStore>? stores;

  /// Whether the screen's own controller is read-only (a given
  /// [controller] has its own setting).
  final bool readOnly;

  /// A theme for the screen and the pages and dialogs it opens; the app's
  /// theme when null.
  final ThemeData? theme;

  /// The app bar's title.
  final String title;

  @override
  State<JustStorageAdminScreen> createState() => _JustStorageAdminScreenState();
}

class _JustStorageAdminScreenState extends State<JustStorageAdminScreen> {
  late StorageAdminController _controller;
  late bool _ownsController;
  double _sidebarWidth = 260;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    final given = widget.controller;
    _ownsController = given == null;
    _controller =
        given ??
        StorageAdminController(
          stores: widget.stores,
          readOnly: widget.readOnly,
        );
    unawaited(_controller.refresh());
  }

  @override
  void didUpdateWidget(JustStorageAdminScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final rebuild =
        widget.controller == null &&
        (oldWidget.readOnly != widget.readOnly ||
            !_sameStores(oldWidget.stores, widget.stores));
    if (oldWidget.controller != widget.controller || rebuild) {
      if (_ownsController) _controller.dispose();
      _attach();
    }
  }

  static bool _sameStores(
    List<StorageAdminStore>? a,
    List<StorageAdminStore>? b,
  ) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  List<Widget> _actions() => [
    if (_controller.isBusy)
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14),
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
        key: const ValueKey('jst-refresh'),
        icon: const Icon(Icons.refresh),
        tooltip: 'Read every storage again (F5)',
        onPressed: _controller.refresh,
      ),
  ];

  Widget _title(BuildContext context) => Row(
    children: [
      Flexible(child: Text(widget.title, overflow: TextOverflow.ellipsis)),
      if (_controller.readOnly) ...[
        const SizedBox(width: 10),
        AdminTag.readOnly(context),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final screen = LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= AdminStyle.wideBreakpoint;
        return AdminLayoutScope(
          wide: wide,
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.f5): () =>
                    unawaited(_controller.refresh()),
              },
              child: wide
                  ? _wide(context, constraints.maxWidth)
                  : _compact(context),
            ),
          ),
        );
      },
    );
    final theme = widget.theme;
    return theme == null ? screen : Theme(data: theme, child: screen);
  }

  Widget _wide(BuildContext context, double width) {
    final sidebar = _sidebarWidth.clamp(200.0, width * 0.4);
    return Scaffold(
      appBar: AppBar(title: _title(context), actions: _actions()),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: sidebar,
            child: StoreSidebar(controller: _controller),
          ),
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) => setState(() {
                _sidebarWidth = (sidebar + d.delta.dx).clamp(
                  200.0,
                  width * 0.4,
                );
              }),
              child: const VerticalDivider(width: 6, thickness: 1),
            ),
          ),
          Expanded(child: StoreWorkspace(controller: _controller)),
        ],
      ),
    );
  }

  Widget _compact(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: _title(context), actions: _actions()),
      body: SafeArea(child: CompactStoreList(controller: _controller)),
    );
  }
}
