import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show internal;
import 'package:pointycastle/export.dart';

import '../core/core.dart';

/// AES-256-GCM authenticated encryption, in pure Dart (pointycastle), for
/// `EncryptedFileStorage`.
///
/// * Key: 256 bits (32 bytes).
/// * Nonce: 96 bits (12 bytes), random for every [seal].
/// * Tag: 128 bits (16 bytes), after the ciphertext.
///
/// [open] checks the tag before it returns anything: a changed ciphertext,
/// nonce, key or additional data fails.
@internal
final class AesGcmCipher {
  /// The cipher; it holds no state.
  const AesGcmCipher();

  /// Key length in bytes.
  static const int keyLength = 32;

  /// Nonce length in bytes.
  static const int nonceLength = 12;

  static const int _tagBits = 128;

  static final Random _random = Random.secure();

  /// [length] cryptographically random bytes.
  static Uint8List randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  /// Encrypts [plaintext] under [key] with a fresh random nonce, binding
  /// [aad] to it. Returns the nonce and `ciphertext || tag`.
  ({Uint8List nonce, Uint8List ciphertext}) seal(
    Uint8List key,
    Uint8List plaintext,
    Uint8List aad,
  ) {
    _checkKey(key);
    final nonce = randomBytes(nonceLength);
    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(true, AEADParameters(KeyParameter(key), _tagBits, nonce, aad));
      return (nonce: nonce, ciphertext: cipher.process(plaintext));
    } catch (e) {
      throw StorageException('AES-GCM encryption failed.', cause: e);
    }
  }

  /// Decrypts [ciphertext] (`ciphertext || tag`) sealed under [key] with
  /// [nonce] and [aad].
  ///
  /// Throws a [StorageException] when the tag doesn't match: the value, its
  /// nonce, the key or the additional data is not what it was sealed with.
  Uint8List open(
    Uint8List key,
    Uint8List nonce,
    Uint8List ciphertext,
    Uint8List aad,
  ) {
    _checkKey(key);
    if (nonce.length != nonceLength) {
      throw StorageException(
        'An AES-GCM nonce is $nonceLength bytes, not ${nonce.length}.',
      );
    }
    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(false, AEADParameters(KeyParameter(key), _tagBits, nonce, aad));
      return cipher.process(ciphertext);
    } on InvalidCipherTextException catch (e) {
      throw StorageException(
        'AES-GCM authentication failed: the value is damaged, was changed, '
        'or was sealed with another key.',
        cause: e,
      );
    } catch (e) {
      throw StorageException('AES-GCM decryption failed.', cause: e);
    }
  }

  static void _checkKey(Uint8List key) {
    if (key.length != keyLength) {
      throw StorageException(
        'An AES-256 key is $keyLength bytes, not ${key.length}.',
      );
    }
  }
}
