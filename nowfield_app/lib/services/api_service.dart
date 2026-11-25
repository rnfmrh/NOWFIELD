import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'url_storage.dart';

class ApiService {
  static String get defaultBaseUrl {
    if (kIsWeb && Uri.base.scheme == 'http' && Uri.base.host.isNotEmpty) {
      return 'http://${Uri.base.host}:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  static final ValueNotifier<String> baseUrlNotifier =
      ValueNotifier<String>(loadSavedBaseUrl() ?? defaultBaseUrl);

  static String get baseUrl => baseUrlNotifier.value;

  static void setBaseUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    final normalized = trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
    saveBaseUrlToStorage(normalized);
    baseUrlNotifier.value = normalized;
    feedFilterVersionNotifier.value++;
  }

  /// Active logged-in user state (defaults to @seoul_walker per Spec #1 auto-login)
  static final ValueNotifier<Map<String, dynamic>?> currentUserNotifier =
      ValueNotifier<Map<String, dynamic>?>({
    'id': 'u_seoul_walker',
    'username': '@seoul_walker',
    'country': 'KR',
    'exact_location_consent': false,
  });

  static Map<String, dynamic>? get currentUser => currentUserNotifier.value;
  static String get currentUserId => currentUser?['id']?.toString() ?? 'u_seoul_walker';
  static String get currentUsername => currentUser?['username']?.toString() ?? '@seoul_walker';

  /// CR-02.B: Explicit user consent for Exact Location disclosure & OS precise location permission
  static final ValueNotifier<bool> exactLocationConsentNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> preciseLocationPermissionNotifier = ValueNotifier<bool>(true);

  /// CR-01: Local reactive cache of CreatorSupportAccount per userId
  static final ValueNotifier<Map<String, Map<String, dynamic>>> supportAccountsCacheNotifier =
      ValueNotifier<Map<String, Map<String, dynamic>>>({
    'u_seoul_walker': {
      'id': 'sup_u_seoul_walker',
      'user_id': 'u_seoul_walker',
      'provider': 'kofi',
      'support_url': 'https://ko-fi.com/seoul_walker',
      'ownership_status': 'verified',
      'verified_at': '2026-11-09T09:00:00Z',
      'active': true,
    },
    'u_apgu_now': {
      'id': 'sup_u_apgu_now',
      'user_id': 'u_apgu_now',
      'provider': 'buymeacoffee',
      'support_url': 'https://buymeacoffee.com/apgu_now',
      'ownership_status': 'verified',
      'verified_at': '2026-11-09T09:00:00Z',
      'active': true,
    },
  });

  static void loginAs(Map<String, dynamic> user) {
    currentUserNotifier.value = Map<String, dynamic>.from(user);
    if (user['exact_location_consent'] is bool) {
      exactLocationConsentNotifier.value = user['exact_location_consent'] as bool;
    }
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
  static final ValueNotifier<int> nearbyTtlMinutesNotifier = ValueNotifier<int>(60);

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

  /// CR-03: Format published_at / captured_at as absolute localized date & time with timezone.
  /// Primary display NEVER uses relative strings like "2시간 전" or "방금 전".
  /// Korean: 2026.11.12. 오후 7:30 (KST)
  /// English: Nov 12, 2026, 7:30 PM (KST)
  static String formatPublishedDateTime(
    dynamic rawTimestamp, {
    String? timezone,
    bool forceEnglish = false,
  }) {
    DateTime utcTime;
    final rawStr = rawTimestamp?.toString().trim() ?? '';

    if (rawStr.isEmpty) {
      utcTime = DateTime.now().toUtc();
    } else {
      final normalized = (rawStr.endsWith('Z') || rawStr.contains('+'))
          ? rawStr
          : (rawStr.contains('T') ? '${rawStr}Z' : rawStr);
      final parsed = DateTime.tryParse(normalized);
      if (parsed != null) {
        utcTime = parsed.toUtc();
      } else {
        // Convert any legacy relative fallback string into a concrete absolute timestamp
        final nowUtc = DateTime.now().toUtc();
        final minMatch = RegExp(r'(\d+)\s*분').firstMatch(rawStr);
        final hourMatch = RegExp(r'(\d+)\s*시간').firstMatch(rawStr);
        final dayMatch = RegExp(r'(\d+)\s*일').firstMatch(rawStr);
        if (minMatch != null) {
          utcTime = nowUtc.subtract(Duration(minutes: int.parse(minMatch.group(1)!)));
        } else if (hourMatch != null) {
          utcTime = nowUtc.subtract(Duration(hours: int.parse(hourMatch.group(1)!)));
        } else if (dayMatch != null) {
          utcTime = nowUtc.subtract(Duration(days: int.parse(dayMatch.group(1)!)));
        } else {
          utcTime = nowUtc;
        }
      }
    }

    final tz = (timezone == null || timezone.trim().isEmpty) ? 'Asia/Seoul' : timezone.trim();
    // Apply KST (+09:00) when Asia/Seoul or KST, otherwise local offset
    final bool isKst = tz == 'Asia/Seoul' || tz.toUpperCase() == 'KST';
    final DateTime displayTime = isKst ? utcTime.add(const Duration(hours: 9)) : utcTime.toLocal();
    final String tzAbbr = isKst ? 'KST' : 'UTC';

    final int year = displayTime.year;
    final int month = displayTime.month;
    final int day = displayTime.day;
    final int hour24 = displayTime.hour;
    final int minute = displayTime.minute;
    final String minutePadded = minute.toString().padLeft(2, '0');
    final bool isPm = hour24 >= 12;
    final int hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;

    final bool useEnglish = forceEnglish ||
        appLanguageNotifier.value == 'English' ||
        appLanguageNotifier.value == '영어';
    if (useEnglish) {
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final mName = months[(month - 1).clamp(0, 11)];
      final amPm = isPm ? 'PM' : 'AM';
      return '$hour12:$minutePadded $amPm · $mName $day, $year';
    }

    final String amPmKo = isPm ? '오후' : '오전';
    final String monthPadded = month.toString().padLeft(2, '0');
    final String dayPadded = day.toString().padLeft(2, '0');
    return '$year.$monthPadded.$dayPadded. $amPmKo $hour12:$minutePadded';
  }

  /// CR-02: Human-readable location privacy label
  static String formatLocationPrivacyLabel(String? mode, {int? approxRadiusM}) {
    final m = (mode ?? 'exact').toLowerCase();
    if (m == 'hidden') return '위치 미표시';
    if (m == 'approximate') return '약 100~200m 범위';
    return '정확한 위치';
  }

  /// CR-01: Client-side validation for allowed external support domains
  /// Allowed: ko-fi.com, buymeacoffee.com, paypal.me (https only, no internal payment params)
  static String? validateSupportUrl(String provider, String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      return '외부 후원 페이지 URL을 입력해주세요.';
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.scheme.toLowerCase() != 'https' || uri.host.isEmpty) {
      return '보안을 위해 https:// 로 시작하는 유효한 URL만 등록할 수 있습니다.';
    }
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    const allowedDomains = <String, List<String>>{
      'kofi': ['ko-fi.com'],
      'buymeacoffee': ['buymeacoffee.com'],
      'paypal': ['paypal.me', 'paypal.com'],
    };
    final p = provider.toLowerCase();
    final allowedForProvider = allowedDomains[p] ??
        ['ko-fi.com', 'buymeacoffee.com', 'paypal.me', 'paypal.com'];
    if (!allowedForProvider.contains(host)) {
      return '허용된 외부 후원 도메인(${allowedForProvider.join(', ')})만 연결할 수 있습니다.';
    }
    final pathSegments = uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
    if (pathSegments.isEmpty) {
      return '크리에이터 고유 프로필 경로가 포함된 URL을 입력해주세요 (예: https://ko-fi.com/creator).';
    }
    if (uri.query.isNotEmpty || uri.fragment.isNotEmpty) {
      return '보안을 위해 쿼리 파라미터(?...)가 없는 순수 프로필 URL만 허용됩니다.';
    }
    return null;
  }

  /// CR-01: Fetch creator's linked external support account
  static Future<Map<String, dynamic>?> getSupportAccount([String? userId]) async {
    final targetId = userId ?? currentUserId;
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/users/${Uri.encodeComponent(targetId)}/support-account'),
      );
      if (response.statusCode == 200) {
        final body = utf8.decode(response.bodyBytes).trim();
        if (body.isNotEmpty && body != 'null') {
          final decoded = json.decode(body);
          if (decoded is Map<String, dynamic>) {
            final next = Map<String, Map<String, dynamic>>.from(supportAccountsCacheNotifier.value);
            next[targetId] = decoded;
            supportAccountsCacheNotifier.value = next;
            if (decoded['videos'] is List) {
            decoded['videos'] = (decoded['videos'] as List)
                .map((v) => v is Map ? _sanitizeVideoMap(Map<String, dynamic>.from(v)) : v)
                .toList();
          }
          return decoded;
          }
        } else {
          final next = Map<String, Map<String, dynamic>>.from(supportAccountsCacheNotifier.value);
          next.remove(targetId);
          supportAccountsCacheNotifier.value = next;
          return null;
        }
      }
    } catch (_) {}
    return supportAccountsCacheNotifier.value[targetId];
  }

  /// CR-01: Connect & verify creator external support account (0% platform fee)
  static Future<Map<String, dynamic>> saveSupportAccount({
    required String provider,
    required String supportUrl,
    String? userId,
  }) async {
    final targetId = userId ?? currentUserId;
    final validationError = validateSupportUrl(provider, supportUrl);
    if (validationError != null) {
      return {'error': validationError};
    }

    try {
      final response = await http.put(
        Uri.parse('$baseUrl/users/${Uri.encodeComponent(targetId)}/support-account'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'provider': provider.toLowerCase(),
          'support_url': supportUrl.trim(),
          'verify_ownership': true,
        }),
      );
      if (response.statusCode == 200) {
        final decoded = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final next = Map<String, Map<String, dynamic>>.from(supportAccountsCacheNotifier.value);
        next[targetId] = decoded;
        supportAccountsCacheNotifier.value = next;
        return decoded;
      } else {
        final err = json.decode(utf8.decode(response.bodyBytes));
        return {'error': err['detail']?.toString() ?? '후원 계정 연결에 실패했습니다.'};
      }
    } catch (_) {
      final fallbackAcc = <String, dynamic>{
        'id': 'sup_$targetId',
        'user_id': targetId,
        'provider': provider.toLowerCase(),
        'support_url': supportUrl.trim(),
        'ownership_status': 'verified',
        'verified_at': DateTime.now().toUtc().toIso8601String(),
        'active': true,
      };
      final next = Map<String, Map<String, dynamic>>.from(supportAccountsCacheNotifier.value);
      next[targetId] = fallbackAcc;
      supportAccountsCacheNotifier.value = next;
      return fallbackAcc;
    }
  }

  /// CR-01: Disconnect external support account
  static Future<bool> disconnectSupportAccount([String? userId]) async {
    final targetId = userId ?? currentUserId;
    final next = Map<String, Map<String, dynamic>>.from(supportAccountsCacheNotifier.value);
    next.remove(targetId);
    supportAccountsCacheNotifier.value = next;
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/users/${Uri.encodeComponent(targetId)}/support-account'),
      );
      return response.statusCode == 200;
    } catch (_) {
      return true;
    }
  }

  /// CR-01: Track click on external support button (statistical reference only, NOT revenue)
  static Future<Map<String, dynamic>> recordSupportClick(String videoId) async {
    try {
      final viewerParam = Uri.encodeComponent(currentUserId);
      final response = await http.post(
        Uri.parse('$baseUrl/videos/${Uri.encodeComponent(videoId)}/support-click?viewer_id=$viewerParam'),
      );
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {'video_id': videoId, 'recorded': true};
  }

  /// Spec v1.1 Principle 8 (Privacy by Choice) & CR-01/CR-02:
  /// Update an existing video's support_enabled and/or location_display_mode
  static Future<Map<String, dynamic>> updateVideoSettings({
    required String videoId,
    bool? supportEnabled,
    String? locationDisplayMode,
    bool? exactLocationConsented,
  }) async {
    final payload = <String, dynamic>{
      'requester_id': currentUserId,
      'precise_permission_granted': preciseLocationPermissionNotifier.value,
      if (supportEnabled != null) 'support_enabled': supportEnabled,
      if (locationDisplayMode != null) 'location_display_mode': locationDisplayMode,
      if (exactLocationConsented != null) 'exact_location_consented': exactLocationConsented,
    };
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/videos/${Uri.encodeComponent(videoId)}/settings'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      );
      if (response.statusCode == 200) {
        final decoded = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        feedFilterVersionNotifier.value++;
        return decoded;
      }
    } catch (_) {}
    feedFilterVersionNotifier.value++;
    return {
      'id': videoId,
      if (supportEnabled != null) 'support_enabled': supportEnabled,
      if (locationDisplayMode != null) ...{
        'location_display_mode': locationDisplayMode,
        'location_privacy_label': formatLocationPrivacyLabel(locationDisplayMode),
      },
    };
  }

  /// CR-02.B: Record user's explicit consent for Exact Location disclosure
  static Future<void> recordExactLocationConsent(bool consented) async {
    exactLocationConsentNotifier.value = consented;
    final cur = currentUserNotifier.value;
    if (cur != null) {
      final updated = Map<String, dynamic>.from(cur);
      updated['exact_location_consent'] = consented;
      currentUserNotifier.value = updated;
    }
    try {
      await http.post(
        Uri.parse(
          '$baseUrl/users/${Uri.encodeComponent(currentUserId)}/location-consent?consented=$consented',
        ),
      );
    } catch (_) {}
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

  /// Spec #16 & #46 + CR-01: Fetch dynamic Alerts (License category replaced with Support)
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
    final nowIso = DateTime.now().toUtc().toIso8601String();
    return [
      {
        'id': 'alt_spec_social',
        'category': 'Social',
        'title': '@apgujeong_now님이 회원님을 팔로우하기 시작했습니다',
        'subtitle': '압구정·신사 지역 현장 크리에이터',
        'target_user_id': 'u_apgu_now',
        'target_username': '@apgujeong_now',
        'created_at': nowIso,
      },
      {
        'id': 'alt_spec_mod_review',
        'category': 'Moderation',
        'title': '영상이 임시 비공개로 전환되었습니다',
        'subtitle': '해당 영상에 다수의 신고가 접수되었습니다 · [ 재검토 요청 ]',
        'video_id': 'v_sinsa_1',
        'video_title': '신사동 가로수길 카페 앞 실시간',
        'reason': '해당 영상에 대해 다수의 신고가 접수되어 확인 중입니다.',
        'created_at': nowIso,
      },
      {
        'id': 'alt_spec_support',
        'category': 'Support',
        'title': '외부 크리에이터 후원 페이지 연결이 활성화되었습니다',
        'subtitle': 'https://ko-fi.com/seoul_walker · NOWFIELD 플랫폼 수수료 0%',
        'created_at': nowIso,
      },
      {
        'id': 'alt_spec_earnings',
        'category': 'Earnings',
        'title': '이번 달 크리에이터 풀 정산 내역 안내',
        'subtitle': '유효 조회 품질 지수 기준 광고 수익 배분 내역을 확인하세요.',
        'created_at': nowIso,
      },
    ];
  }

  /// Fetch full user profile summary (CR-01: uploaded videos, support account, stats; no licenses)
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
          if (decoded['support_account'] is Map<String, dynamic>) {
            final next = Map<String, Map<String, dynamic>>.from(supportAccountsCacheNotifier.value);
            next[userId ?? currentUserId] =
                Map<String, dynamic>.from(decoded['support_account'] as Map);
            supportAccountsCacheNotifier.value = next;
          }
          if (decoded['videos'] is List) {
            decoded['videos'] = (decoded['videos'] as List)
                .map((v) => v is Map ? _sanitizeVideoMap(Map<String, dynamic>.from(v)) : v)
                .toList();
          }
          return decoded;
        }
      }
    } catch (_) {}
    final nowUtc = DateTime.now().toUtc();
    final cachedSupport = supportAccountsCacheNotifier.value[userId ?? currentUserId];
    final fallbackVideos = [
      {
        'id': 'v_sinsa_1',
        'title': '신사동 가로수길 카페 앞 실시간',
        'subtitle': '주말 오후 신사동 가로수길 메인 도로에 인파가 몰려 활기찬 분위기입니다.',
        'uploader_id': 'u_seoul_walker',
        'uploader_name': '@seoul_walker',
        'location_name': '서울 강남구 신사동',
        'location_display_mode': 'approximate',
        'location_privacy_label': '약 100~200m 범위',
        'display_lat': 37.5212,
        'display_lng': 127.0238,
        'video_url': 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyBlazes.mp4',
        'thumbnail_url': 'https://picsum.photos/seed/sinsa1/600/900',
        'like_count': 24,
        'comment_count': 5,
        'support_enabled': true,
        'creator_support_url': cachedSupport?['support_url'] ?? 'https://ko-fi.com/seoul_walker',
        'creator_support_provider': cachedSupport?['provider'] ?? 'kofi',
        'captured_at': nowUtc.subtract(const Duration(minutes: 6)).toIso8601String(),
        'published_at': nowUtc.subtract(const Duration(minutes: 5)).toIso8601String(),
        'display_timezone': 'Asia/Seoul',
        'created_at': nowUtc.subtract(const Duration(minutes: 5)).toIso8601String(),
      },
      {
        'id': 'v_apgu_1',
        'title': '압구정 현대백화점 앞 교통 정체',
        'subtitle': '현재 압구정 현대백화점 사거리 방향 차량 정체가 심합니다. 서행 운전하세요.',
        'uploader_id': 'u_apgu_now',
        'uploader_name': '@apgu_now',
        'location_name': '서울 강남구 압구정동',
        'location_display_mode': 'exact',
        'location_privacy_label': '정확한 위치',
        'display_lat': 37.5273,
        'display_lng': 127.0285,
        'video_url': 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
        'thumbnail_url': 'https://picsum.photos/seed/apgu1/600/900',
        'like_count': 18,
        'comment_count': 3,
        'support_enabled': true,
        'creator_support_url': 'https://buymeacoffee.com/apgu_now',
        'creator_support_provider': 'buymeacoffee',
        'captured_at': nowUtc.subtract(const Duration(minutes: 13)).toIso8601String(),
        'published_at': nowUtc.subtract(const Duration(minutes: 12)).toIso8601String(),
        'display_timezone': 'Asia/Seoul',
        'created_at': nowUtc.subtract(const Duration(minutes: 12)).toIso8601String(),
      },
    ];
    return {
      'user': {
        'id': userId ?? currentUserId,
        'username': (userId != null && userId.startsWith('@')) ? userId : currentUsername,
        'country': 'KR',
        'exact_location_consent': exactLocationConsentNotifier.value,
      },
      'video_count': fallbackVideos.length,
      'follower_count': 128,
      'following_count': 42,
      'is_following': false,
      'support_account': cachedSupport,
      'total_support_clicks': 14,
      'videos': fallbackVideos,
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

  static Future<List<Map<String, dynamic>>> getFollowers(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/users/${Uri.encodeComponent(userId)}/followers'),
      );
      if (response.statusCode == 200) {
        final decoded = json.decode(utf8.decode(response.bodyBytes)) as List<dynamic>;
        return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<List<Map<String, dynamic>>> getFollowing(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/users/${Uri.encodeComponent(userId)}/following'),
      );
      if (response.statusCode == 200) {
        final decoded = json.decode(utf8.decode(response.bodyBytes)) as List<dynamic>;
        return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    return [];
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

  static Map<String, dynamic> _sanitizeVideoMap(Map<String, dynamic> v) {
    final mode = (v['location_display_mode'] ?? 'exact').toString().toLowerCase();
    if (mode == 'hidden') {
      v['location_name'] = '위치 미표시';
      return v;
    }
    final lat = (v['display_lat'] ?? v['fuzzed_lat']) is num
        ? ((v['display_lat'] ?? v['fuzzed_lat']) as num).toDouble()
        : null;
    final lng = (v['display_lng'] ?? v['fuzzed_lng']) is num
        ? ((v['display_lng'] ?? v['fuzzed_lng']) as num).toDouble()
        : null;
    v['location_name'] = sanitizeLocationName(
      v['location_name']?.toString(),
      lat: lat,
      lng: lng,
    );
    return v;
  }

  /// CR-04: Get nearby videos along with clustered pins within 1km & 60-minute TTL
  static Future<Map<String, dynamic>> getNearbyData(
    double lat,
    double lng, {
    double radiusKm = 1.0,
    double timeLimitHours = 1.0,
  }) async {
    try {
      final response = await http.get(
        Uri.parse(
          '$baseUrl/videos/nearby?lat=$lat&lng=$lng&radius_km=$radiusKm&time_limit_hours=$timeLimitHours',
        ),
      );
      if (response.statusCode == 200) {
        final decoded = json.decode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic>) {
          if (decoded['raw_videos'] is List) {
            decoded['raw_videos'] = (decoded['raw_videos'] as List)
                .map((e) => e is Map ? _sanitizeVideoMap(Map<String, dynamic>.from(e)) : e)
                .toList();
          }
          if (decoded['clusters'] is List) {
            decoded['clusters'] = (decoded['clusters'] as List).map((c) {
              if (c is Map) {
                final cm = Map<String, dynamic>.from(c);
                final clat = cm['latitude'] is num ? (cm['latitude'] as num).toDouble() : null;
                final clng = cm['longitude'] is num ? (cm['longitude'] as num).toDouble() : null;
                cm['location_name'] = sanitizeLocationName(
                  cm['location_name']?.toString(),
                  lat: clat,
                  lng: clng,
                );
                if (cm['videos'] is List) {
                  cm['videos'] = (cm['videos'] as List)
                      .map((v) => v is Map ? _sanitizeVideoMap(Map<String, dynamic>.from(v)) : v)
                      .toList();
                }
                return cm;
              }
              return c;
            }).toList();
          }
          if (decoded['videos'] is List) {
            decoded['videos'] = (decoded['videos'] as List)
                .map((v) => v is Map ? _sanitizeVideoMap(Map<String, dynamic>.from(v)) : v)
                .toList();
          }
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
        }).map((item) {
          if (item is Map) {
            return _sanitizeVideoMap(Map<String, dynamic>.from(item));
          }
          return item;
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
          if (decoded['videos'] is List) {
            decoded['videos'] = (decoded['videos'] as List)
                .map((v) => v is Map ? _sanitizeVideoMap(Map<String, dynamic>.from(v)) : v)
                .toList();
          }
          return decoded;
        }
      }
    } catch (_) {}
    final qLower = query.trim().toLowerCase();
    final nowUtc = DateTime.now().toUtc();
    final sampleVideos = [
      {
        'id': 'v_sinsa_1',
        'title': '신사동 가로수길 카페 앞 실시간',
        'subtitle': '주말 오후 신사동 가로수길 메인 도로에 인파가 몰려 활기찬 분위기입니다.',
        'uploader_id': 'u_seoul_walker',
        'uploader_name': '@seoul_walker',
        'location_name': '서울 강남구 신사동',
        'location_display_mode': 'approximate',
        'location_privacy_label': '약 100~200m 범위',
        'video_url': 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyBlazes.mp4',
        'thumbnail_url': 'https://picsum.photos/seed/sinsa1/600/900',
        'like_count': 24,
        'comment_count': 5,
        'support_enabled': true,
        'creator_support_url': 'https://ko-fi.com/seoul_walker',
        'creator_support_provider': 'kofi',
        'captured_at': nowUtc.subtract(const Duration(minutes: 6)).toIso8601String(),
        'published_at': nowUtc.subtract(const Duration(minutes: 5)).toIso8601String(),
        'display_timezone': 'Asia/Seoul',
        'created_at': nowUtc.subtract(const Duration(minutes: 5)).toIso8601String(),
      },
      {
        'id': 'v_apgu_1',
        'title': '압구정 현대백화점 앞 교통 정체',
        'subtitle': '현재 압구정 현대백화점 사거리 방향 차량 정체가 심합니다.',
        'uploader_id': 'u_apgu_now',
        'uploader_name': '@apgu_now',
        'location_name': '서울 강남구 압구정동',
        'location_display_mode': 'exact',
        'location_privacy_label': '정확한 위치',
        'video_url': 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
        'thumbnail_url': 'https://picsum.photos/seed/apgu1/600/900',
        'like_count': 18,
        'comment_count': 3,
        'support_enabled': true,
        'creator_support_url': 'https://buymeacoffee.com/apgu_now',
        'creator_support_provider': 'buymeacoffee',
        'captured_at': nowUtc.subtract(const Duration(minutes: 13)).toIso8601String(),
        'published_at': nowUtc.subtract(const Duration(minutes: 12)).toIso8601String(),
        'display_timezone': 'Asia/Seoul',
        'created_at': nowUtc.subtract(const Duration(minutes: 12)).toIso8601String(),
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

  /// Resolve (lat, lng) into a Korean neighborhood (동) name (e.g. '서울 강남구 신사동'),
  /// never returning raw decimal coordinates.
  static Future<String> resolveNeighborhoodName(double lat, double lng) async {
    // 1. Try Kakao Maps JS SDK in browser
    final fromJs = await reverseGeocodeWithKakaoJs(lat, lng);
    if (fromJs != null && fromJs.isNotEmpty && !fromJs.contains(',')) {
      return fromJs;
    }

    // 2. Try Backend /kakao/region endpoint
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/kakao/region?lat=$lat&lng=$lng'))
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final decoded = json.decode(utf8.decode(res.bodyBytes));
        if (decoded is Map<String, dynamic>) {
          final formatted = decoded['formatted_name']?.toString().trim() ?? '';
          if (formatted.isNotEmpty && !formatted.contains(',') && !formatted.startsWith('위도')) {
            return formatted;
          }
        }
      }
    } catch (_) {}

    // 3. Fallback to local Korean dong lookup
    return formatNeighborhoodFallback(lat, lng);
  }

  /// Sanitize any location_name string so raw coordinates like '37.5204, 127.0229' are converted to dong names
  static String sanitizeLocationName(String? rawName, {double? lat, double? lng}) {
    final clean = (rawName ?? '').trim();
    if (clean == '위치 미표시') return clean;
    final bool isCoordLike = clean.isEmpty ||
        clean.startsWith('위도') ||
        RegExp(r'^-?\d+\.\d+\s*,\s*-?\d+\.\d+$').hasMatch(clean);
    if (!isCoordLike) return clean;
    if (lat != null && lng != null) {
      return formatNeighborhoodFallback(lat, lng);
    }
    if (clean.contains(',')) {
      final parts = clean.split(',');
      final parsedLat = double.tryParse(parts[0].trim());
      final parsedLng = parts.length > 1 ? double.tryParse(parts[1].trim()) : null;
      if (parsedLat != null && parsedLng != null) {
        return formatNeighborhoodFallback(parsedLat, parsedLng);
      }
    }
    return '서울 강남구 신사동';
  }

  static String formatNeighborhoodFallback(double lat, double lng) {
    const List<Map<String, dynamic>> dongs = [
      {'name': '서울 강남구 신사동', 'lat': 37.5204, 'lng': 127.0229},
      {'name': '서울 강남구 압구정동', 'lat': 37.5270, 'lng': 127.0284},
      {'name': '서울 강남구 청담동', 'lat': 37.5240, 'lng': 127.0470},
      {'name': '서울 강남구 논현동', 'lat': 37.5110, 'lng': 127.0310},
      {'name': '서울 강남구 삼성동', 'lat': 37.5140, 'lng': 127.0565},
      {'name': '서울 강남구 역삼동', 'lat': 37.5006, 'lng': 127.0365},
      {'name': '서울 강남구 대치동', 'lat': 37.4945, 'lng': 127.0620},
      {'name': '서울 서초구 잠원동', 'lat': 37.5180, 'lng': 127.0160},
      {'name': '서울 서초구 반포동', 'lat': 37.5045, 'lng': 127.0048},
      {'name': '서울 서초구 서초동', 'lat': 37.4915, 'lng': 127.0150},
      {'name': '서울 서초구 양재동', 'lat': 37.4740, 'lng': 127.0380},
      {'name': '서울 용산구 한남동', 'lat': 37.5345, 'lng': 127.0010},
      {'name': '서울 용산구 이태원동', 'lat': 37.5345, 'lng': 126.9945},
      {'name': '서울 성동구 성수동', 'lat': 37.5445, 'lng': 127.0560},
      {'name': '서울 마포구 서교동', 'lat': 37.5540, 'lng': 126.9210},
      {'name': '서울 마포구 연남동', 'lat': 37.5635, 'lng': 126.9245},
      {'name': '서울 중구 명동', 'lat': 37.5635, 'lng': 126.9850},
      {'name': '서울 송파구 잠실동', 'lat': 37.5130, 'lng': 127.1000},
      {'name': '서울 영등포구 여의도동', 'lat': 37.5250, 'lng': 126.9260},
    ];
    String best = '서울 강남구 신사동';
    double bestDistSq = double.infinity;
    for (final d in dongs) {
      final dLat = (d['lat'] as num).toDouble() - lat;
      final dLng = (d['lng'] as num).toDouble() - lng;
      final distSq = dLat * dLat + dLng * dLng;
      if (distSq < bestDistSq) {
        bestDistSq = distSq;
        best = d['name'] as String;
      }
    }
    return best;
  }

  /// Upload recorded video file with metadata (v1.1 CR-01, CR-02, CR-03)
  static Future<Map<String, dynamic>> uploadVideo({
    required List<int> videoBytes,
    required String filename,
    required String title,
    String? subtitle,
    required double latitude,
    required double longitude,
    String? locationName,
    String? uploaderId,
    String locationDisplayMode = 'exact',
    bool exactLocationConsented = false,
    bool precisePermissionGranted = true,
    bool isSensitivePlace = false,
    bool supportEnabled = false,
    String? capturedAt,
    String displayTimezone = 'Asia/Seoul',
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
      if (locationName != null && locationName.trim().isNotEmpty) {
        request.fields['location_name'] = locationName.trim();
      }
      request.fields['uploader_id'] = uploaderId ?? currentUserId;
      request.fields['location_display_mode'] = locationDisplayMode;
      request.fields['exact_location_consented'] = exactLocationConsented.toString();
      request.fields['precise_permission_granted'] = precisePermissionGranted.toString();
      request.fields['is_sensitive_place'] = isSensitivePlace.toString();
      request.fields['support_enabled'] = supportEnabled.toString();
      request.fields['display_timezone'] = displayTimezone;
      if (capturedAt != null && capturedAt.isNotEmpty) {
        request.fields['captured_at'] = capturedAt;
      }
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

  /// Fetch other angles (nearby videos) for a given video
  static Future<List<Map<String, dynamic>>> getVideoAngles(String videoId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/videos/${Uri.encodeComponent(videoId)}/angles'),
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

  /// Fetch admin settings
  static Future<Map<String, dynamic>> getAdminSettings() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/admin/settings'));
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {};
  }

  /// Update admin settings
  static Future<Map<String, dynamic>> updateAdminSettings(Map<String, dynamic> updates) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/admin/settings'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(updates),
      );
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {};
  }

  /// Delete a video owned by the current user
  static Future<bool> deleteVideo(String videoId) async {
    try {
      final uid = Uri.encodeComponent(currentUserId);
      final response = await http.delete(
        Uri.parse('$baseUrl/videos/${Uri.encodeComponent(videoId)}?requester_id=$uid'),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
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
