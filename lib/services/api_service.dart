import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static const String defaultBaseUrl = 'https://nothing-cash-spoke-burns.trycloudflare.com';

  static final ValueNotifier<String> baseUrlNotifier =
      ValueNotifier<String>(defaultBaseUrl);

  static String get baseUrl => baseUrlNotifier.value;

  static void setBaseUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    final normalized = trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
    baseUrlNotifier.value = normalized;
  }

  /// Active logged-in user state (defaults to @seoul_walker per Spec #1 auto-login)
  static final ValueNotifier<Map<String, dynamic>?> currentUserNotifier =
      ValueNotifier<Map<String, dynamic>?>({
    'id': 'u_seoul_walker',
    'username': '@seoul_walker',
    'country': 'KR',
  });

  static Map<String, dynamic>? get currentUser => currentUserNotifier.value;
  static String get currentUserId => currentUser?['id']?.toString() ?? 'u_seoul_walker';
  static String get currentUsername => currentUser?['username']?.toString() ?? '@seoul_walker';

  static void loginAs(Map<String, dynamic> user) {
    currentUserNotifier.value = Map<String, dynamic>.from(user);
  }

  static void logout() {
    currentUserNotifier.value = null;
  }

  /// Spec #2, #32, #50: Blocked users & Not Interested videos state
  static final ValueNotifier<Set<String>> blockedUsersNotifier = ValueNotifier<Set<String>>({});
  static final ValueNotifier<Set<String>> notInterestedVideoIdsNotifier = ValueNotifier<Set<String>>({});
  static final ValueNotifier<int> feedFilterVersionNotifier = ValueNotifier<int>(0);

  /// Spec #50 Settings preferences
  static final ValueNotifier<String> defaultCaptionLangNotifier = ValueNotifier<String>('원문');
  static final ValueNotifier<String> appLanguageNotifier = ValueNotifier<String>('한국어');
  static final ValueNotifier<bool> notificationsEnabledNotifier = ValueNotifier<bool>(true);

  static void blockUser(String usernameOrId) {
    final normalized = usernameOrId.trim();
    if (normalized.isEmpty) return;
    final next = Set<String>.from(blockedUsersNotifier.value)..add(normalized);
    blockedUsersNotifier.value = next;
    feedFilterVersionNotifier.value++;
  }

  static void unblockUser(String usernameOrId) {
    final next = Set<String>.from(blockedUsersNotifier.value)..remove(usernameOrId.trim());
    blockedUsersNotifier.value = next;
    feedFilterVersionNotifier.value++;
  }

  static bool isUserBlocked(String? username, String? userId) {
    final blocked = blockedUsersNotifier.value;
    if (username != null && blocked.contains(username)) return true;
    if (userId != null && blocked.contains(userId)) return true;
    return false;
  }

  static void markNotInterested(String videoId) {
    if (videoId.isEmpty) return;
    final next = Set<String>.from(notInterestedVideoIdsNotifier.value)..add(videoId);
    notInterestedVideoIdsNotifier.value = next;
    feedFilterVersionNotifier.value++;
  }

  /// Spec #1 & #50: Delete Account
  static Future<bool> deleteCurrentAccount() async {
    final uid = currentUserId;
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/users/${Uri.encodeComponent(uid)}'),
      );
      logout();
      return response.statusCode == 200;
    } catch (_) {
      logout();
      return true;
    }
  }

  /// Spec #16 & #46: Fetch dynamic Alerts
  static Future<List<Map<String, dynamic>>> getAlerts() async {
    try {
      final uid = Uri.encodeComponent(currentUserId);
      final response = await http.get(Uri.parse('$baseUrl/alerts?user_id=$uid'));
      if (response.statusCode == 200) {
        final decoded = json.decode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic> && decoded['alerts'] is List) {
          return (decoded['alerts'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
    } catch (_) {}
    return [
      {
        'id': 'alt_spec_social',
        'category': 'Social',
        'title': '@apgujeong_now님이 회원님을 팔로우하기 시작했습니다',
        'subtitle': '압구정·신사 지역 현장 크리에이터',
        'target_user_id': 'u_apgu_now',
        'target_username': '@apgujeong_now',
        'created_at': '2분 전',
      },
      {
        'id': 'alt_spec_mod_review',
        'category': 'Moderation',
        'title': '영상이 임시 비공개로 전환되었습니다',
        'subtitle': '해당 영상에 다수의 신고가 접수되었습니다 · [ 재검토 요청 ]',
        'video_id': 'v_sinsa_1',
        'video_title': '신사동 가로수길 카페 앞 실시간',
        'reason': '해당 영상에 대해 다수의 신고가 접수되어 확인 중입니다.',
        'created_at': '18분 전',
      },
      {
        'id': 'alt_spec_license',
        'category': 'License',
        'title': '내 영상 라이선스가 판매되었습니다 · 판매가 ₩10,000',
        'subtitle': '표준 상업 라이선스 · 크리에이터 80% 정산 (₩6,800 ~ ₩8,000)',
        'video_id': 'v_sinsa_1',
        'created_at': '1시간 전',
      },
      {
        'id': 'alt_spec_earnings',
        'category': 'Earnings',
        'title': '이번 달 크리에이터 수익 정산이 확정되었습니다',
        'subtitle': '크리에이터 풀 (광고 순수익 30%) 및 라이선스 정산 내역을 확인하세요.',
        'created_at': '1일 전',
      },
    ];
  }

  /// Fetch full user profile summary (uploaded videos, licensed videos, stats)
  static Future<Map<String, dynamic>> getUserProfile([String? userId]) async {
    final targetId = Uri.encodeComponent(userId ?? currentUserId);
    final viewerId = Uri.encodeComponent(currentUserId);
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/users/$targetId/profile?viewer_id=$viewerId'),
      );
      if (response.statusCode == 200) {
        final decoded = json.decode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      }
    } catch (_) {}
    final fallbackVideos = [
      {
        'id': 'v_sinsa_1',
        'title': '신사동 가로수길 카페 앞 실시간',
        'subtitle': '주말 오후 신사동 가로수길 메인 도로에 인파가 몰려 활기찬 분위기입니다.',
        'uploader_id': 'u_seoul_walker',
        'uploader_name': '@seoul_walker',
        'location_name': '서울 강남구 신사동',
        'video_url': 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyBlazes.mp4',
        'thumbnail_url': 'https://picsum.photos/seed/sinsa1/600/900',
        'like_count': 24,
        'comment_count': 5,
        'license_price': 10000,
        'created_at': '5분 전',
      },
      {
        'id': 'v_apgu_1',
        'title': '압구정 현대백화점 앞 교통 정체',
        'subtitle': '현재 압구정 현대백화점 사거리 방향 차량 정체가 심합니다. 서행 운전하세요.',
        'uploader_id': 'u_apgu_now',
        'uploader_name': '@apgu_now',
        'location_name': '서울 강남구 압구정동',
        'video_url': 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
        'thumbnail_url': 'https://picsum.photos/seed/apgu1/600/900',
        'like_count': 18,
        'comment_count': 3,
        'license_price': 10000,
        'created_at': '12분 전',
      },
    ];
    return {
      'user': {
        'id': userId ?? currentUserId,
        'username': (userId != null && userId.startsWith('@')) ? userId : currentUsername,
        'country': 'KR',
      },
      'video_count': fallbackVideos.length,
      'follower_count': 128,
      'following_count': 42,
      'is_following': false,
      'total_license_sales': 3,
      'total_creator_revenue': 22000,
      'videos': fallbackVideos,
      'licensed_videos': [fallbackVideos.first],
    };
  }

  /// Toggle follow / unfollow user (Spec #2 & #15)
  static Future<Map<String, dynamic>> toggleFollow(String targetUserId) async {
    try {
      final encodedTarget = Uri.encodeComponent(targetUserId);
      final encodedFollower = Uri.encodeComponent(currentUserId);
      final response = await http.post(
        Uri.parse('$baseUrl/users/$encodedTarget/follow?follower_id=$encodedFollower'),
      );
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {};
  }

  /// Fetch all registered users for account switching
  static Future<List<Map<String, dynamic>>> getAllUsers() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/users'));
      if (response.statusCode == 200) {
        final decoded = json.decode(utf8.decode(response.bodyBytes)) as List<dynamic>;
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Create or login user by @username (Spec #1 & #25)
  static Future<Map<String, dynamic>> createOrLoginUser(
    String username, {
    String country = 'KR',
  }) async {
    try {
      final normalized = username.startsWith('@') ? username : '@$username';
      final response = await http.post(
        Uri.parse('$baseUrl/users'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': normalized,
          'country': country,
          'is_creator': true,
        }),
      );
      if (response.statusCode == 200) {
        final user = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        loginAs(user);
        return user;
      }
    } catch (_) {}
    return {};
  }

  /// Get nearby videos along with clustered pins (Spec Rule #8 & #9)
  static Future<Map<String, dynamic>> getNearbyData(
    double lat,
    double lng, {
    double radiusKm = 3.0,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/videos/nearby?lat=$lat&lng=$lng&radius_km=$radiusKm'),
      );
      if (response.statusCode == 200) {
        final decoded = json.decode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      }
    } catch (_) {
      // Graceful fallback when backend is offline
    }
    return {};
  }

  /// Compatibility helper for existing callers
  static Future<List<dynamic>> getNearbyVideos(double lat, double lng) async {
    final data = await getNearbyData(lat, lng);
    if (data.containsKey('raw_videos')) {
      return data['raw_videos'] as List<dynamic>;
    }
    return [];
  }

  /// Fetch vertical feed videos (supports Spec #6 tabs: recommended, latest, following)
  static Future<List<dynamic>> getFeedVideos({String tab = 'recommended'}) async {
    try {
      final viewer = currentUser != null ? '&viewer_id=${Uri.encodeComponent(currentUserId)}' : '';
      final response = await http.get(
        Uri.parse('$baseUrl/videos/feed?tab=${Uri.encodeComponent(tab)}$viewer'),
      );
      if (response.statusCode == 200) {
        final raw = json.decode(utf8.decode(response.bodyBytes)) as List<dynamic>;
        return raw.where((item) {
          if (item is Map) {
            final vid = item['id']?.toString() ?? '';
            final uname = item['uploader_name']?.toString();
            final uid = item['uploader_id']?.toString();
            if (notInterestedVideoIdsNotifier.value.contains(vid)) return false;
            if (isUserBlocked(uname, uid)) return false;
          }
          return true;
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Unified Search (Spec #14: Username, Video Title, Location, Category)
  static Future<Map<String, dynamic>> searchUnified(
    String query, {
    String? category,
  }) async {
    try {
      final qParam = Uri.encodeComponent(query);
      final catParam = (category != null && category.isNotEmpty && category != '전체')
          ? '&category=${Uri.encodeComponent(category)}'
          : '';
      final response = await http.get(
        Uri.parse('$baseUrl/search?q=$qParam$catParam'),
      );
      if (response.statusCode == 200) {
        final decoded = json.decode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      }
    } catch (_) {}
    final qLower = query.trim().toLowerCase();
    final sampleVideos = [
      {
        'id': 'v_sinsa_1',
        'title': '신사동 가로수길 카페 앞 실시간',
        'subtitle': '주말 오후 신사동 가로수길 메인 도로에 인파가 몰려 활기찬 분위기입니다.',
        'uploader_id': 'u_seoul_walker',
        'uploader_name': '@seoul_walker',
        'location_name': '서울 강남구 신사동',
        'video_url': 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyBlazes.mp4',
        'thumbnail_url': 'https://picsum.photos/seed/sinsa1/600/900',
        'like_count': 24,
        'comment_count': 5,
        'created_at': '5분 전',
      },
      {
        'id': 'v_apgu_1',
        'title': '압구정 현대백화점 앞 교통 정체',
        'subtitle': '현재 압구정 현대백화점 사거리 방향 차량 정체가 심합니다.',
        'uploader_id': 'u_apgu_now',
        'uploader_name': '@apgu_now',
        'location_name': '서울 강남구 압구정동',
        'video_url': 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
        'thumbnail_url': 'https://picsum.photos/seed/apgu1/600/900',
        'like_count': 18,
        'comment_count': 3,
        'created_at': '12분 전',
      },
    ].where((v) {
      if (qLower.isEmpty) return true;
      return v['title']!.toString().toLowerCase().contains(qLower) ||
          v['location_name']!.toString().toLowerCase().contains(qLower) ||
          v['uploader_name']!.toString().toLowerCase().contains(qLower);
    }).toList();

    final sampleUsers = [
      {'id': 'u_seoul_walker', 'username': '@seoul_walker', 'country': 'KR'},
      {'id': 'u_apgu_now', 'username': '@apgu_now', 'country': 'KR'},
      {'id': 'u_commuter', 'username': '@commuter', 'country': 'KR'},
    ].where((u) {
      if (qLower.isEmpty) return true;
      return u['username']!.toLowerCase().contains(qLower);
    }).toList();

    return {
      'videos': sampleVideos,
      'users': sampleUsers,
      'places': qLower.isEmpty
          ? []
          : [
              {
                'place_name': query.trim(),
                'road_address_name': '서울 강남구 신사동',
                'address_name': '서울 강남구 신사동',
                'category_group_name': '지역/장소',
              }
            ],
    };
  }

  /// Purchase video license (80:20 split)
  static Future<Map<String, dynamic>> purchaseLicense(String videoId) async {
    try {
      final buyerId = currentUserId;
      final response = await http.post(
        Uri.parse('$baseUrl/videos/$videoId/license?buyer_id=$buyerId'),
      );
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {};
  }

  /// Toggle video like (Spec #15 & #27: Like / Cancel Like)
  static Future<Map<String, dynamic>> toggleLike(
    String videoId, {
    String? userId,
  }) async {
    try {
      final uid = userId ?? currentUserId;
      final response = await http.post(
        Uri.parse('$baseUrl/videos/$videoId/like?user_id=$uid'),
      );
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {};
  }

  /// Fetch comments for a video (Spec #15)
  static Future<List<Map<String, dynamic>>> getComments(String videoId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/videos/$videoId/comments'),
      );
      if (response.statusCode == 200) {
        final decoded = json.decode(utf8.decode(response.bodyBytes)) as List<dynamic>;
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Post a new comment on a video (Spec #15)
  static Future<Map<String, dynamic>> postComment(
    String videoId,
    String content, {
    String? userId,
    String? username,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/videos/$videoId/comments'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'user_id': userId ?? currentUserId,
          'username': username ?? currentUsername,
          'content': content,
        }),
      );
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {};
  }

  /// Report a video or comment (Spec #5.2 & #39)
  static Future<Map<String, dynamic>> reportContent({
    required String videoId,
    required String reason,
    String? details,
    String? reporterId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/reports'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'video_id': videoId,
          'reporter_id': reporterId ?? currentUserId,
          'reason': reason,
          'details': details,
        }),
      );
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {};
  }

  /// Upload recorded video file with metadata (One Take & One Minute pipeline)
  static Future<Map<String, dynamic>> uploadVideo({
    required List<int> videoBytes,
    required String filename,
    required String title,
    String? subtitle,
    required double latitude,
    required double longitude,
    String? uploaderId,
    bool licenseEnabled = true,
    int licensePrice = 10000,
    int? recordedDuration,
    String? captureSessionId,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/videos/upload');
      final request = http.MultipartRequest('POST', uri);

      request.fields['title'] = title;
      if (subtitle != null && subtitle.isNotEmpty) {
        request.fields['subtitle'] = subtitle;
      }
      request.fields['latitude'] = latitude.toString();
      request.fields['longitude'] = longitude.toString();
      request.fields['uploader_id'] = uploaderId ?? currentUserId;
      request.fields['license_enabled'] = licenseEnabled.toString();
      request.fields['license_price'] = (licenseEnabled ? licensePrice : 0).toString();
      if (recordedDuration != null) {
        request.fields['recorded_duration'] = recordedDuration.toString();
      }
      if (captureSessionId != null) {
        request.fields['capture_session_id'] = captureSessionId;
      }

      final multipartFile = http.MultipartFile.fromBytes(
        'video_file',
        videoBytes,
        filename: filename,
      );
      request.files.add(multipartFile);

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      } else {
        try {
          final err = json.decode(utf8.decode(response.bodyBytes));
          return {
            'error': err['detail'] ?? 'Upload failed (${response.statusCode})',
            'statusCode': response.statusCode,
          };
        } catch (_) {
          return {
            'error': 'Upload failed with status code ${response.statusCode}',
            'statusCode': response.statusCode,
          };
        }
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Helper to resolve absolute media URL
  static String resolveMediaUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    if (path.startsWith('/')) return '$baseUrl$path';
    return '$baseUrl/$path';
  }
}
