/// What the admin screen asks about a storage beyond its values — where it
/// keeps them, whether it can be wiped — of the platform, or of the app a
/// remote storage belongs to.
@internal
library;

import 'package:flutter/foundation.dart' show internal;

import '../../core/admin_types.dart';
import '../../core/core.dart';
import '../../file/admin_support.dart'
    if (dart.library.js_interop) '../../web/admin_support.dart'
    as platform;
import 'remote_storage.dart';

/// Where [storage] keeps its values; null for a storage that says nothing.
@internal
Future<StoreDescription?> describeStorage(JustKeyValueStorage storage) =>
    storage is RemoteStorage
    ? storage.describe()
    : platform.describeStorage(storage);

/// Whether [storage] can be wiped: emptied, with its key destroyed.
@internal
bool canWipeStorage(JustKeyValueStorage storage) =>
    storage is RemoteStorage ? storage.info.canWipe : platform.canWipe(storage);

/// Empties [storage] and destroys its key; see [canWipeStorage].
@internal
Future<void> wipeStorage(JustKeyValueStorage storage) =>
    storage is RemoteStorage ? storage.wipe() : platform.wipeStorage(storage);

/// The class of [storage] — in the app, for a remote one.
@internal
String storageTypeName(JustKeyValueStorage storage) =>
    storage is RemoteStorage ? storage.info.type : '${storage.runtimeType}';
