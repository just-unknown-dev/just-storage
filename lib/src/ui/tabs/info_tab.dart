import 'package:flutter/foundation.dart' show internal, kIsWeb;
import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../storage_admin_controller.dart';
import 'entries_tab.dart';

/// How many entries each storage holds, where they are kept and how they
/// are protected, and clearing them.
@internal
class InfoTab extends StatelessWidget {
  /// The tab over [controller].
  const InfoTab({super.key, required this.controller});

  /// What the tab shows.
  final StorageAdminController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final colorScheme = Theme.of(context).colorScheme;
        final standardCount = controller.entries(secure: false).length;
        final secureCount = controller.entries(secure: true).length;
        final standardError = controller.error(secure: false);
        final secureError = controller.error(secure: true);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SectionCard(
              title: 'Statistics',
              children: [
                _StatRow(
                  icon: Icons.storage_outlined,
                  label: 'Standard entries',
                  value: standardError == null ? '$standardCount' : '—',
                  color: colorScheme.secondary,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _StatRow(
                  icon: Icons.lock_outlined,
                  label: 'Secure entries',
                  value: secureError == null ? '$secureCount' : '—',
                  color: colorScheme.tertiary,
                ),
              ],
            ),
            const SizedBox(height: 12),

            _SectionCard(
              title: 'Where the values are kept',
              children: [
                ListTile(
                  leading: Icon(
                    kIsWeb ? Icons.web : Icons.folder_outlined,
                    color: colorScheme.primary,
                  ),
                  title: Text(
                    kIsWeb ? 'Browser storage' : 'Files',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    kIsWeb
                        ? 'localStorage, one item per value:\n'
                              '  just_storage:<key>  (standard)\n'
                              '  just_secure:<key>   (encrypted)\n'
                              'The key: IndexedDB, database just_storage.'
                        : 'In the app\'s support folder, unless another '
                              'was given:\n'
                              '  just_storage.json         (standard)\n'
                              '  just_secure_storage.enc   (encrypted)\n'
                              '  .storage.key              (the key)',
                  ),
                  isThreeLine: true,
                ),
              ],
            ),
            const SizedBox(height: 12),

            _SectionCard(
              title: 'Encryption (secure storage)',
              children: [
                const _FeatureTile(
                  icon: Icons.lock,
                  label: 'Algorithm',
                  detail:
                      'AES-256-GCM: each value encrypted on its own, with a '
                      'random 12-byte nonce, bound to its key',
                ),
                _FeatureTile(
                  icon: Icons.key,
                  label: 'Key',
                  detail: kIsWeb
                      ? 'A non-extractable Web Crypto key in IndexedDB: code '
                            'on the page can use it but not read it. Kept raw '
                            'in localStorage where IndexedDB is unavailable.'
                      : 'A random 256-bit key in .storage.key, beside the '
                            'values; readable only by its owner on desktop '
                            'platforms. Anyone who can read the user\'s files '
                            'can read it too.',
                ),
                const _FeatureTile(
                  icon: Icons.verified_user_outlined,
                  label: 'Integrity',
                  detail:
                      'A 16-byte GCM tag on every value: a value changed, or '
                      'moved to another key, makes the storage throw a '
                      'StorageCorruptException rather than return it',
                ),
                const _FeatureTile(
                  icon: Icons.swap_horiz,
                  label: 'Saving',
                  detail: kIsWeb
                      ? 'Each value is one localStorage item, written in '
                            'order'
                      : 'A temporary file renamed over the old one: a crash '
                            'leaves the old file or the new one, never half',
                ),
              ],
            ),
            const SizedBox(height: 12),

            const _SectionCard(
              title: 'API',
              children: [
                _FeatureTile(
                  icon: Icons.data_object,
                  label: 'Typed JSON helpers',
                  detail:
                      'readJson<T>(key, fromJson)\n'
                      'writeJson<T>(key, value, toJson)',
                ),
                _FeatureTile(
                  icon: Icons.stream,
                  label: 'Watching a key',
                  detail:
                      'watch(key) → Stream<String?>\n'
                      'The current value, then every change',
                ),
                _FeatureTile(
                  icon: Icons.list_alt_outlined,
                  label: 'All at once',
                  detail:
                      'readAll(): a copy of every entry\n'
                      'clear(): removes every entry; recovers a storage that '
                      'can\'t be read',
                ),
              ],
            ),
            const SizedBox(height: 12),

            _SectionCard(
              title: 'Danger zone',
              titleColor: colorScheme.error,
              children: [
                _ClearTile(
                  controller: controller,
                  secure: false,
                  count: standardCount,
                  error: standardError,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _ClearTile(
                  controller: controller,
                  secure: true,
                  count: secureCount,
                  error: secureError,
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

class _ClearTile extends StatelessWidget {
  const _ClearTile({
    required this.controller,
    required this.secure,
    required this.count,
    required this.error,
  });

  final StorageAdminController controller;
  final bool secure;
  final int count;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final unreadable = error is StorageCorruptException;
    final kind = secure ? 'encrypted' : 'plain-text';
    return ListTile(
      leading: Icon(Icons.delete_forever, color: colorScheme.error),
      title: Text(
        'Clear ${secure ? 'secure' : 'standard'} storage',
        style: TextStyle(color: colorScheme.error),
      ),
      subtitle: Text(
        unreadable
            ? 'Can\'t be read: removes what is there and starts over'
            : 'Permanently removes all $count '
                  '$kind entr${count == 1 ? 'y' : 'ies'}',
      ),
      onTap: count > 0 || unreadable ? () => _clear(context, unreadable) : null,
    );
  }

  Future<void> _clear(BuildContext context, bool unreadable) async {
    final confirmed = await confirmClear(
      context,
      count: count,
      secure: secure,
      unreadable: unreadable,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await controller.clearAll(secure: secure);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not clear: $e')));
    }
  }
}

// =============================================================================
// Shared section card
// =============================================================================

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    this.titleColor,
    required this.children,
  });

  final String title;
  final Color? titleColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: titleColor ?? colorScheme.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ),
          ...children,
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

// =============================================================================
// Stat row
// =============================================================================

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 20, color: color),
      title: Text(label),
      trailing: Text(
        value,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

// =============================================================================
// Feature tile
// =============================================================================

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.icon,
    required this.label,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 20),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(detail),
      isThreeLine: detail.contains('\n'),
    );
  }
}
