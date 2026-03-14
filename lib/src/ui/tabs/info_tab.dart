import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../storage_provider.dart';

/// Displays storage statistics, backend information, API feature overview, and
/// a danger-zone section for clearing data.
class InfoTab extends StatelessWidget {
  final StorageProvider provider;
  const InfoTab({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        final stdCount = provider.standardEntries.length;
        final secCount = provider.secureEntries.length;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ----------------------------------------------------------------
            // Statistics
            // ----------------------------------------------------------------
            _SectionCard(
              title: 'Statistics',
              children: [
                _StatRow(
                  icon: Icons.storage_outlined,
                  label: 'Standard entries',
                  value: stdCount.toString(),
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _StatRow(
                  icon: Icons.lock_outlined,
                  label: 'Secure entries',
                  value: secCount.toString(),
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ----------------------------------------------------------------
            // Backend
            // ----------------------------------------------------------------
            _SectionCard(
              title: 'Storage Backend',
              children: [
                ListTile(
                  leading: Icon(
                    kIsWeb ? Icons.web : Icons.folder_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(
                    kIsWeb ? 'Browser localStorage' : 'File System',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    kIsWeb
                        ? 'Data persists in window.localStorage under '
                            'prefixed keys:\n'
                            '  just_storage:<key>  (standard)\n'
                            '  just_secure:<key>   (encrypted)'
                        : 'JSON files in the Application Support Directory:\n'
                            '  just_storage.json          (standard)\n'
                            '  just_secure_storage.enc    (encrypted)',
                  ),
                  isThreeLine: true,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ----------------------------------------------------------------
            // Encryption
            // ----------------------------------------------------------------
            _SectionCard(
              title: 'Encryption (Secure Storage)',
              children: [
                _FeatureTile(
                  icon: Icons.lock,
                  label: 'Algorithm',
                  detail: 'AES-256-GCM authenticated encryption',
                ),
                _FeatureTile(
                  icon: Icons.key,
                  label: 'Key management',
                  detail: kIsWeb
                      ? 'Master key auto-generated and stored in localStorage '
                          '(base64-encoded 256-bit key)'
                      : 'Master key stored in .storage.key '
                          '(owner-read-only 0600 on POSIX)',
                ),
                const _FeatureTile(
                  icon: Icons.shuffle,
                  label: 'Nonces',
                  detail: 'Fresh random 12-byte nonce per write — '
                      'each entry is independently encrypted, '
                      'nonce reuse never compromises other keys',
                ),
                const _FeatureTile(
                  icon: Icons.verified_user_outlined,
                  label: 'Integrity',
                  detail: '128-bit GCM authentication tag per entry — '
                      'any tampering raises a StorageException '
                      'before plaintext is returned',
                ),
                const _FeatureTile(
                  icon: Icons.swap_horiz,
                  label: 'Atomic writes',
                  detail: 'Write to .tmp file → rename over target — '
                      'no partial writes, no data loss on crash',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ----------------------------------------------------------------
            // API features
            // ----------------------------------------------------------------
            _SectionCard(
              title: 'API Features',
              children: const [
                _FeatureTile(
                  icon: Icons.data_object,
                  label: 'Typed JSON helpers',
                  detail: 'readJson<T>(key, fromJson)\n'
                      'writeJson<T>(key, value, toJson)\n'
                      'Serialize / deserialize domain objects directly',
                ),
                _FeatureTile(
                  icon: Icons.stream,
                  label: 'Reactive streams',
                  detail: 'watch(key) → Stream<String?>\n'
                      'Emits the current value on subscribe, then on every '
                      'subsequent write or delete',
                ),
                _FeatureTile(
                  icon: Icons.list_alt_outlined,
                  label: 'Bulk operations',
                  detail:
                      'readAll() — snapshot of all entries as Map<String,String>\n'
                      'clear()   — removes every entry atomically',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ----------------------------------------------------------------
            // Danger zone
            // ----------------------------------------------------------------
            _SectionCard(
              title: 'Danger Zone',
              titleColor: Theme.of(context).colorScheme.error,
              children: [
                ListTile(
                  leading: Icon(
                    Icons.delete_forever,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    'Clear Standard Storage',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  subtitle: Text(
                    'Permanently removes all $stdCount '
                    'plain-text entr${stdCount == 1 ? 'y' : 'ies'}',
                  ),
                  onTap: stdCount > 0
                      ? () => _confirmClear(context, isSecure: false)
                      : null,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: Icon(
                    Icons.delete_forever,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    'Clear Secure Storage',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  subtitle: Text(
                    'Permanently removes all $secCount '
                    'encrypted entr${secCount == 1 ? 'y' : 'ies'}',
                  ),
                  onTap: secCount > 0
                      ? () => _confirmClear(context, isSecure: true)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Future<void> _confirmClear(
    BuildContext context, {
    required bool isSecure,
  }) async {
    final count = isSecure
        ? provider.secureEntries.length
        : provider.standardEntries.length;
    final label = isSecure ? 'secure' : 'standard';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Clear ${isSecure ? 'Secure' : 'Standard'} Storage'),
        content: Text(
          'This will permanently remove all $count '
          'entr${count == 1 ? 'y' : 'ies'} from $label storage.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await provider.clearAll(isSecure: isSecure);
  }
}

// =============================================================================
// Shared section card
// =============================================================================

class _SectionCard extends StatelessWidget {
  final String title;
  final Color? titleColor;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    this.titleColor,
    required this.children,
  });

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
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

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
  final IconData icon;
  final String label;
  final String detail;

  const _FeatureTile({
    required this.icon,
    required this.label,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 20),
      title: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(detail),
      isThreeLine: detail.contains('\n'),
    );
  }
}
