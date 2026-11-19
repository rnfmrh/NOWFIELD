String? _memoryUrl;

String? loadSavedBaseUrl() => _memoryUrl;

void saveBaseUrlToStorage(String url) {
  _memoryUrl = url;
}
