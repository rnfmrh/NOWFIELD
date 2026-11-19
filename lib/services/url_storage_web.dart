// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

const String _storageKey = 'nowfield_api_base_url';

String? loadSavedBaseUrl() {
  try {
    final fromLocal = html.window.localStorage[_storageKey]?.trim();
    if (fromLocal != null && fromLocal.isNotEmpty) {
      return fromLocal;
    }
  } catch (_) {}

  try {
    final fromSession = html.window.sessionStorage[_storageKey]?.trim();
    if (fromSession != null && fromSession.isNotEmpty) {
      return fromSession;
    }
  } catch (_) {}

  try {
    final cookieStr = html.document.cookie ?? '';
    for (final part in cookieStr.split(';')) {
      final kv = part.trim().split('=');
      if (kv.length == 2 && kv[0].trim() == _storageKey) {
        final decoded = Uri.decodeComponent(kv[1].trim());
        if (decoded.isNotEmpty) {
          return decoded;
        }
      }
    }
  } catch (_) {}

  return null;
}

void saveBaseUrlToStorage(String url) {
  try {
    html.window.localStorage[_storageKey] = url;
  } catch (_) {}

  try {
    html.window.sessionStorage[_storageKey] = url;
  } catch (_) {}

  try {
    final encoded = Uri.encodeComponent(url);
    html.document.cookie =
        '$_storageKey=$encoded; path=/; max-age=31536000; SameSite=Lax';
  } catch (_) {}
}
