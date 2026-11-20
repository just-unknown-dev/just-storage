/// Small widgets and helpers shared by the admin screen.
@internal
library;

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../admin_style.dart';
import '../admin_utils.dart';

/// Pushes [page] with the theme in effect at [context], so pages pushed
/// from a themed admin screen keep its theme.
@internal
Future<T?> pushAdminPage<T>(BuildContext context, Widget page) {
  final navigator = Navigator.of(context);
  final themed = InheritedTheme.captureAll(
    context,
    page,
    to: navigator.context,
  );
  return navigator.push<T>(MaterialPageRoute<T>(builder: (_) => themed));
}

/// Shows [message] as an error SnackBar on the nearest messenger.
@internal
void showAdminError(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final cs = Theme.of(context).colorScheme;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: cs.errorContainer,
        content: Text(message, style: TextStyle(color: cs.onErrorContainer)),
        showCloseIcon: true,
        closeIconColor: cs.onErrorContainer,
        duration: const Duration(seconds: 6),
      ),
    );
}

/// Shows [message] as a SnackBar on the nearest messenger.
@internal
void showAdminMessage(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
}

/// Runs [action]; shows [success] when it works, else what went wrong
/// (prefixed with [failure]). Returns whether it worked.
@internal
Future<bool> runReported(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
  required String failure,
}) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) {
      showAdminError(context, '$failure: ${describeError(e)}');
    }
    return false;
  }
  if (success != null && context.mounted) showAdminMessage(context, success);
  return true;
}

/// Copies [text] and says so.
@internal
Future<void> copyText(BuildContext context, String text, {String? what}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showAdminMessage(context, '${what ?? 'Text'} copied.');
}

/// Asks to confirm an action. With [typeToConfirm] the user must type that
/// text first. Returns whether they confirmed.
@internal
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  bool destructive = true,
  String? typeToConfirm,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      destructive: destructive,
      typeToConfirm: typeToConfirm,
    ),
  );
  return result == true;
}

class _ConfirmDialog extends StatefulWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.destructive,
    required this.typeToConfirm,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final bool destructive;
  final String? typeToConfirm;

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  bool get _canConfirm =>
      widget.typeToConfirm == null || _typed.text == widget.typeToConfirm;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final must = widget.typeToConfirm;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.message),
            if (must != null) ...[
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('jst-confirm-text'),
                controller: _typed,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (_canConfirm) Navigator.pop(context, true);
                },
                decoration: InputDecoration(
                  labelText: 'Type $must to confirm',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('jst-confirm'),
          style: widget.destructive
              ? FilledButton.styleFrom(
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                )
              : null,
          onPressed: _canConfirm ? () => Navigator.pop(context, true) : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Asks for one line of text; [validate] returns why it can't be used.
/// Returns the text, or null when cancelled.
@internal
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  String? helper,
  String confirmLabel = 'OK',
  String? Function(String text)? validate,
  bool monospace = false,
}) => showDialog<String>(
  context: context,
  builder: (_) => _PromptDialog(
    title: title,
    label: label,
    initial: initial,
    helper: helper,
    confirmLabel: confirmLabel,
    validate: validate,
    monospace: monospace,
  ),
);

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.helper,
    required this.confirmLabel,
    required this.validate,
    required this.monospace,
  });

  final String title;
  final String label;
  final String initial;
  final String? helper;
  final String confirmLabel;
  final String? Function(String text)? validate;
  final bool monospace;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _text =
      TextEditingController(text: widget.initial)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initial.length,
        );
  bool _showError = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String? get _error => widget.validate?.call(_text.text);

  void _submit() {
    if (_error != null) {
      setState(() => _showError = true);
      return;
    }
    Navigator.pop(context, _text.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: TextField(
          key: const ValueKey('jst-prompt'),
          controller: _text,
          autofocus: true,
          style: widget.monospace
              ? AdminStyle.mono(context, fontSize: 14)
              : null,
          onChanged: (_) {
            if (_showError) setState(() {});
          },
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: widget.label,
            helperText: widget.helper,
            helperMaxLines: 3,
            errorText: _showError ? _error : null,
            errorMaxLines: 3,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('jst-prompt-ok'),
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// A dialog that is an [AlertDialog]-sized card on wide screens and a
/// full-screen page on phones. With [fill], its [child] gets a fixed
/// height on wide screens, so it can expand.
@internal
class AdminDialog extends StatelessWidget {
  /// A dialog titled [title] around [child].
  const AdminDialog({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.width = 560,
    this.fill = false,
  });

  /// The title.
  final String title;

  /// The content.
  final Widget child;

  /// The buttons along the bottom.
  final List<Widget> actions;

  /// The width on wide screens.
  final double width;

  /// Whether [child] fills a fixed height on wide screens.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    if (AdminStyle.isWide(context)) {
      final height = MediaQuery.sizeOf(context).height;
      return AlertDialog(
        title: Text(title),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        content: SizedBox(
          width: width,
          height: fill ? (height * 0.72).clamp(260.0, 640.0) : null,
          child: child,
        ),
        actions: actions,
      );
    }
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(title),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: child,
          ),
        ),
        bottomNavigationBar: actions.isEmpty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: actions,
                  ),
                ),
              ),
      ),
    );
  }
}

