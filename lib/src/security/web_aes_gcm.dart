import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../models/storage_exception.dart';

/// AES-256-GCM cipher backed by the browser's native Web Crypto API.
///
/// Used exclusively on web and WASM targets — the native path still uses
/// [AesGcmCipher] (pointycastle-based).  Advantages over a pure-Dart
/// implementation on web/WASM:
/// - Delegates to the browser's hardened, hardware-accelerated engine.
/// - Avoids shipping a large pure-Dart crypto library in the web bundle.
/// - Full WASM compatibility — no pure-Dart integer-math crypto needed.
///
/// All encryption/decryption methods are `async` because the Web Crypto
/// API is inherently promise-based.
class WebAesGcmCipher {
  static const int keyLength = 32; // bytes — 256-bit AES key
  static const int nonceLength = 12; // bytes — 96-bit GCM IV

  /// Encrypts [plaintext] and returns `ciphertext || 16-byte GCM auth tag`.
  Future<Uint8List> encrypt(
    web.CryptoKey key,
    Uint8List nonce,
    Uint8List plaintext,
  ) async {
    if (nonce.length != nonceLength) {
      throw StorageException(
        'AES-GCM nonce must be $nonceLength bytes, got ${nonce.length}.',
      );
    }
    try {
      final algorithm = _AesGcmParams(name: 'AES-GCM', iv: nonce.toJS);
      final result = await web.window.crypto.subtle
          .encrypt(algorithm, key, plaintext.toJS)
          .toDart;
      return (result as JSArrayBuffer).toDart.asUint8List();
    } on StorageException {
      rethrow;
    } catch (e) {
      throw StorageException('AES-GCM encryption failed.', cause: e);
    }
  }

  /// Decrypts [ciphertextWithTag] (`ciphertext || 16-byte GCM auth tag`).
  ///
  /// Throws [StorageException] if authentication fails — the data has been
  /// tampered with or the key/nonce is wrong.
  Future<Uint8List> decrypt(
    web.CryptoKey key,
    Uint8List nonce,
    Uint8List ciphertextWithTag,
  ) async {
    if (nonce.length != nonceLength) {
      throw StorageException(
        'AES-GCM nonce must be $nonceLength bytes, got ${nonce.length}.',
      );
    }
    try {
      final algorithm = _AesGcmParams(name: 'AES-GCM', iv: nonce.toJS);
      final result = await web.window.crypto.subtle
          .decrypt(algorithm, key, ciphertextWithTag.toJS)
          .toDart;
      return (result as JSArrayBuffer).toDart.asUint8List();
    } on StorageException {
      rethrow;
    } catch (e) {
      throw StorageException(
        'AES-GCM authentication failed: ciphertext may be corrupt or tampered.',
        cause: e,
      );
    }
  }

  /// Imports raw [keyBytes] (32 bytes) as an opaque [web.CryptoKey] for
  /// use with [encrypt] and [decrypt].
  static Future<web.CryptoKey> importKey(Uint8List keyBytes) async {
    if (keyBytes.length != keyLength) {
      throw StorageException(
        'AES-GCM key must be $keyLength bytes, got ${keyBytes.length}.',
      );
    }
    try {
      final algorithm = _AesImportParams(name: 'AES-GCM');
      final usages = <JSString>['encrypt'.toJS, 'decrypt'.toJS].toJS;
      final result = await web.window.crypto.subtle
          .importKey('raw', keyBytes.toJS, algorithm, false, usages)
          .toDart;
      return result;
    } on StorageException {
      rethrow;
    } catch (e) {
      throw StorageException('Failed to import AES-GCM key.', cause: e);
    }
  }

  /// Generates a cryptographically-random 12-byte nonce via
  /// `window.crypto.getRandomValues`.
  static Uint8List randomNonce() {
    final jsNonce = Uint8List(nonceLength).toJS;
    web.window.crypto.getRandomValues(jsNonce);
    return jsNonce.toDart;
  }

  /// Generates a cryptographically-random 32-byte AES-256 master key via
  /// `window.crypto.getRandomValues`.
  static Uint8List generateKeyBytes() {
    final jsKey = Uint8List(keyLength).toJS;
    web.window.crypto.getRandomValues(jsKey);
    return jsKey.toDart;
  }
}

// ---------------------------------------------------------------------------
// Private JS-interop extension types for algorithm parameters
// ---------------------------------------------------------------------------

/// AES-GCM algorithm parameters passed to `subtle.encrypt` / `subtle.decrypt`.
extension type _AesGcmParams._(JSObject _) implements JSObject {
  external factory _AesGcmParams({
    required String name,
    required JSUint8Array iv,
  });
}

/// Algorithm identifier passed to `subtle.importKey` for an AES key.
extension type _AesImportParams._(JSObject _) implements JSObject {
  external factory _AesImportParams({required String name});
}
