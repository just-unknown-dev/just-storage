/// What the admin screen asks of the platform in a browser: where a
/// storage's values are, wiping one, and export files as downloads — not
/// exported.
@internal
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart' show internal;
import 'package:web/web.dart' as web;

import '../core/admin_types.dart';
import '../core/core.dart';
import 'web_key_store.dart';
import 'web_secure_storage.dart';
import 'web_storage.dart';

/// Where [storage] keeps its values; null for a storage this package
/// didn't make.
@internal
Future<StoreDescription?> describeStorage(JustKeyValueStorage storage) async {
  final String prefix;
  final bool secure;
  if (storage is WebStorage) {
    prefix = WebStorage.prefix;
    secure = false;
  } else if (storage is WebSecureStorage) {
    prefix = WebSecureStorage.prefix;
    secure = true;
  } else {
    return null;
  }
  final web.Storage local;
  try {
    local = web.window.localStorage;
  } catch (_) {
    return const StoreDescription(
      medium: 'Browser storage',
      facts: [StoreFact('localStorage', 'Not available in this browser')],
    );
  }
  var items = 0;
  var units = 0;
  for (var i = 0; i < local.length; i++) {
    final name = local.key(i);
    if (name == null || !name.startsWith(prefix)) continue;
    items++;
    units += name.length + (local.getItem(name)?.length ?? 0);
  }
  String origin;
  try {
    origin = web.window.location.origin;
  } catch (_) {
    origin = 'this page';
  }
  final rawKey = secure && local.getItem(WebKeyStore.rawKeyEntry) != null;
  return StoreDescription(
    medium: secure ? 'Encrypted browser storage' : 'Browser storage',
    // Browsers count localStorage in UTF-16 code units: two bytes each.
    sizeBytes: items == 0 ? null : units * 2,
    canWipe: secure,
    facts: [
      StoreFact('Origin', origin, path: true),
      StoreFact(
        'Items',
        'localStorage, one item per value, named $prefix<key> '
            '($items now)',
      ),
      if (secure) ...[
        const StoreFact(
          'Format',
          'Version 2: each value sealed with AES-256-GCM and bound to its '
              'key',
        ),
        StoreFact(
          'Key',
          rawKey
              ? 'Raw, in localStorage: IndexedDB is unavailable here'
              : 'A Web Crypto key in IndexedDB "just_storage": scripts on '
                    'the page can use it but not read it',
        ),
      ] else
        const StoreFact(
          'Format',
          'Plain text: any script on the page can read the values',
        ),
      const StoreFact(
        'Shared',
        'With every tab of this origin: changes made there show here',
      ),
    ],
  );
}

/// Whether [storage] can be wiped: emptied, with its key destroyed.
@internal
bool canWipe(JustKeyValueStorage storage) => storage is WebSecureStorage;

/// Empties [storage] and destroys its key; see [canWipe].
@internal
Future<void> wipeStorage(JustKeyValueStorage storage) =>
    (storage as WebSecureStorage).wipe();

/// Whether [pickTextFile] can show a file picker here.
@internal
const bool canPickFiles = true;

/// Whether a file can be read from a path the user types: never in a
/// browser.
@internal
bool get canReadTypedPaths => false;

/// Where exports go: the browser's downloads, so there is no folder.
@internal
Future<String?> exportsLocation() async => null;

/// Downloads [content] as [fileName] and says where it went.
@internal
Future<String> saveExport(String fileName, String content) async {
  final blob = web.Blob(
    <web.BlobPart>[content.toJS].toJS,
    web.BlobPropertyBag(type: 'application/json;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  // Give the browser a moment to start the download before freeing it.
  Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
  return "your browser's downloads ($fileName)";
}

/// No folder to list in a browser.
@internal
Future<List<ExportFile>> listExports() async => const [];

/// A browser cannot read a file by path.
@internal
Future<String> readExport(String path) =>
    Future.error(UnsupportedError('A browser cannot read files by path.'));

/// Shows the browser's file picker and reads the chosen file as text; null
/// when nothing was chosen.
@internal
Future<PickedTextFile?> pickTextFile() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.json,.txt,application/json,text/plain';
  final chosen = Completer<web.File?>();
  input.onchange = ((web.Event _) {
    if (!chosen.isCompleted) chosen.complete(input.files?.item(0));
  }).toJS;
  input.addEventListener(
    'cancel',
    ((web.Event _) {
      if (!chosen.isCompleted) chosen.complete(null);
    }).toJS,
  );
  input.click();
  final file = await chosen.future;
  if (file == null) return null;
  final text = (await file.text().toDart).toDart;
  return (name: file.name, content: text);
}
