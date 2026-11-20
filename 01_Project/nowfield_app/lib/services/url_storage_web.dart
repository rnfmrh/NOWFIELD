// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

const String _storageKey = 'nowfield_api_base_url';

String? _extractApiParamFromLocation() {
  try {
    final uri = Uri.parse(html.window.location.href);
    final direct = uri.queryParameters['api'] ??
        uri.queryParameters['api_url'] ??
        uri.queryParameters['server'];
    if (direct != null && direct.trim().isNotEmpty) {
      return direct.trim();
    }
    // Also support hash-based parameters like /#/?api=https://...
    final frag = uri.fragment;
    if (frag.contains('?')) {
      final fragUri = Uri.tryParse(frag);
      final fromFrag = fragUri?.queryParameters['api'] ??
          fragUri?.queryParameters['api_url'] ??
          fragUri?.queryParameters['server'];
      if (fromFrag != null && fromFrag.trim().isNotEmpty) {
        return fromFrag.trim();
      }
    }
  } catch (_) {}
  return null;
}

String? loadSavedBaseUrl() {
  // 1. Highest priority: URL query parameter (?api=https://...)
  final fromQuery = _extractApiParamFromLocation();
  if (fromQuery != null && fromQuery.isNotEmpty) {
    final normalized = fromQuery.endsWith('/')
        ? fromQuery.substring(0, fromQuery.length - 1)
        : fromQuery;
    saveBaseUrlToStorage(normalized);
    return normalized;
  }

  // 2. Saved localStorage / sessionStorage / Cookie
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
