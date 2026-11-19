@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_storage/src/web/web.dart';
import 'package:web/web.dart' as web;

import '../support/storage_contract.dart';

void main() {
  setUp(() => web.window.localStorage.clear());

  group('WebStorage contract', () {
    storageContract(
      () => (open: () async => WebStorage(), reopen: () async => WebStorage()),
    );
  });

  test('keeps each value under just_storage:<key>', () async {
    await WebStorage().write('theme', 'dark');
    expect(web.window.localStorage.getItem('just_storage:theme'), 'dark');
  });

  test('clear leaves other keys of the page alone', () async {
    web.window.localStorage.setItem('someone_else', 'x');
    final s = WebStorage();
    await s.write('a', '1');
    await s.clear();
    expect(web.window.localStorage.getItem('someone_else'), 'x');
    expect(await s.readAll(), isEmpty);
  });

  test('the factory hands out one instance', () async {
    expect(
      identical(await JustStorage.standard(), await JustStorage.standard()),
      isTrue,
    );
  });
}
