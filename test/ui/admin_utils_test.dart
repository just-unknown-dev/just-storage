import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_storage/src/ui/admin_utils.dart';

void main() {
  group('kindOf', () {
    test('tells the kinds apart', () {
      expect(kindOf(''), ValueKind.empty);
      expect(kindOf('true'), ValueKind.boolean);
      expect(kindOf('false'), ValueKind.boolean);
      expect(kindOf('42'), ValueKind.number);
      expect(kindOf('-0.5e3'), ValueKind.number);
      expect(kindOf('{"a": 1}'), ValueKind.object);
      expect(kindOf('  [1, 2]'), ValueKind.array);
      expect(kindOf('hello'), ValueKind.text);
    });

    test('only JSON numbers are numbers', () {
      for (final notNumber in [
        'NaN',
        'Infinity',
        ' 1',
        '1 ',
        '01',
        '1.',
        '+1',
      ]) {
        expect(kindOf(notNumber), ValueKind.text, reason: notNumber);
      }
    });

    test('text that only looks like JSON is text', () {
      expect(kindOf('{not json'), ValueKind.text);
      expect(kindOf('"quoted"'), ValueKind.text);
      expect(kindOf('True'), ValueKind.text);
    });
  });

  test('utf8Length counts as UTF-8 does', () {
    for (final s in [
      '',
      'abc',
      'ß',
      '✓ 日本',
      '🎮 x',
      '\u{10FFFF}',
      'a\uD800b',
    ]) {
      expect(utf8Length(s), utf8.encode(s).length, reason: s);
    }
  });

  test('formatBytes', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1023), '1023 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
  });

  test('entries and plural', () {
    expect(entries(1), '1 entry');
    expect(entries(0), '0 entries');
    expect(plural(2, 'key'), '2 keys');
  });

  group('checkJson', () {
    test('says what valid JSON holds', () {
      expect(checkJson('{"a": 1, "b": 2}').summary, contains('2 keys'));
      expect(checkJson('[1]').summary, contains('1 item'));
    });

    test('says where invalid JSON fails', () {
      final check = checkJson('{\n  "a": 1,\n  oops\n}');
      expect(check.isValid, isFalse);
      expect(check.line, 3);
      expect(check.column, 3);
      expect(check.summary, contains('line 3, column 3'));
    });
  });

  group('export and import', () {
    test('an export reads back, with its storage named', () {
      final json = buildExport(
        store: 'Secure',
        secure: true,
        entries: {'b': '2', 'a': '', 'c': '{"x":1}'},
        now: DateTime.utc(2026, 11, 20),
      );
      final data = parseImport(json);
      expect(data.entries, {'a': '', 'b': '2', 'c': '{"x":1}'});
      expect(data.store, 'Secure');
      expect(data.fromSecure, isTrue);
      expect(data.converted, 0);
      // Sorted by key.
      expect(json.indexOf('"a"'), lessThan(json.indexOf('"b"')));
    });

    test('a plain object imports, values that are not text as JSON', () {
      final data = parseImport(
        '{"theme": "dark", "volume": 0.8, "flags": [1]}',
      );
      expect(data.entries, {'theme': 'dark', 'volume': '0.8', 'flags': '[1]'});
      expect(data.converted, 2);
      expect(data.store, isNull);
      expect(data.fromSecure, isFalse);
    });

    test('what is not an object is refused, saying why', () {
      expect(() => parseImport(''), throwsFormatException);
      expect(() => parseImport('[1, 2]'), throwsFormatException);
      expect(
        () => parseImport('{"a": '),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Not valid JSON'),
          ),
        ),
      );
      expect(
        () => parseImport('{"format": "just_storage", "entries": 3}'),
        throwsFormatException,
      );
    });

    test('file names are safe and dated', () {
      final name = exportFileName(
        'Game saves / 2',
        now: DateTime(2026, 11, 20, 9, 5, 7),
      );
      expect(name, 'just_storage-Game_saves_2-20261120-090507.json');
      expect(exportFileName('///'), startsWith('just_storage-store-'));
    });
  });
}
