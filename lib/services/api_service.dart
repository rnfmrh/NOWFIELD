import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Use 10.0.2.2 for Android emulator, localhost for iOS simulator
  static const String baseUrl = 'http://127.0.0.1:8000';

  static Future<List<dynamic>> getNearbyVideos(double lat, double lng) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/videos/nearby?lat=$lat&lng=$lng&radius_km=1.0'),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print('Error fetching nearby videos: $e');
    }
    return [];
  }
}
