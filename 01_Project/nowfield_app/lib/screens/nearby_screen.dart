import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/api_service.dart';
import '../widgets/kakao_map_view.dart';
import 'camera_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  List<Map<String, dynamic>> _nearbyVideos = [];
  List<Map<String, dynamic>> _kakaoPins = [];
  String _nearbyStateMode = 'normal'; // 'normal', 'empty' (Spec #42), 'denied' (Spec #51.3)

  @override
  void initState() {
    super.initState();
    _fetchVideos();
  }

  Future<void> _fetchVideos() async {
    try {
      final data = await ApiService.getNearbyData(37.5250, 127.0250);
      if (mounted) {
        setState(() {
          if (data.containsKey('raw_videos') && data['raw_videos'] is List) {
            final raw = data['raw_videos'] as List<dynamic>;
            _nearbyVideos = raw
                .whereType<Map>()
                .map((v) => Map<String, dynamic>.from(v))
                .toList();
          }
          if (data.containsKey('clusters') && data['clusters'] is List) {
            final clusters = data['clusters'] as List<dynamic>;
            _kakaoPins = clusters.whereType<Map>().map((c) {
              final rawClusterVideos = (c['videos'] as List<dynamic>? ?? []);
              final clusterVideos = rawClusterVideos
                  .whereType<Map>()
                  .map((v) => Map<String, dynamic>.from(v))
                  .toList();
              final firstTitle = clusterVideos.isNotEmpty
                  ? (clusterVideos.first['title']?.toString() ?? c['location_name']?.toString() ?? '')
                  : (c['location_name']?.toString() ?? '');
              return <String, dynamic>{
                'id': c['cluster_id']?.toString() ?? '',
                'title': firstTitle,
                'location_name': c['location_name']?.toString() ?? '',
                'lat': (c['latitude'] as num).toDouble(),
                'lng': (c['longitude'] as num).toDouble(),
                'isStacked': c['is_stacked'] == true,
                'videos': clusterVideos,
              };
            }).toList();
          }
        });
      }
    } catch (_) {
      // Fallback
    }
  }

  void _openVideoDetail(BuildContext context, Map<String, dynamic> video) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoDetailScreen(videoData: video),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          '내 주변',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '검색',
            icon: const Icon(Icons.search_rounded, color: AppColors.textPrimary),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SearchScreen(),
                ),
              );
            },
          ),
          IconButton(
            tooltip: '내 주변 필터 및 상태 설정',
            icon: const Icon(Icons.settings_outlined, color: AppColors.textPrimary),
            onPressed: () => _showNearbySettingsSheet(context),
          ),
        ],
      ),
      body: _nearbyStateMode == 'empty'
          ? _buildEmptyNearbyState(context)
          : _nearbyStateMode == 'denied'
              ? _buildLocationDeniedState()
              : Column(
                  children: [
          // Privacy protection indicator banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.card,
            child: Row(
              children: const [
                Icon(Icons.shield_outlined, size: 16, color: AppColors.accent),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '위치 개인정보 보호를 위해 반경 100m~200m 좌표 퍼징이 적용됩니다.',
                    style: TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),

          // Map Area (Real interactive Kakao Map on Web)
          Expanded(
            child: Stack(
              children: [
                // 1. Interactive Kakao Map on Web
                if (kIsWeb)
                  Positioned.fill(
                    child: KakaoMapView(
                      centerLat: 37.5250,
                      centerLng: 127.0250,
                      pins: _kakaoPins.isNotEmpty
                          ? _kakaoPins
                          : [
                              {
                                'id': 'cluster_apgu',
                                'title': '서울 강남구 압구정동',
                                'lat': 37.5270,
                                'lng': 127.0284,
                                'isStacked': true,
                              },
                              {
                                'id': 'single_sinsa',
                                'title': '서울 강남구 신사동',
                                'lat': 37.5205,
                                'lng': 127.0230,
                                'isStacked': false,
                              },
                              {
                                'id': 'single_jamwon',
                                'title': '서울 서초구 잠원동',
                                'lat': 37.5180,
                                'lng': 127.0160,
                                'isStacked': false,
                              },
                            ],
                      onPinClicked: (id, title, isStacked) {
                        final matchedPin = _kakaoPins.cast<Map<String, dynamic>?>().firstWhere(
                          (p) => p != null && p['id'] == id,
                          orElse: () => null,
                        );
                        final pinVideos = matchedPin != null && matchedPin['videos'] is List
                            ? (matchedPin['videos'] as List)
                                .whereType<Map>()
                                .map((v) => Map<String, dynamic>.from(v))
                                .toList()
                            : <Map<String, dynamic>>[];
                        final locationName = matchedPin?['location_name']?.toString() ?? title;

                        if (isStacked) {
                          final videosToShow = pinVideos.isNotEmpty
                              ? pinVideos
                              : <Map<String, dynamic>>[
                                  {
                                    'id': 'v_apgu_1',
                                    'title': '압구정 현대백화점 앞 교통 정체',
                                    'uploader_name': '@apgu_now',
                                    'location_name': locationName,
                                    'time': '3분 전',
                                    'video_url': 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
                                    'thumbnail_url': 'https://picsum.photos/seed/apgu1/600/400',
                                  },
                                  {
                                    'id': 'v_apgu_2',
                                    'title': '압구정역 3번 출구 퇴근길 버스 정류장 대기줄',
                                    'uploader_name': '@commuter',
                                    'location_name': locationName,
                                    'time': '15분 전',
                                    'video_url': 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
                                    'thumbnail_url': 'https://picsum.photos/seed/apgu2/600/400',
                                  },
                                  {
                                    'id': 'v_apgu_3',
                                    'title': '압구정 로데오 골목 인파 현황',
                                    'uploader_name': '@seoul_walker',
                                    'location_name': locationName,
                                    'time': '28분 전',
                                    'video_url': 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4',
                                    'thumbnail_url': 'https://picsum.photos/seed/apgu3/600/400',
                                  },
                                ];
                          _showClusterModal(context, locationName, videosToShow);
                        } else {
                          final singleVideo = pinVideos.isNotEmpty
                              ? pinVideos.first
                              : (_nearbyVideos.isNotEmpty
                                  ? _nearbyVideos.first
                                  : <String, dynamic>{
                                      'id': id,
                                      'title': title,
                                      'uploader_name': '@seoul_walker',
                                      'location_name': locationName,
                                      'time': '1분 전',
                                      'video_url': 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyBlazes.mp4',
                                      'thumbnail_url': 'https://picsum.photos/seed/sinsa1/600/400',
                                    });
                          _showSingleVideoModal(context, singleVideo);
                        }
                      },
                    ),
                  )
                else ...[
                  // Mobile / Fallback static layout
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/map_placeholder.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      color: AppColors.background.withOpacity(0.28),
                    ),
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: _buildNaverStyleUserMarker(),
                  ),
                  Positioned(
                    top: 130,
                    left: 70,
                    child: _buildSinglePinMarker(
                      context,
                      video: _nearbyVideos.isNotEmpty
                          ? _nearbyVideos.first
                          : <String, dynamic>{
                              'id': 'v_sinsa_1',
                              'title': '신사동 가로수길 카페 앞 실시간',
                              'uploader_name': '@coffee_lover',
                              'location_name': '서울 강남구 신사동',
                              'time': '1분 전',
                              'video_url': 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyBlazes.mp4',
                              'thumbnail_url': 'https://picsum.photos/seed/sinsa1/600/400',
                            },
                    ),
                  ),
                  Positioned(
                    top: 220,
                    right: 48,
                    child: _buildStackedPinMarker(
                      context,
                      clusterCount: 3,
                      locationName: '압구정역 3번 출구 인근',
                      videos: [
                        {
                          'id': 'v_apgu_1',
                          'title': '압구정 현대백화점 앞 교통 정체',
                          'time': '3분 전',
                          'uploader_name': '@apgu_now',
                          'location_name': '압구정역 3번 출구 인근',
                          'video_url': 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
                          'thumbnail_url': 'https://picsum.photos/seed/apgu1/600/400',
                        },
                        {
                          'id': 'v_apgu_2',
                          'title': '압구정 로데오 골목 인파 현황',
                          'time': '12분 전',
                          'uploader_name': '@seoul_rider',
                          'location_name': '압구정역 3번 출구 인근',
                          'video_url': 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4',
                          'thumbnail_url': 'https://picsum.photos/seed/apgu2/600/400',
                        },
                        {
                          'id': 'v_apgu_3',
                          'title': '퇴근길 버스 정류장 대기줄',
                          'time': '18분 전',
                          'uploader_name': '@commuter',
                          'location_name': '압구정역 3번 출구 인근',
                          'video_url': 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
                          'thumbnail_url': 'https://picsum.photos/seed/apgu3/600/400',
                        },
                      ],
                    ),
                  ),
                ],

                // GPS Re-center FAB
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton.small(
                    backgroundColor: AppColors.card,
                    foregroundColor: AppColors.accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: AppColors.cardBorder, width: 0.8),
                    ),
                    onPressed: () {
                      _fetchVideos();
                    },
                    child: const Icon(Icons.my_location_rounded, size: 20),
                  ),
                ),
              ],
            ),
          ),

          // Recent nearby videos panel
          Container(
            color: AppColors.background,
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '최근 내 주변 영상',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '반경 1km',
                        style: TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 110,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _nearbyVideos.isNotEmpty ? _nearbyVideos.length : 5,
                    itemBuilder: (context, index) {
                      final item = _nearbyVideos.isNotEmpty && index < _nearbyVideos.length
                          ? _nearbyVideos[index]
                          : <String, dynamic>{
                              'id': 'v_sample_$index',
                              'title': '주변 실시간 영상 ${index + 1}',
                              'uploader_name': '@field_reporter',
                              'location_name': '서울 강남구 신사동',
                              'time': '${index + 1}분 전',
                              'video_url': 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
                              'thumbnail_url': 'https://picsum.photos/seed/${index + 60}/200/300',
                            };
                      final thumbUrl = ApiService.resolveMediaUrl(
                        (item['thumbnail_url'] ?? item['preview_url']) as String?,
                      );
                      final timeText = formatVideoTimeAgo(item['created_at'] ?? item['time']);

                      return GestureDetector(
                        onTap: () => _showSingleVideoModal(context, item),
                        child: Container(
                          width: 80,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.cardBorder.withOpacity(0.5)),
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Image.network(
                                  thumbUrl.isNotEmpty
                                      ? thumbUrl
                                      : 'https://picsum.photos/seed/${index + 60}/200/300',
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => Container(
                                    color: AppColors.card,
                                    child: const Center(child: Icon(Icons.videocam, color: Colors.white24)),
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.bottomLeft,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  decoration: const BoxDecoration(
                                    color: AppColors.subtitleBackground,
                                    borderRadius: BorderRadius.only(
                                      topRight: Radius.circular(4),
                                    ),
                                  ),
                                  child: Text(
                                    timeText,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Naver map style user location marker
  Widget _buildNaverStyleUserMarker() {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.primary.withOpacity(0.38),
                  AppColors.primary.withOpacity(0.12),
                  Colors.transparent,
                ],
                stops: const [0.25, 0.65, 1.0],
              ),
            ),
          ),
          Transform.rotate(
            angle: 0.60,
            child: Transform.translate(
              offset: const Offset(0, -15),
              child: CustomPaint(
                size: const Size(14, 12),
                painter: _HeadingArrowPainter(color: AppColors.primary),
              ),
            ),
          ),
          Container(
            width: 17,
            height: 17,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSinglePinMarker(
    BuildContext context, {
    required Map<String, dynamic> video,
  }) {
    return GestureDetector(
      onTap: () => _showSingleVideoModal(context, video),
      child: _buildSpeechBubbleWidget(hasPlayIcon: true),
    );
  }

  Widget _buildStackedPinMarker(
    BuildContext context, {
    required int clusterCount,
    required String locationName,
    required List<Map<String, dynamic>> videos,
  }) {
    return GestureDetector(
      onTap: () => _showClusterModal(context, locationName, videos),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Transform.translate(
            offset: const Offset(10, -10),
            child: _buildSpeechBubbleWidget(hasPlayIcon: false),
          ),
          Transform.translate(
            offset: const Offset(5, -5),
            child: _buildSpeechBubbleWidget(hasPlayIcon: false),
          ),
          _buildSpeechBubbleWidget(hasPlayIcon: true),
        ],
      ),
    );
  }

  Widget _buildSpeechBubbleWidget({required bool hasPlayIcon}) {
    return CustomPaint(
      size: const Size(44, 38),
      painter: _SpeechBubblePainter(
        fillColor: Colors.white,
        borderColor: Colors.black,
        borderWidth: 2.8,
      ),
      child: SizedBox(
        width: 44,
        height: 38,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8.0, right: 2.0),
          child: Center(
            child: hasPlayIcon
                ? const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.black,
                    size: 22,
                  )
                : null,
          ),
        ),
      ),
    );
  }

  void _showSingleVideoModal(BuildContext parentContext, Map<String, dynamic> video) {
    final title = video['title']?.toString() ?? '현장 영상';
    final author = (video['uploader_name'] ?? video['author'] ?? '@seoul_walker').toString();
    final locationName = video['location_name']?.toString() ?? '';
    final time = formatVideoTimeAgo(video['created_at'] ?? video['time']);
    final thumbUrl = ApiService.resolveMediaUrl(
      (video['thumbnail_url'] ?? video['preview_url']) as String?,
    );

    showModalBottomSheet(
      context: parentContext,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () {
                    Navigator.pop(modalContext);
                    _openVideoDetail(parentContext, video);
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      height: 180,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            thumbUrl.isNotEmpty
                                ? thumbUrl
                                : 'https://picsum.photos/seed/single_preview/600/340',
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              height: 180,
                              color: AppColors.background,
                              child: const Center(child: Icon(Icons.videocam, color: Colors.white24, size: 40)),
                            ),
                          ),
                          Container(color: Colors.black26),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () {
                    Navigator.pop(modalContext);
                    Navigator.of(parentContext).push(
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(
                          targetUserId: video['uploader_id']?.toString() ?? author,
                          targetUsername: author,
                        ),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      Text(
                        author,
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Flexible(
                        child: Text(
                          locationName.isNotEmpty ? ' · $locationName · $time' : ' · $time',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(modalContext);
                      _openVideoDetail(parentContext, video);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('현장 영상 시청하기', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showClusterModal(BuildContext parentContext, String locationName, List<Map<String, dynamic>> videos) {
    showModalBottomSheet(
      context: parentContext,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${videos.length}개 영상 스택',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        locationName,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  '촬영자 사생활 보호 원칙에 따라 약 150m 반경 영상이 1개 핀으로 집약되었습니다.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
                const SizedBox(height: 12),
                ...videos.map(
                  (v) {
                    final thumbUrl = ApiService.resolveMediaUrl(
                      (v['thumbnail_url'] ?? v['preview_url']) as String?,
                    );
                    final author = (v['uploader_name'] ?? v['author'] ?? '@field_reporter').toString();
                    final time = formatVideoTimeAgo(v['created_at'] ?? v['time']);
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 44,
                        height: 44,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color: AppColors.background,
                        ),
                        child: Image.network(
                          thumbUrl.isNotEmpty
                              ? thumbUrl
                              : 'https://picsum.photos/seed/cluster_thumb/100/100',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const Center(
                            child: Icon(Icons.videocam, color: Colors.white24, size: 20),
                          ),
                        ),
                      ),
                      title: Text(
                        v['title']?.toString() ?? '',
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '$author · $time',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.accent),
                      onTap: () {
                        Navigator.pop(modalContext);
                        _openVideoDetail(parentContext, v);
                      },
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Spec #40: Nearby ⚙ Filter & State Settings Sheet
  void _showNearbySettingsSheet(BuildContext parentContext) {
    showModalBottomSheet(
      context: parentContext,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '내 주변 설정 및 화면 상태 확인',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  '기본 정책: 반경 1km 이내 · 최근 1시간 이내 게시된 공개 영상 · 공개 좌표 150m 퍼징',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.map_rounded,
                    color: _nearbyStateMode == 'normal' ? AppColors.accent : AppColors.textMuted,
                  ),
                  title: const Text('실시간 주변 지도 & 피드 (기본 모드)', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                  trailing: _nearbyStateMode == 'normal' ? const Icon(Icons.check_circle, color: AppColors.accent) : null,
                  onTap: () {
                    setState(() => _nearbyStateMode = 'normal');
                    Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.videocam_off_outlined,
                    color: _nearbyStateMode == 'empty' ? AppColors.accent : AppColors.textMuted,
                  ),
                  title: const Text('내 주변 영상 없음 화면 보기', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                  trailing: _nearbyStateMode == 'empty' ? const Icon(Icons.check_circle, color: AppColors.accent) : null,
                  onTap: () {
                    setState(() => _nearbyStateMode = 'empty');
                    Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.location_disabled_rounded,
                    color: _nearbyStateMode == 'denied' ? AppColors.warning : AppColors.textMuted,
                  ),
                  title: const Text('위치 권한 거부 화면 보기', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                  trailing: _nearbyStateMode == 'denied' ? const Icon(Icons.check_circle, color: AppColors.warning) : null,
                  onTap: () {
                    setState(() => _nearbyStateMode = 'denied');
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Spec #42: Nearby Empty Screen
  Widget _buildEmptyNearbyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.radar_rounded, color: AppColors.accent, size: 58),
            const SizedBox(height: 16),
            const Text(
              '아직 주변에 올라온 영상이 없습니다',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '최근 1시간 이내 반경 1km 안에서\n게시된 현장 영상이 없습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13.5, height: 1.5),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CameraScreen()),
                );
              },
              icon: const Icon(Icons.videocam_rounded, size: 18),
              label: const Text('카메라 열기', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => setState(() => _nearbyStateMode = 'normal'),
              child: const Text('지도 모드로 돌아가기', style: TextStyle(color: AppColors.accent)),
            ),
          ],
        ),
      ),
    );
  }

  /// Spec #51.3: Location Denied Screen
  Widget _buildLocationDeniedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off_outlined, color: AppColors.warning, size: 56),
            const SizedBox(height: 16),
            const Text(
              '위치 정보를 사용할 수 없습니다',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '내 주변 1km 현장을 탐색하려면 위치 접근 권한이 필요합니다.\n홈 및 촬영 기능은 위치 권한 없이도 이용 가능합니다.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => setState(() => _nearbyStateMode = 'normal'),
              icon: const Icon(Icons.my_location_rounded, size: 18),
              label: const Text('위치 권한 허용', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeechBubblePainter extends CustomPainter {
  final Color fillColor;
  final Color borderColor;
  final double borderWidth;

  _SpeechBubblePainter({
    required this.fillColor,
    required this.borderColor,
    required this.borderWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..strokeJoin = StrokeJoin.round;

    final double w = size.width;
    final double h = size.height;
    final double r = 7.0;
    final double bodyBottom = h - 8.0;

    final path = Path();
    path.moveTo(r, 0);
    path.lineTo(w - r, 0);
    path.arcToPoint(Offset(w, r), radius: Radius.circular(r));
    path.lineTo(w, bodyBottom - r);
    path.arcToPoint(Offset(w - r, bodyBottom), radius: Radius.circular(r));
    path.lineTo(w * 0.72, bodyBottom);
    path.lineTo(w * 0.65, h);
    path.lineTo(w * 0.52, bodyBottom);
    path.lineTo(r, bodyBottom);
    path.arcToPoint(Offset(0, bodyBottom - r), radius: Radius.circular(r));
    path.lineTo(0, r);
    path.arcToPoint(Offset(r, 0), radius: Radius.circular(r));
    path.close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HeadingArrowPainter extends CustomPainter {
  final Color color;
  _HeadingArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(size.width / 2, 0);
    path.lineTo(size.width, size.height);
    path.lineTo(size.width / 2, size.height * 0.65);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