/// A centred icon, title, message and optional action.
@internal
class EmptyState extends StatelessWidget {
  /// An empty state with [icon] and [title].
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  /// The icon.
  final IconData icon;

  /// What is empty.
  final String title;

  /// More about it.
  final String? message;

  /// What to do about it.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: text.titleMedium?.copyWith(color: cs.onSurface),
            ),
            if (message != null) ...[
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// The tone of a [MessageBanner].
@internal
enum BannerTone {
  /// Something to know.
  info,

  /// Something to be careful about.
  warning,

  /// Something that went wrong.
  error,
}

/// An inline message with an icon and optional actions.
@internal
class MessageBanner extends StatelessWidget {
  /// A banner saying [message] in [tone].
  const MessageBanner({
    super.key,
    required this.message,
    this.tone = BannerTone.info,
    this.actions = const [],
    this.margin = EdgeInsets.zero,
  });

  /// What it says.
  final String message;

  /// How it looks.
  final BannerTone tone;

  /// Buttons at its end.
  final List<Widget> actions;

  /// Space around it.
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (Color bg, Color fg, IconData icon) = switch (tone) {
      BannerTone.info => (
        cs.secondaryContainer,
        cs.onSecondaryContainer,
        Icons.info_outline,
      ),
      BannerTone.warning => (
        cs.tertiaryContainer,
        cs.onTertiaryContainer,
        Icons.warning_amber_rounded,
      ),
      BannerTone.error => (
        cs.errorContainer,
        cs.onErrorContainer,
        Icons.error_outline,
      ),
    };
    final text = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 18, color: fg),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(
            message,
            style: TextStyle(fontSize: 13, color: fg),
          ),
        ),
      ],
    );
    return Container(
      margin: margin,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: actions.isEmpty
          ? text
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                text,
                const SizedBox(height: 4),
                TextButtonTheme(
                  data: TextButtonThemeData(
                    style: TextButton.styleFrom(foregroundColor: fg),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 4,
                    children: actions,
                  ),
                ),
              ],
            ),
    );
  }
}

/// A small rounded label.
@internal
class AdminTag extends StatelessWidget {
  /// A tag saying [label] in the given colours.
  const AdminTag({
    super.key,
    required this.label,
    this.icon,
    required this.background,
    required this.foreground,
    this.tooltip,
  });

  /// The read-only tag.
  factory AdminTag.readOnly(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AdminTag(
      label: 'Read-only',
      icon: Icons.visibility_outlined,
      background: cs.tertiaryContainer,
      foreground: cs.onTertiaryContainer,
      tooltip: 'Nothing can be changed from this screen',
    );
  }

  /// A tag for a secure (encrypted) storage.
  factory AdminTag.secure(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AdminTag(
      label: 'Encrypted',
      icon: Icons.lock_outline,
      background: cs.tertiaryContainer,
      foreground: cs.onTertiaryContainer,
    );
  }

