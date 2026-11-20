/// Layout and text styles shared by the admin screen.
@internal
library;

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter/material.dart';

/// The breakpoints, spacing and text styles of the admin screen.
@internal
abstract final class AdminStyle {
  /// The width from which the screen shows the sidebar and panes side by
  /// side instead of pages.
  static const double wideBreakpoint = 840;

  /// The width of the workspace (beside the sidebar) from which a value
  /// panel fits next to the entries.
  static const double sidePanelBreakpoint = 900;

  /// The width of the value panel beside the entries.
  static const double sidePanelWidth = 440;

  /// Whether [context] is wide enough for the side-by-side layout: the
  /// screen's own width inside it (see [AdminLayoutScope]), else the
  /// window's (dialogs and pushed pages).
  static bool isWide(BuildContext context) =>
      AdminLayoutScope.maybeWideOf(context) ??
      MediaQuery.sizeOf(context).width >= wideBreakpoint;

  /// Monospace families to try in order (Windows, macOS/iOS, Linux,
  /// Android). The generic `monospace` resolves only on Android and Linux,
  /// so it is not first.
  static const List<String> monoFamilies = [
    'Consolas',
    'Cascadia Mono',
    'Menlo',
    'SF Mono',
    'Roboto Mono',
    'DejaVu Sans Mono',
    'Liberation Mono',
    'Noto Sans Mono',
    'monospace',
    'Courier New',
    'Courier',
  ];

  /// A monospace style for keys and values.
  static TextStyle mono(
    BuildContext context, {
    double fontSize = 13,
    Color? color,
    FontWeight? fontWeight,
    double height = 1.45,
  }) => TextStyle(
    fontFamily: monoFamilies.first,
    fontFamilyFallback: monoFamilies.sublist(1),
    fontSize: fontSize,
    height: height,
    fontWeight: fontWeight,
    color: color ?? Theme.of(context).colorScheme.onSurface,
  );

  /// A small caption in the variant colour.
  static TextStyle caption(BuildContext context) {
    final theme = Theme.of(context);
    return (theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12))
        .copyWith(color: theme.colorScheme.onSurfaceVariant);
  }

  /// A section heading.
  static TextStyle heading(BuildContext context) {
    final theme = Theme.of(context);
    return (theme.textTheme.titleSmall ?? const TextStyle(fontSize: 14))
        .copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface,
        );
  }

  /// A small upper-case label over a group, as in the sidebar.
  static TextStyle overline(BuildContext context) => caption(
    context,
  ).copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.8);
}

/// Tells the admin screen under it whether it is laid out wide (from the
/// screen's own constraints, which may be narrower than the window when the
/// screen is embedded).
@internal
class AdminLayoutScope extends InheritedWidget {
  /// A scope saying whether the screen is [wide].
  const AdminLayoutScope({super.key, required this.wide, required super.child});

  /// Whether the screen is laid out wide.
  final bool wide;

  /// The nearest scope's answer, or null outside one.
  static bool? maybeWideOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdminLayoutScope>()?.wide;

  @override
  bool updateShouldNotify(AdminLayoutScope oldWidget) => wide != oldWidget.wide;
}
