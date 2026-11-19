import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show internal;
import 'package:web/web.dart' as web;

import '../core/core.dart';

/// AES-256-GCM through the browser's Web Crypto API, for
/// `WebSecureStorage`: the browser's own engine, no Dart crypto library in
/// the bundle, and the same code on JS and WebAssembly builds.
///
/// Keys are `CryptoKey`s made non-extractable: scripts on the page can use
/// one to encrypt and decrypt, but can't read its bytes.
@internal
final class WebAesGcmCipher {
  /// The cipher; it holds no state.
  const WebAesGcmCipher();

  /// Nonce length in bytes.
  static const int nonceLength = 12;

  /// Raw key length in bytes.
  static const int keyLength = 32;

  static web.SubtleCrypto get _subtle => web.window.crypto.subtle;

  static JSArray<JSString> get _usages =>
      <JSString>['encrypt'.toJS, 'decrypt'.toJS].toJS;

  /// [length] cryptographically random bytes.
  static Uint8List randomBytes(int length) {
    final bytes = Uint8List(length).toJS;
    web.window.crypto.getRandomValues(bytes);
    return bytes.toDart;
  }

  /// A new random non-extractable AES-256-GCM key.
  static Future<web.CryptoKey> generateKey() async {
    try {
      final key = await _subtle
          .generateKey(
            _AesKeyGenParams(name: 'AES-GCM', length: 256),
            false,
            _usages,
          )
          .toDart;
      return key as web.CryptoKey;
    } catch (e) {
      throw StorageException('Could not make an AES-GCM key.', cause: e);
    }
  }

  /// [raw] (32 bytes) as a non-extractable AES-256-GCM key.
  static Future<web.CryptoKey> importRawKey(Uint8List raw) async {
    if (raw.length != keyLength) {
      throw StorageException(
        'An AES-256 key is $keyLength bytes, not ${raw.length}.',
      );
    }
    try {
      return await _subtle
          .importKey(
            'raw',
            raw.toJS,
            _AesAlgorithm(name: 'AES-GCM'),
            false,
            _usages,
          )
          .toDart;
    } catch (e) {
      throw StorageException('Could not import an AES-GCM key.', cause: e);
    }
  }

  /// Encrypts [plaintext] under [key] with a fresh random nonce, binding
  /// [aad] to it. Returns the nonce and `ciphertext || tag`.
  Future<({Uint8List nonce, Uint8List ciphertext})> seal(
    web.CryptoKey key,
    Uint8List plaintext,
    Uint8List aad,
  ) async {
    final nonce = randomBytes(nonceLength);
    try {
      final result = await _subtle
          .encrypt(
            _AesGcmParams(
              name: 'AES-GCM',
              iv: nonce.toJS,
              additionalData: aad.toJS,
            ),
            key,
            plaintext.toJS,
          )
          .toDart;
      return (
        nonce: nonce,
        ciphertext: (result as JSArrayBuffer).toDart.asUint8List(),
      );
    } catch (e) {
      throw StorageException('AES-GCM encryption failed.', cause: e);
    }
  }

  /// Decrypts [ciphertext] (`ciphertext || tag`) sealed under [key] with
  /// [nonce] and [aad].
  ///
  /// Throws a [StorageException] when the tag doesn't match: the value, its
  /// nonce, the key or the additional data is not what it was sealed with.
  Future<Uint8List> open(
    web.CryptoKey key,
    Uint8List nonce,
    Uint8List ciphertext,
    Uint8List aad,
  ) async {
    if (nonce.length != nonceLength) {
      throw StorageException(
        'An AES-GCM nonce is $nonceLength bytes, not ${nonce.length}.',
      );
    }
    try {
      final result = await _subtle
          .decrypt(
            _AesGcmParams(
              name: 'AES-GCM',
              iv: nonce.toJS,
              additionalData: aad.toJS,
            ),
            key,
            ciphertext.toJS,
          )
          .toDart;
      return (result as JSArrayBuffer).toDart.asUint8List();
    } catch (e) {
      throw StorageException(
        'AES-GCM authentication failed: the value is damaged, was changed, '
        'or was sealed with another key.',
        cause: e,
      );
    }
  }
}

/// `AesGcmParams`: the nonce and the additional authenticated data.
extension type _AesGcmParams._(JSObject _) implements JSObject {
  external factory _AesGcmParams({
    required String name,
    required JSUint8Array iv,
    required JSUint8Array additionalData,
  });
}

/// `AesKeyGenParams`: the key length in bits.
extension type _AesKeyGenParams._(JSObject _) implements JSObject {
  external factory _AesKeyGenParams({
    required String name,
    required int length,
  });
}

/// An algorithm named and nothing else, for `importKey`.
extension type _AesAlgorithm._(JSObject _) implements JSObject {
  external factory _AesAlgorithm({required String name});
}
