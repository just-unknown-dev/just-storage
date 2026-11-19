import 'dart:async';

import 'package:flutter/foundation.dart' show internal;

import 'just_key_value_storage.dart';

/// The listeners of a storage's [JustKeyValueStorage.watch] streams, by key.
///
/// Each listener gets the key's value when it starts listening, then every
/// value [changed] reports after that. Values are delivered synchronously,
/// as the storage reports them, so a listener sees a write before the
/// writer's future completes.
@internal
final class ValueWatchers {
  final Map<String, Set<_Listener>> _byKey = {};

  /// The keys someone is watching now.
  Iterable<String> get keys => _byKey.keys;

  /// A broadcast stream of [key]'s values.
  ///
  /// A new listener waits for [load] — the storage reading what it holds —
  /// then gets [now], [key]'s value at that moment. Changes reported while
  /// it waits are already in that value, so they are not sent again. If
  /// [load] fails, the listener gets the error and the changes that follow.
  Stream<String?> watch(
    String key, {
    required Future<void> Function() load,
    required String? Function() now,
  }) {
    return Stream<String?>.multi((controller) {
      final listener = _Listener(controller);
      final listeners = _byKey.putIfAbsent(key, () => {})..add(listener);
      controller.onCancel = () {
        listeners.remove(listener);
        if (listeners.isEmpty && identical(_byKey[key], listeners)) {
          _byKey.remove(key);
        }
      };
      load().then(
        (_) {
          if (!listeners.contains(listener)) return;
          final String? value;
          try {
            value = now();
          } catch (e, s) {
            listener.ready = true;
            controller.addErrorSync(e, s);
            return;
          }
          listener.ready = true;
          controller.addSync(value);
        },
        onError: (Object e, StackTrace s) {
          if (!listeners.contains(listener)) return;
          listener.ready = true;
          controller.addErrorSync(e, s);
        },
      );
    }, isBroadcast: true);
  }

  /// Sends [value] to everyone watching [key].
  void changed(String key, String? value) {
    final listeners = _byKey[key];
    if (listeners == null) return;
    for (final listener in [...listeners]) {
      if (listener.ready) listener.controller.addSync(value);
    }
  }

  /// Ends every stream handed out so far.
  void closeAll() {
    final all = <_Listener>[];
    for (final set in _byKey.values) {
      all.addAll(set);
      // A listener still waiting for its first value finds itself gone.
      set.clear();
    }
    _byKey.clear();
    for (final listener in all) {
      listener.controller.closeSync();
    }
  }
}

final class _Listener {
  _Listener(this.controller);

  final MultiStreamController<String?> controller;

  /// Whether it has had its first value, so changes go to it now.
  bool ready = false;
}
