import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_storage/just_storage.dart';
import 'package:just_storage/ui.dart';

import '../support/memory_storage.dart';
import '../support/workbench_support.dart';

const _wide = Size(1400, 900);
const _medium = Size(1000, 800);
const _phone = Size(400, 820);

void main() {
  late MemoryStandardStorage standard;
  late MemorySecureStorage secure;
  String? clipboard;

  setUp(() {
    standard = MemoryStandardStorage()
      ..values.addAll({
        'theme': 'dark',
        'volume': '0.8',
        'profile': '{"name":"Ada","level":3,"tags":["a","b"]}',
      });
    secure = MemorySecureStorage()..values.addAll({'token': 'abc123'});
    clipboard = null;
  });

  Future<void> show(
    WidgetTester tester, {
    Size size = _wide,
    bool readOnly = false,
    StorageAdminController? controller,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: JustStorageAdminScreen(
          controller: controller,
          readOnly: readOnly,
          theme: theme,
          stores: [
            adminStore('Standard', standard),
            adminStore('Secure', secure),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder row(String key) => find.byKey(ValueKey('jst-entry-$key'));

  String shownValue(WidgetTester tester) => tester
      .widget<SelectableText>(find.byKey(const ValueKey('jst-value-text')))
      .data!;

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  Future<void> openStore(WidgetTester tester, String name) =>
      tapKey(tester, 'jst-store-$name');

  Future<void> rowMenu(WidgetTester tester, String key, String item) async {
    await tester.tap(row(key), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await tester.pumpAndSettle();
  }

  group('wide', () {
    testWidgets('lists the storages, and a value beside its entry', (
      tester,
    ) async {
      await show(tester);
      expect(find.text('STORAGES'), findsOneWidget);
      expect(find.text('3 entries · 66 B'), findsWidgets);
      expect(find.text('1 entry · 11 B'), findsOneWidget);
      expect(row('theme'), findsOneWidget);
      expect(find.text('No entry selected'), findsOneWidget);

      await tester.tap(row('theme'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('jst-value-panel')), findsOneWidget);
      expect(shownValue(tester), 'dark');
    });

    testWidgets('shows JSON formatted, as a tree, or raw', (tester) async {
      await show(tester);
      await tester.tap(row('profile'));
      await tester.pumpAndSettle();
      expect(shownValue(tester), contains('\n  "name": "Ada"'));

      await tester.tap(find.text('Tree'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('jst-tree')), findsOneWidget);
      expect(find.text('"Ada"'), findsOneWidget);
      expect(find.text('"tags": '), findsOneWidget);

      await tester.tap(find.text('Raw'));
      await tester.pumpAndSettle();
      expect(shownValue(tester), standard.values['profile']);
    });

    testWidgets('secure values are hidden, and not searched, until shown', (
      tester,
    ) async {
      await show(tester);
      await openStore(tester, 'Secure');
      expect(row('token'), findsOneWidget);
      expect(find.textContaining('abc123'), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('jst-search')), 'abc');
      await tester.pumpAndSettle();
      expect(row('token'), findsNothing);
      expect(find.text('No matches'), findsOneWidget);

      await tapKey(tester, 'jst-toggle-values');
      expect(row('token'), findsOneWidget);
      expect(find.textContaining('abc123'), findsOneWidget);
    });

    testWidgets('search and show-values survive switching storages', (
      tester,
    ) async {
      await show(tester);
      await tester.enterText(find.byKey(const ValueKey('jst-search')), 'vol');
      await tester.pumpAndSettle();
      expect(row('theme'), findsNothing);
      await openStore(tester, 'Secure');
      await openStore(tester, 'Standard');
      expect(row('theme'), findsNothing);
      expect(row('volume'), findsOneWidget);
      expect(find.text('1 of 3 entries'), findsOneWidget);
    });

    testWidgets('a new entry may not take a key that holds a value', (
      tester,
    ) async {
      await show(tester);
      await tapKey(tester, 'jst-add-entry');
      await tester.enterText(
        find.byKey(const ValueKey('jst-new-entry-key')),
        'theme',
      );
      await tester.enterText(
        find.byKey(const ValueKey('jst-new-entry-value')),
        'light',
      );
      await tapKey(tester, 'jst-new-entry-add');
      expect(find.text('"theme" already holds a value.'), findsOneWidget);
      expect(standard.values['theme'], 'dark');

      await tester.enterText(
        find.byKey(const ValueKey('jst-new-entry-key')),
        'blank',
      );
      await tester.enterText(
        find.byKey(const ValueKey('jst-new-entry-value')),
        '',
      );
      await tapKey(tester, 'jst-new-entry-add');
      expect(standard.values['blank'], '');
      // The new entry is selected.
      expect(
        tester
            .widget<SelectableText>(find.byKey(const ValueKey('jst-value-key')))
            .data,
        'blank',
      );
    });

    testWidgets('the new entry dialog checks JSON as it is typed', (
      tester,
    ) async {
      await show(tester);
      await tapKey(tester, 'jst-add-entry');
      await tester.enterText(
        find.byKey(const ValueKey('jst-new-entry-value')),
        '{"a": ',
      );
      await tester.pump();
      expect(find.textContaining('Not valid JSON'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('jst-new-entry-value')),
        '{"a": 1}',
      );
      await tester.pump();
      expect(find.text('Valid JSON object · 1 key'), findsOneWidget);
    });

    testWidgets('edits a value in place', (tester) async {
      await show(tester);
      await tester.tap(row('theme'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'jst-value-edit');
      await tester.enterText(
        find.byKey(const ValueKey('jst-value-editor')),
        'light',
      );
      await tapKey(tester, 'jst-value-save');
      expect(standard.values['theme'], 'light');
      expect(shownValue(tester), 'light');
    });

    testWidgets('warns when the value changes while it is edited', (
      tester,
    ) async {
      await show(tester);
      await tester.tap(row('theme'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'jst-value-edit');
      standard.changeBehindItsBack('theme', 'blue');
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('jst-value-conflict')), findsOneWidget);
      await tester.tap(find.text('Load the new value'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('jst-value-editor')))
            .controller!
            .text,
        'blue',
      );
    });

    testWidgets('renames and duplicates an entry from its menu', (
      tester,
    ) async {
      await show(tester);
      await rowMenu(tester, 'theme', 'Rename…');
      await tester.enterText(
        find.byKey(const ValueKey('jst-prompt')),
        'volume',
      );
      await tapKey(tester, 'jst-prompt-ok');
      expect(find.text('"volume" already holds a value.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('jst-prompt')), 'look');
      await tapKey(tester, 'jst-prompt-ok');
      expect(standard.values.containsKey('theme'), isFalse);
      expect(standard.values['look'], 'dark');

      await rowMenu(tester, 'look', 'Duplicate…');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('jst-prompt')))
            .controller!
            .text,
        'look_copy',
      );
      await tapKey(tester, 'jst-prompt-ok');
      expect(standard.values['look_copy'], 'dark');
    });

    testWidgets('deletes the selected entry from its panel', (tester) async {
      await show(tester);
      await tester.tap(row('theme'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'jst-value-menu');
      await tester.tap(find.text('Delete…'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'jst-confirm');
      expect(standard.values.containsKey('theme'), isFalse);
      expect(row('theme'), findsNothing);
      expect(find.text('No entry selected'), findsOneWidget);
    });

    testWidgets('deletes the checked entries at once', (tester) async {
      await show(tester);
      for (final key in ['theme', 'volume']) {
        await tester.tap(
          find.descendant(of: row(key), matching: find.byType(Checkbox)),
        );
        await tester.pump();
      }
      expect(find.text('2 selected'), findsOneWidget);
      await tapKey(tester, 'jst-delete-selected');
      expect(find.text('Delete 2 entries?'), findsOneWidget);
      await tapKey(tester, 'jst-confirm');
      expect(standard.values.keys, ['profile']);
      expect(find.byKey(const ValueKey('jst-selection-bar')), findsNothing);
    });

    testWidgets('shows what the app writes as it writes it, marked for a '
        'moment', (tester) async {
      await show(tester);
      standard.changeBehindItsBack('score', '120');
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      expect(row('score'), findsOneWidget);
      expect(
        find.descendant(
          of: row('score'),
          matching: find.byKey(const ValueKey('jst-recent')),
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(find.byKey(const ValueKey('jst-recent')), findsNothing);
    });

    testWidgets('a storage that can\'t be read leaves the others, and can '
        'be cleared', (tester) async {
      secure.failure = const StorageCorruptException(
        'secure.enc',
        'none of its values can be decrypted.',
      );
      await show(tester);
      expect(row('theme'), findsOneWidget);
      expect(find.text('Can\'t be read'), findsOneWidget);

      await openStore(tester, 'Secure');
      expect(find.byKey(const ValueKey('jst-store-error')), findsOneWidget);
      await tapKey(tester, 'jst-error-clear');
      await tester.enterText(
        find.byKey(const ValueKey('jst-confirm-text')),
        'Secure',
      );
      await tester.pump();
      await tapKey(tester, 'jst-confirm');
      expect(secure.clears, 1);
      expect(find.byKey(const ValueKey('jst-store-error')), findsNothing);
      expect(find.text('No entries yet'), findsOneWidget);
    });

    testWidgets('exports JSON, warning that secure values come out plain', (
      tester,
    ) async {
      await show(tester);
      await openStore(tester, 'Secure');
      await tapKey(tester, 'jst-store-menu-Secure');
      await tapKey(tester, 'jst-menu-export');
      expect(
        find.byKey(const ValueKey('jst-export-secure-warning')),
        findsOneWidget,
      );
      // The preview hides the values, as the screen does.
      expect(find.textContaining('abc123'), findsNothing);
      await tapKey(tester, 'jst-export-show');
      expect(find.textContaining('abc123'), findsOneWidget);
      await tapKey(tester, 'jst-export-copy');
      final exported = jsonDecode(clipboard!) as Map<String, dynamic>;
      expect(exported['store'], 'Secure');
      expect(exported['entries'], {'token': 'abc123'});
    });

    testWidgets('imports pasted JSON, merging or adding only new keys', (
      tester,
    ) async {
      await show(tester);
      await tapKey(tester, 'jst-store-menu-Standard');
      await tapKey(tester, 'jst-menu-import');
      await tester.enterText(
        find.byKey(const ValueKey('jst-import-text')),
        '{"theme": "light", "lang": "en", "count": 3}',
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.text(
          '3 entries: 2 new, 1 already in Standard · 1 not text, kept as '
          'their JSON',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Only new keys'));
      await tester.pump();
      expect(find.text('Import 2 entries'), findsOneWidget);
      await tapKey(tester, 'jst-import-run');
      expect(standard.values['theme'], 'dark');
      expect(standard.values['lang'], 'en');
      expect(standard.values['count'], '3');
    });

    testWidgets('import can replace everything', (tester) async {
      await show(tester);
      await tapKey(tester, 'jst-store-menu-Standard');
      await tapKey(tester, 'jst-menu-import');
      await tester.enterText(
        find.byKey(const ValueKey('jst-import-text')),
        '{"format": "just_storage", "version": 1, "store": "X", '
        '"entries": {"only": "this"}}',
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Replace all'));
      await tester.pump();
      await tapKey(tester, 'jst-import-run');
      await tapKey(tester, 'jst-confirm');
      expect(standard.values, {'only': 'this'});
    });

    testWidgets('the details count the entries and their kinds', (
      tester,
    ) async {
      await show(tester);
      await tapKey(tester, 'jst-tab-details');
      expect(find.text('Keys and values'), findsOneWidget);
      expect(find.text('66 B'), findsOneWidget);
      expect(find.text('Kept by the app'), findsOneWidget);
      expect(find.text('Number: 1'), findsOneWidget);
      expect(find.text('JSON object: 1'), findsOneWidget);
      expect(find.text('Text: 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('jst-details-clear')), findsOneWidget);
      expect(find.byKey(const ValueKey('jst-details-wipe')), findsNothing);
    });

    testWidgets('read-only changes nothing, but still shows and exports', (
      tester,
    ) async {
      await show(tester, readOnly: true);
      expect(find.text('Read-only'), findsOneWidget);
      expect(find.byKey(const ValueKey('jst-add-entry')), findsNothing);
      await tester.tap(row('theme'));
      await tester.pumpAndSettle();
      expect(shownValue(tester), 'dark');
      expect(find.byKey(const ValueKey('jst-value-edit')), findsNothing);
      expect(find.byKey(const ValueKey('jst-value-copy')), findsOneWidget);
      expect(find.byKey(const ValueKey('jst-delete-selected')), findsNothing);

      await tapKey(tester, 'jst-store-menu-Standard');
      expect(find.byKey(const ValueKey('jst-menu-export')), findsOneWidget);
      expect(find.byKey(const ValueKey('jst-menu-import')), findsNothing);
      expect(find.byKey(const ValueKey('jst-menu-clear')), findsNothing);
    });
  });

  testWidgets('without room for a panel, a value opens in a dialog', (
    tester,
  ) async {
    await show(tester, size: _medium);
    expect(find.text('No entry selected'), findsNothing);
    await tester.tap(row('volume'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(shownValue(tester), '0.8');
  });

  group('phone', () {
    testWidgets('drills from storages to entries to a value', (tester) async {
      await show(tester, size: _phone);
      expect(find.text('STORAGES'), findsNothing);
      await openStore(tester, 'Standard');
      expect(row('theme'), findsOneWidget);
      expect(find.byKey(const ValueKey('jst-add-entry')), findsOneWidget);

      await tester.tap(row('theme'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('jst-entry-title')), findsOneWidget);
      expect(shownValue(tester), 'dark');

      // Deleting it goes back to the list.
      await tapKey(tester, 'jst-value-menu');
      await tester.tap(find.text('Delete…'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'jst-confirm');
      expect(find.byKey(const ValueKey('jst-entry-title')), findsNothing);
      expect(row('theme'), findsNothing);
      expect(row('volume'), findsOneWidget);
    });

    testWidgets('a long press selects; back leaves selection first', (
      tester,
    ) async {
      await show(tester, size: _phone);
      await openStore(tester, 'Standard');
      expect(find.byType(Checkbox), findsNothing);
      await tester.longPress(row('theme'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(row('volume'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      await navigator.maybePop();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('jst-selection-bar')), findsNothing);
      expect(row('theme'), findsOneWidget, reason: 'still on the page');
    });

    testWidgets('a phone page gives way when the window gets wide', (
      tester,
    ) async {
      await show(tester, size: _phone);
      await openStore(tester, 'Secure');
      tester.view.physicalSize = _wide;
      await tester.pumpAndSettle();
      expect(find.text('STORAGES'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('jst-workspace-title')))
            .data,
        'Secure',
      );
    });
  });

  group('appearance', () {
    ThemeData themeAt(WidgetTester tester, Finder finder) =>
        Theme.of(tester.element(finder));

    StorageAdminController controllerFor({
      ThemeMode themeMode = ThemeMode.dark,
    }) {
      final controller = StorageAdminController(
        stores: [
          adminStore('Standard', standard),
          adminStore('Secure', secure),
        ],
        themeMode: themeMode,
      );
      addTearDown(controller.dispose);
      return controller;
    }

    testWidgets('dark with coral by default; the button switches to light', (
      tester,
    ) async {
      final controller = controllerFor();
      await show(tester, controller: controller);
      var theme = themeAt(tester, row('theme'));
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, const Color(0xFFF5746F));

      await tapKey(tester, 'jst-theme-toggle');
      theme = themeAt(tester, row('theme'));
      expect(controller.themeMode, ThemeMode.light);
      expect(theme.brightness, Brightness.light);
      expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);

      await tapKey(tester, 'jst-theme-toggle');
      expect(controller.themeMode, ThemeMode.dark);
      expect(themeAt(tester, row('theme')).brightness, Brightness.dark);
    });

    testWidgets('follows the device when asked to', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await show(
        tester,
        controller: controllerFor(themeMode: ThemeMode.system),
      );
      expect(themeAt(tester, row('theme')).brightness, Brightness.light);
    });

    testWidgets('a given theme is used in its brightness, remade in the '
        'other', (tester) async {
      final given = ThemeData(colorSchemeSeed: const Color(0xFF00897B));
      final controller = controllerFor(themeMode: ThemeMode.light);
      await show(tester, controller: controller, theme: given);
      expect(themeAt(tester, row('theme')).colorScheme, given.colorScheme);

      controller.setThemeMode(ThemeMode.dark);
      await tester.pumpAndSettle();
      final dark = themeAt(tester, row('theme')).colorScheme;
      expect(dark.brightness, Brightness.dark);
      expect(dark.primary, isNot(const Color(0xFFF5746F)));
      expect(dark, isNot(given.colorScheme));
    });

    testWidgets('pages pushed on a phone follow a change', (tester) async {
      final controller = controllerFor();
      await show(tester, size: _phone, controller: controller);
      await openStore(tester, 'Standard');
      expect(themeAt(tester, row('theme')).brightness, Brightness.dark);

      controller.setThemeMode(ThemeMode.light);
      await tester.pumpAndSettle();
      expect(themeAt(tester, row('theme')).brightness, Brightness.light);
    });
  });

  testWidgets('a shared controller drives the screen', (tester) async {
    final controller = StorageAdminController(
      stores: [adminStore('Standard', standard), adminStore('Secure', secure)],
    );
    addTearDown(controller.dispose);
    await show(tester, controller: controller);
    controller.select(controller.storeNamed('Secure')!, key: 'token');
    await tester.pumpAndSettle();
    expect(find.text('Value hidden'), findsOneWidget);
    await tapKey(tester, 'jst-value-show');
    expect(shownValue(tester), 'abc123');
  });

  testWidgets('closing the screen while it reads is fine', (tester) async {
    final gate = standard.gate = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: JustStorageAdminScreen(
          stores: [adminStore('Standard', standard)],
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
