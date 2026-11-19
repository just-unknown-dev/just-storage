import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_storage/just_storage.dart';
import 'package:just_storage/ui.dart';

import '../support/memory_storage.dart';

void main() {
  late MemoryStandardStorage standard;
  late MemorySecureStorage secure;

  setUp(() {
    standard = MemoryStandardStorage()..values.addAll({'theme': 'dark'});
    secure = MemorySecureStorage()..values.addAll({'token': 'abc123'});
  });

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: JustStorageAdminScreen(standard: standard, secure: secure),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  testWidgets('lists the standard entries', (tester) async {
    await show(tester);
    expect(find.text('theme'), findsOneWidget);
    expect(find.text('dark'), findsOneWidget);
  });

  testWidgets('hides secure values until shown', (tester) async {
    await show(tester);
    await openTab(tester, 'Secure');
    expect(find.text('token'), findsOneWidget);
    expect(find.text('abc123'), findsNothing);
    await tester.tap(find.byTooltip('Show values'));
    await tester.pumpAndSettle();
    expect(find.text('abc123'), findsOneWidget);
  });

  testWidgets('hidden values are not searched', (tester) async {
    await show(tester);
    await openTab(tester, 'Secure');
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pumpAndSettle();
    expect(find.text('token'), findsNothing);
    await tester.tap(find.byTooltip('Show values'));
    await tester.pumpAndSettle();
    expect(find.text('token'), findsOneWidget);
  });

  testWidgets('a secure storage that cannot be read leaves the standard one, '
      'and can be cleared', (tester) async {
    secure.failure = const StorageCorruptException(
      'secure.enc',
      'none of its values can be decrypted.',
    );
    await show(tester);
    expect(find.text('theme'), findsOneWidget);

    await openTab(tester, 'Secure');
    expect(find.textContaining('can\'t be read'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear all'));
    await tester.pumpAndSettle();
    expect(secure.clears, 1);
    expect(find.textContaining('can\'t be read'), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('adds an entry, an empty value too', (tester) async {
    await show(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Key'), 'blank');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(standard.values['blank'], '');
    expect(find.text('blank'), findsOneWidget);
  });

  testWidgets('deletes an entry', (tester) async {
    await show(tester);
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(standard.values, isEmpty);
    expect(find.text('theme'), findsNothing);
  });

  testWidgets('a failed write shows its error', (tester) async {
    await show(tester);
    standard.failure = const StorageException('disk full');
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Key'), 'k');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('disk full'), findsWidgets);
  });

  testWidgets('closing the screen while it reads is fine', (tester) async {
    final gate = standard.gate = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: JustStorageAdminScreen(standard: standard, secure: secure),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the info tab counts the entries', (tester) async {
    await show(tester);
    await openTab(tester, 'Info');
    expect(find.text('Standard entries'), findsOneWidget);
    expect(find.text('1'), findsNWidgets(2));
  });
}