  /// A tag for a standard (plain) storage.
  factory AdminTag.plain(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AdminTag(
      label: 'Plain',
      icon: Icons.lock_open_outlined,
      background: cs.secondaryContainer,
      foreground: cs.onSecondaryContainer,
    );
  }

  /// A warning tag.
  factory AdminTag.warning(BuildContext context, String label) {
    final cs = Theme.of(context).colorScheme;
    return AdminTag(
      label: label,
      icon: Icons.warning_amber_rounded,
      background: cs.errorContainer,
      foreground: cs.onErrorContainer,
    );
  }

  /// A neutral tag.
  factory AdminTag.neutral(
    BuildContext context,
    String label, {
    IconData? icon,
    String? tooltip,
  }) {
    final cs = Theme.of(context).colorScheme;
    return AdminTag(
      label: label,
      icon: icon,
      background: cs.surfaceContainerHighest,
      foreground: cs.onSurfaceVariant,
      tooltip: tooltip,
    );
  }

  /// What it says.
  final String label;

  /// An icon before [label].
  final IconData? icon;

  /// Its fill.
  final Color background;

  /// Its text and icon colour.
  final Color foreground;

  /// What it means, on hover.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final tag = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
    return tooltip == null ? tag : Tooltip(message: tooltip, child: tag);
  }
}

/// A badge naming a value's [kind], in theme colours.
@internal
class KindBadge extends StatelessWidget {
  /// A badge for [kind].
  const KindBadge({super.key, required this.kind});

  /// The kind it names.
  final ValueKind kind;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (kind) {
      ValueKind.object ||
      ValueKind.array => (cs.primaryContainer, cs.onPrimaryContainer),
      ValueKind.number ||
      ValueKind.boolean => (cs.secondaryContainer, cs.onSecondaryContainer),
      ValueKind.text ||
      ValueKind.empty => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
    };
    return Tooltip(
      message: kind.label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          kind.tag,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: fg,
          ),
        ),
      ),
    );
  }
}

/// A dot marking an entry that changed a moment ago.
@internal
class RecentDot extends StatelessWidget {
  /// The dot.
  const RecentDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Changed just now',
      child: Container(
        key: const ValueKey('jst-recent'),
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// A titled card that groups related details.
@internal
class SectionCard extends StatelessWidget {
  /// A card titled [title] holding [children].
  const SectionCard({
    super.key,
    required this.title,
    required this.children,
    this.titleColor,
    this.trailing,
  });

  /// The heading.
  final String title;

  /// What it holds.
  final List<Widget> children;

  /// The heading's colour; the primary colour by default.
  final Color? titleColor;

  /// A widget at the end of the heading.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 10, trailing == null ? 16 : 4, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: AdminStyle.heading(
                      context,
                    ).copyWith(color: titleColor ?? cs.primary),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }
}

/// A stat: a value over a label, in a small tile.
@internal
class StatTile extends StatelessWidget {
  /// A tile showing [value] over [label].
  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.tooltip,
  });

  /// The icon.
  final IconData icon;

  /// What the value is.
  final String label;

  /// The value.
  final String value;

  /// More about it, on hover.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tile = Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                Text(label, style: AdminStyle.caption(context)),
              ],
            ),
          ),
        ],
      ),
    );
    return tooltip == null ? tile : Tooltip(message: tooltip, child: tile);
  }
}

/// A menu entry with an icon, for popup menus.
@internal
PopupMenuItem<T> menuItem<T>(
  BuildContext context,
  T value,
  IconData icon,
  String label, {
  bool destructive = false,
  bool enabled = true,
  Key? key,
}) {
  final cs = Theme.of(context).colorScheme;
  final color = destructive ? cs.error : null;
  return PopupMenuItem<T>(
    key: key,
    value: value,
    enabled: enabled,
    child: Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Flexible(
          child: Text(label, style: TextStyle(color: color)),
        ),
      ],
    ),
  );
}

/// Shows [items] as a menu at [position] (global) and returns the choice.
@internal
Future<T?> showMenuAt<T>(
  BuildContext context,
  Offset position,
  List<PopupMenuEntry<T>> items,
) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final local = overlay.globalToLocal(position);
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(
      local & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: items,
  );
}
