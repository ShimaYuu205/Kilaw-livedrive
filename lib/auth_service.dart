import 'dart:io';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Login Google dengan OAuth (BUKAN API key + Apps Script lagi).
/// - Android : google_sign_in
/// - Desktop : loopback OAuth, refresh token disimpan terenkripsi
class AuthService {
  // Isi dari Google Cloud Console (lihat README).
  // Untuk desktop: OAuth client type "Desktop app".
  static const desktopClientId = 'ISI_CLIENT_ID_DESKTOP.apps.googleusercontent.com';
  static const desktopClientSecret = 'ISI_CLIENT_SECRET_DESKTOP';

  static const _scopes = [drive.DriveApi.driveScope];
  static const _store = FlutterSecureStorage();
  static const _kRefresh = 'refresh_token';

  static final _clientId = ClientId(desktopClientId, desktopClientSecret);

  /// Mengembalikan http.Client yang sudah terautentikasi, atau null jika batal.
  Future<http.Client?> signIn() async {
    if (Platform.isAndroid || Platform.isIOS) return _signInMobile();
    return _signInDesktop();
  }

  Future<void> signOut() async {
    await _store.delete(key: _kRefresh);
    if (Platform.isAndroid) await GoogleSignIn().signOut();
  }

  Future<http.Client?> _signInMobile() async {
    final gs = GoogleSignIn(scopes: _scopes);
    final acc = await gs.signInSilently() ?? await gs.signIn();
    if (acc == null) return null;
    return gs.authenticatedClient();
  }

  Future<http.Client?> _signInDesktop() async {
    final saved = await _store.read(key: _kRefresh);
    if (saved != null) {
      // Token kedaluwarsa sengaja diset lampau -> otomatis di-refresh.
      final creds = AccessCredentials(
        AccessToken('Bearer', '', DateTime.utc(1970)),
        saved,
        _scopes,
      );
      return autoRefreshingClient(_clientId, creds, http.Client());
    }
    final client = await clientViaUserConsent(
      _clientId,
      _scopes,
      (url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    );
    final refresh = client.credentials.refreshToken;
    if (refresh != null) await _store.write(key: _kRefresh, value: refresh);
    return client;
  }
}
