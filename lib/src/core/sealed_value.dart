import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show internal;

/// One encrypted value as a secure storage keeps it: the nonce it was
/// encrypted with, and the ciphertext with its 16-byte GCM tag.
///
/// The format both platforms write is version [current]: the value is
/// encrypted with its key as additional authenticated data ([aadFor]), so a
/// value moved to another key fails its check. Version 1, written before
/// 2.0.0, had no additional data; a storage still reads it and writes it
/// back as version 2.
@internal
final class SealedValue {
  /// A sealed value from its parts.
  const SealedValue(this.nonce, this.ciphertext);

  /// The format version written now.
  static const int current = 2;

  /// The 12-byte nonce.
  final Uint8List nonce;

  /// The ciphertext followed by the 16-byte GCM tag.
  final Uint8List ciphertext;

  /// The additional authenticated data a value under [key] is sealed with,
  /// in format [version].
  static Uint8List aadFor(String key, int version) => version < 2
      ? Uint8List(0)
      : Uint8List.fromList(utf8.encode('just_storage/v2/$key'));

  /// As JSON: `{"n": <base64 nonce>, "ct": <base64 ciphertext>}`.
  Map<String, String> toJson() => {
    'n': base64.encode(nonce),
    'ct': base64.encode(ciphertext),
  };

  /// Reads [json] as [toJson] writes it. Throws a [FormatException] when it
  /// isn't.
  static SealedValue fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('An encrypted value is not a JSON object.');
    }
    final n = json['n'];
    final ct = json['ct'];
    if (n is! String || ct is! String) {
      throw const FormatException('An encrypted value lacks "n" or "ct".');
    }
    return SealedValue(base64.decode(n), base64.decode(ct));
  }
}
