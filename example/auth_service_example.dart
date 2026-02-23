/// Recipe: Building an auth-token service on top of [JustSecureStorage].
///
/// Auth tokens (OAuth access + refresh) are highly sensitive — they must
/// never be stored in plain text.  [EncryptedFileStorage] encrypts each value
/// with AES-256-GCM so tokens are unreadable even if the device's file system
/// is accessed directly.
library;

import 'dart:async';

import 'package:just_storage/just_storage.dart';

// ---------------------------------------------------------------------------
// Domain model
// ---------------------------------------------------------------------------

class OAuthTokens {
  const OAuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.username,
  });

  factory OAuthTokens.fromJson(Map<String, dynamic> json) => OAuthTokens(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
        username: json['username'] as String,
      );

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String username;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt.toIso8601String(),
        'username': username,
      };
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Stores and retrieves OAuth tokens using [JustSecureStorage].
///
/// All tokens are AES-256-GCM encrypted on disk.  This service should be the
/// **only** place in the app that reads or writes token data — nothing else
/// should hold a reference to the storage instance directly.
class AuthTokenService {
  AuthTokenService(this._secure);

  final JustSecureStorage _secure;

  static const _tokensKey = 'oauth_tokens';

  // --------------------------------------------------------------------------
  // Token lifecycle
  // --------------------------------------------------------------------------

  /// Saves [tokens] to the encrypted store.  Call this after a successful
  /// OAuth code exchange or token refresh.
  Future<void> saveTokens(OAuthTokens tokens) =>
      _secure.writeJson(_tokensKey, tokens, (t) => t.toJson());

  /// Returns the stored tokens, or `null` if the user has never authenticated
  /// or has been logged out.
  Future<OAuthTokens?> loadTokens() =>
      _secure.readJson(_tokensKey, OAuthTokens.fromJson);

  /// Returns `true` when tokens exist and the access token has not expired.
  Future<bool> isAuthenticated() async {
    final tokens = await loadTokens();
    return tokens != null && !tokens.isExpired;
  }

  /// Returns the access token string directly, for use in HTTP headers.
  /// Returns `null` if unauthenticated.
  Future<String?> accessToken() async => (await loadTokens())?.accessToken;

  /// Deletes all stored tokens.  Call on logout.
  Future<void> logout() => _secure.delete(_tokensKey);

  // --------------------------------------------------------------------------
  // Reactive auth-state stream
  // --------------------------------------------------------------------------

  /// Emits `true` when authenticated, `false` after logout / token deletion.
  ///
  /// Subscribing immediately gets the current auth state.
  Stream<bool> watchAuthState() =>
      _secure.watch(_tokensKey).asyncMap((raw) => isAuthenticated());

  // --------------------------------------------------------------------------
  // Additional secure fields (individual secrets)
  // --------------------------------------------------------------------------

  /// Stores a single string secret under its own key (e.g. a PKCE verifier,
  /// device ID, or derived key material).
  Future<void> storeSecret(String key, String value) =>
      _secure.write(key, value);

  Future<String?> readSecret(String key) => _secure.read(key);

  Future<void> deleteSecret(String key) => _secure.delete(key);

  /// Full wipe: removes **all** entries from the secure store — tokens,
  /// individual secrets, everything.  Use only for "reset / factory wipe".
  Future<void> wipeAll() => _secure.clear();
}

// ---------------------------------------------------------------------------
// Usage demonstration
// ---------------------------------------------------------------------------

Future<void> runAuthExample(JustSecureStorage secure) async {
  final service = AuthTokenService(secure);

  // Should be unauthenticated initially.
  assert(!await service.isAuthenticated());

  // Simulate successful OAuth code exchange.
  await service.saveTokens(
    OAuthTokens(
      accessToken: 'eyJhbGciOiJSUzI1NiJ9.access',
      refreshToken: 'eyJhbGciOiJSUzI1NiJ9.refresh',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      username: 'Magnus',
    ),
  );

  assert(await service.isAuthenticated());
  assert(await service.accessToken() != null);

  // Token is transparently re-read from the encrypted store.
  final loaded = await service.loadTokens();
  assert(loaded?.username == 'Magnus');

  // Store a supplementary PKCE code verifier.
  await service.storeSecret(
      'pkce_verifier', 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1g');
  assert(await service.readSecret('pkce_verifier') != null);
  await service.deleteSecret('pkce_verifier');

  // Logout — tokens gone.
  await service.logout();
  assert(!await service.isAuthenticated());
  assert(await service.loadTokens() == null);
}
