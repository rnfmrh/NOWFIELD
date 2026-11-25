String? _memoryUrl;

String? loadSavedBaseUrl() => _memoryUrl;

void saveBaseUrlToStorage(String url) {
  _memoryUrl = url;
}

Future<Map<String, double>?> getCurrentBrowserPosition() async => null;

Future<String?> reverseGeocodeWithKakaoJs(double lat, double lng) async => null;
