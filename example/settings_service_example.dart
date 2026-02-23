/// Recipe: Building a settings service on top of [JustStandardStorage].
///
/// This pattern is recommended over accessing the storage directly from UI
/// code.  The service encapsulates key names, default values, and
/// serialisation, exposing a clean typed API to the rest of the app.
library;

import 'dart:convert';

import 'package:just_storage/just_storage.dart';

// ---------------------------------------------------------------------------
// Domain model
// ---------------------------------------------------------------------------

enum ChessTheme { light, dark, system }

enum BoardStyle { classic, walnut, marble, tournament }

class AppSettings {
  const AppSettings({
    this.theme = ChessTheme.system,
    this.boardStyle = BoardStyle.classic,
    this.soundEnabled = true,
    this.moveAnimationMs = 200,
    this.showCoordinates = true,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        theme: ChessTheme.values.byName(json['theme'] as String? ?? 'system'),
        boardStyle: BoardStyle.values
            .byName(json['boardStyle'] as String? ?? 'classic'),
        soundEnabled: json['soundEnabled'] as bool? ?? true,
        moveAnimationMs: json['moveAnimationMs'] as int? ?? 200,
        showCoordinates: json['showCoordinates'] as bool? ?? true,
      );

  static const AppSettings defaults = AppSettings();

  final ChessTheme theme;
  final BoardStyle boardStyle;
  final bool soundEnabled;
  final int moveAnimationMs;
  final bool showCoordinates;

  Map<String, dynamic> toJson() => {
        'theme': theme.name,
        'boardStyle': boardStyle.name,
        'soundEnabled': soundEnabled,
        'moveAnimationMs': moveAnimationMs,
        'showCoordinates': showCoordinates,
      };

  AppSettings copyWith({
    ChessTheme? theme,
    BoardStyle? boardStyle,
    bool? soundEnabled,
    int? moveAnimationMs,
    bool? showCoordinates,
  }) =>
      AppSettings(
        theme: theme ?? this.theme,
        boardStyle: boardStyle ?? this.boardStyle,
        soundEnabled: soundEnabled ?? this.soundEnabled,
        moveAnimationMs: moveAnimationMs ?? this.moveAnimationMs,
        showCoordinates: showCoordinates ?? this.showCoordinates,
      );
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Manages application settings above [JustStandardStorage].
///
/// Key design choices:
/// - Constructor receives the abstract interface — trivially testable.
/// - One JSON key for the whole settings object, not one key per field.
///   This means a single read/write per settings change instead of N.
/// - [watchSettings] re-emits on every write so the UI can rebuild reactively
///   without manually calling [load].
class SettingsService {
  SettingsService(this._storage);

  final JustStandardStorage _storage;

  static const _key = 'app_settings';

  // --------------------------------------------------------------------------
  // Read
  // --------------------------------------------------------------------------

  /// Returns the saved settings, or [AppSettings.defaults] when no settings
  /// have been saved yet.
  Future<AppSettings> load() async {
    try {
      return await _storage.readJson(_key, AppSettings.fromJson) ??
          AppSettings.defaults;
    } on StorageException {
      return AppSettings.defaults;
    }
  }

  // --------------------------------------------------------------------------
  // Write
  // --------------------------------------------------------------------------

  /// Persists [settings].
  Future<void> save(AppSettings settings) =>
      _storage.writeJson(_key, settings, (s) => s.toJson());

  /// Convenience: load, apply [update], then save.
  Future<void> update(AppSettings Function(AppSettings) update) async {
    final current = await load();
    await save(update(current));
  }

  // --------------------------------------------------------------------------
  // Reactive watch
  // --------------------------------------------------------------------------

  /// Stream of [AppSettings] — emits the current value immediately on
  /// subscription, then again whenever [save] / [update] is called.
  Stream<AppSettings> watchSettings() => _storage.watch(_key).map(
        (raw) {
          if (raw == null) return AppSettings.defaults;
          try {
            return AppSettings.fromJson(
              Map<String, dynamic>.from(jsonDecode(raw) as Map),
            );
          } on FormatException {
            return AppSettings.defaults;
          }
        },
      );

  // --------------------------------------------------------------------------
  // Reset
  // --------------------------------------------------------------------------

  Future<void> reset() => _storage.delete(_key);
}

// ---------------------------------------------------------------------------
// Usage demonstration
// ---------------------------------------------------------------------------

Future<void> runSettingsExample(JustStandardStorage storage) async {
  final service = SettingsService(storage);

  // Save initial settings.
  await service.save(
    const AppSettings(
      theme: ChessTheme.dark,
      boardStyle: BoardStyle.walnut,
      soundEnabled: false,
    ),
  );

  // Load them back.
  final loaded = await service.load();
  assert(loaded.theme == ChessTheme.dark);
  assert(loaded.boardStyle == BoardStyle.walnut);
  assert(!loaded.soundEnabled);

  // Partial update — only flip sound.
  await service.update((s) => s.copyWith(soundEnabled: true));
  final updated = await service.load();
  assert(updated.boardStyle == BoardStyle.walnut); // unchanged
  assert(updated.soundEnabled); // flipped

  // Reset to defaults.
  await service.reset();
  final reset = await service.load();
  assert(reset.theme == AppSettings.defaults.theme);
}
