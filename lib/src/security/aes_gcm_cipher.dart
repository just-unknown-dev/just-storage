import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../models/storage_exception.dart';

/// Low-level AES-256-GCM authenticated encryption / decryption.
///
/// * Key length : 256 bits (32 bytes)
/// * Nonce length : 96 bits (12 bytes) — the recommended GCM IV length
/// * Auth-tag length: 128 bits (16 bytes)
///
/// GCM provides **both** confidentiality and integrity.  Any modification to
/// the ciphertext (including the stored key file) will cause [decrypt] to
/// throw a [StorageException] before any plaintext is returned.
class AesGcmCipher {
  static const int keyLength = 32; // bytes
  static const int nonceLength = 12; // bytes
  static const int tagLengthBits = 128;

  /// Encrypts [plaintext] and returns `ciphertext || 16-byte GCM auth tag`.
  ///
  /// A fresh random nonce is **not** generated here; callers must supply one
  /// (see [randomNonce]). Separating nonce generation lets callers store the
  /// nonce alongside the ciphertext.
  Uint8List encrypt(Uint8List key, Uint8List nonce, Uint8List plaintext) {
    assert(key.length == keyLength, 'Key must be $keyLength bytes.');
    assert(nonce.length == nonceLength, 'Nonce must be $nonceLength bytes.');

    try {
      final cipher = GCMBlockCipher(AESEngine());
      cipher.init(
        true, // forEncryption
        AEADParameters(
          KeyParameter(key),
          tagLengthBits,
          nonce,
          Uint8List(0), // no additional authenticated data
        ),
      );
      return cipher.process(plaintext);
    } catch (e) {
      throw StorageException('AES-GCM encryption failed.', cause: e);
    }
  }

  /// Decrypts [ciphertextWithTag] (ciphertext concatenated with 16-byte GCM
  /// auth tag) and returns the original plaintext.
  ///
  /// Throws [StorageException] if the GCM tag does not match — indicating that
  /// the ciphertext, the nonce, or the key has been tampered with.
  Uint8List decrypt(
      Uint8List key, Uint8List nonce, Uint8List ciphertextWithTag) {
    assert(key.length == keyLength, 'Key must be $keyLength bytes.');
    assert(nonce.length == nonceLength, 'Nonce must be $nonceLength bytes.');

    try {
      final cipher = GCMBlockCipher(AESEngine());
      cipher.init(
        false, // forDecryption
        AEADParameters(
          KeyParameter(key),
          tagLengthBits,
          nonce,
          Uint8List(0),
        ),
      );
      return cipher.process(ciphertextWithTag);
    } on InvalidCipherTextException catch (e) {
      throw StorageException(
        'AES-GCM authentication failed: ciphertext may be corrupt or tampered.',
        cause: e,
      );
    } catch (e) {
      throw StorageException('AES-GCM decryption failed.', cause: e);
    }
  }

  /// Generates a cryptographically-random 12-byte nonce.
  ///
  /// **Never reuse** a nonce with the same key.  Call this once per
  /// [encrypt] call.
  static Uint8List randomNonce() {
    final rng = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(nonceLength, (_) => rng.nextInt(256)),
    );
  }
}
