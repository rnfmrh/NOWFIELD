import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../constants/app_colors.dart';
import '../services/api_service.dart';
import 'earnings_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

String formatVideoTimeAgo(dynamic createdAtRaw) {
  if (createdAtRaw == null) return '방금 전';
  final str = createdAtRaw.toString().trim();
  if (str.isEmpty) return '방금 전';
  if (str.contains('분 전') || str.contains('시간 전') || str.contains('ago') || str == '방금 전') {
    return str;
  }
  try {
    final normalized = str.endsWith('Z') || str.contains('+') ? str : '${str}Z';
    final dt = DateTime.parse(normalized).toLocal();
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    return '${diff.inDays}일 전';
  } catch (_) {
    return '방금 전';
  }
}

class VideoDetailScreen extends StatefulWidget {
  final Map<String, dynamic> videoData;
  final List<Map<String, dynamic>>? videoList;
  final int initialIndex;

  const VideoDetailScreen({
    super.key,
    required this.videoData,
    this.videoList,
    this.initialIndex = 0,
  });

  @override
  State<VideoDetailScreen> createState() => _VideoDetailScreenState();
}

class _VideoDetailScreenState extends State<VideoDetailScreen> {
  late final List<Map<String, dynamic>> _items;
  late final PageController _pageController;
  late int _currentIndex;
  DateTime _lastWheelScroll = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    if (widget.videoList != null && widget.videoList!.isNotEmpty) {
      _items = widget.videoList!;
      _currentIndex = widget.initialIndex.clamp(0, _items.length - 1);
    } else {
      _items = [widget.videoData];
      _currentIndex = 0;
    }
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent && _items.length > 1) {
      final now = DateTime.now();
      if (now.difference(_lastWheelScroll).inMilliseconds < 450) return;
      if (event.scrollDelta.dy > 18 && _currentIndex < _items.length - 1) {
        _lastWheelScroll = now;
        _pageController.nextPage(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      } else if (event.scrollDelta.dy < -18 && _currentIndex > 0) {
        _lastWheelScroll = now;
        _pageController.previousPage(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Listener(
        onPointerSignal: _handlePointerSignal,
        child: Stack(
          children: [
            ScrollConfiguration(
              behavior: const MaterialScrollBehavior().copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                },
              ),
              child: PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                itemCount: _items.length,
                onPageChanged: (idx) {
                  setState(() => _currentIndex = idx);
                },
                itemBuilder: (context, index) {
                  return VideoFeedItem(
                    index: index,
                    videoData: _items[index],
                    showBackButton: true,
                  );
                },
              ),
            ),
            if (_items.length > 1)
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24, width: 0.8),
                  ),
                  child: Text(
                    '${_currentIndex + 1} / ${_items.length}',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> _videos = [];
  bool _isLoading = true;
  String _selectedTab = 'recommended'; // Spec #6: recommended, latest, following

  @override
  void initState() {
    super.initState();
    _loadFeed();
    ApiService.feedFilterVersionNotifier.addListener(_loadFeed);
    ApiService.currentUserNotifier.addListener(_loadFeed);
  }

  @override
  void dispose() {
    ApiService.feedFilterVersionNotifier.removeListener(_loadFeed);
    ApiService.currentUserNotifier.removeListener(_loadFeed);
    super.dispose();
  }

  Future<void> _loadFeed() async {
    final list = await ApiService.getFeedVideos(tab: _selectedTab);
    if (mounted) {
      setState(() {
        _videos = list;
        _isLoading = false;
      });
    }
  }

  void _selectTab(String tab) {
    if (_selectedTab == tab) return;
    setState(() {
      _selectedTab = tab;
      _isLoading = true;
    });
    _loadFeed();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildFeedTabButton('추천', 'recommended'),
            const SizedBox(width: 16),
            _buildFeedTabButton('최신', 'latest'),
            const SizedBox(width: 16),
            _buildFeedTabButton('팔로잉', 'following'),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh, color: AppColors.textPrimary, size: 22),
            onPressed: () {
              setState(() => _isLoading = true);
              _loadFeed();
            },
          ),
          IconButton(
            tooltip: '검색',
            icon: const Icon(Icons.search, color: AppColors.textPrimary, size: 24),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SearchScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : RefreshIndicator(
              onRefresh: _loadFeed,
              color: AppColors.accent,
              backgroundColor: AppColors.card,
              child: _videos.isEmpty
                  ? _buildEmptyFeedState()
                  : ScrollConfiguration(
                      behavior: const MaterialScrollBehavior().copyWith(
                        dragDevices: {
                          PointerDeviceKind.touch,
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.trackpad,
                        },
                      ),
                      child: PageView.builder(
                        scrollDirection: Axis.vertical,
                        itemCount: _videos.length + 1,
                        itemBuilder: (context, index) {
                          if (index == _videos.length) {
                            return _buildSponsoredAdCard(context);
                          }
                          return VideoFeedItem(
                            index: index,
                            videoData: _videos[index] as Map<String, dynamic>,
                            allVideos: _videos,
                          );
                        },
                      ),
                    ),
            ),
    );
  }

  Widget _buildFeedTabButton(String label, String tabKey) {
    final isSelected = _selectedTab == tabKey;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _selectTab(tabKey),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white60,
              fontSize: isSelected ? 15 : 13.5,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
              shadows: const [
                Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: isSelected ? 22 : 0,
            height: 2.5,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyFeedState() {
    if (_selectedTab == 'following') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.people_outline_rounded, color: AppColors.accent, size: 54),
              const SizedBox(height: 14),
              const Text(
                '팔로우한 사용자의 영상이 없습니다',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '관심 있는 현장 기록자를 팔로우하거나\n추천 피드에서 실시간 현장을 둘러보세요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _selectTab('recommended'),
                icon: const Icon(Icons.explore_outlined, size: 18),
                label: const Text(
                  '현장 둘러보기',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_off_outlined, color: Colors.white38, size: 48),
          const SizedBox(height: 12),
          const Text(
            '현재 표시할 현장 영상이 없습니다.',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: _loadFeed,
            child: const Text('다시 불러오기'),
          ),
        ],
      ),
    );
  }

  Widget _buildSponsoredAdCard(BuildContext context) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.accent.withOpacity(0.35), width: 1.2),
            boxShadow: const [
              BoxShadow(color: Colors.black45, blurRadius: 16, offset: Offset(0, 6)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.warning, width: 0.8),
                    ),
                    child: const Text(
                      '광고 · 스폰서',
                      style: TextStyle(color: AppColors.warning, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Text(
                    '광고 순수익 30% 크리에이터 풀 배분',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  'https://picsum.photos/seed/nowfield_ad/800/450',
                  height: 190,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 190,
                    color: AppColors.background,
                    child: const Center(child: Icon(Icons.campaign_outlined, color: AppColors.accent, size: 48)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '나우필드 미디어 파트너',
                style: TextStyle(color: AppColors.accent, fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                '글로벌 미디어·보도기관을 위한 실시간 현장 영상 라이선스 네트워크',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold, height: 1.35),
              ),
              const SizedBox(height: 6),
              const Text(
                '일반 현장 영상과 명확히 구분되는 네이티브 광고 슬롯입니다. 확정 광고 순수익의 30%는 크리에이터 풀에 적립되어 시청 품질 기준으로 배분됩니다.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.45),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const EarningsScreen(initialTabIndex: 0)),
                    );
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text(
                    '자세히 알아보기 (수익 배분 구조)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Marquee text widget that scrolls horizontally when text overflows single line
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  late final ScrollController _scrollController;
  bool _isScrolling = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScrolling());
  }

  void _startScrolling() async {
    if (!mounted || !_scrollController.hasClients || _isScrolling) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return;

    _isScrolling = true;
    while (mounted && _scrollController.hasClients) {
      await Future.delayed(const Duration(milliseconds: 1800));
      if (!mounted || !_scrollController.hasClients) break;
      await _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: Duration(milliseconds: (maxScroll * 35).toInt().clamp(2000, 10000)),
        curve: Curves.linear,
      );
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted || !_scrollController.hasClients) break;
      _scrollController.jumpTo(0.0);
    }
    _isScrolling = false;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(
        widget.text,
        style: widget.style,
        maxLines: 1,
      ),
    );
  }
}

class VideoFeedItem extends StatefulWidget {
  final int index;
  final Map<String, dynamic> videoData;
  final bool showBackButton;
  final List<dynamic>? allVideos;

  const VideoFeedItem({
    super.key,
    required this.index,
    required this.videoData,
    this.showBackButton = false,
    this.allVideos,
  });

  @override
  State<VideoFeedItem> createState() => _VideoFeedItemState();
}

class _VideoFeedItemState extends State<VideoFeedItem> {
  VideoPlayerController? _videoController;
  bool _isVideoReady = false;
  bool _isPlaying = true;
  bool _isLiked = false;
  late int _likeCount;
  late int _commentCount;
  String _captionLang = ApiService.defaultCaptionLangNotifier.value; // 원문, 영어, 일본어, 한국어, 꺼짐

  @override
  void initState() {
    super.initState();
    final savedLang = ApiService.defaultCaptionLangNotifier.value;
    _captionLang = (savedLang == 'Original') ? '원문' : (savedLang == 'Off' ? '꺼짐' : savedLang);
    _syncCountsFromData();
    _initVideoPlayer();
  }

  String _translateCaptionText(String raw, String lang) {
    if (lang == '꺼짐' || lang == 'Off') return '';
    if (lang == '원문' || lang == 'Original' || lang == '한국어') return raw;
    if (lang == '영어' || lang == 'English') {
      if (raw.contains('백화점')) return '[영어 번역] Heavy traffic congestion in front of Apgujeong Department Store. Please drive slowly.';
      if (raw.contains('버스')) return '[영어 번역] Long queue at the bus stop outside Apgujeong Station Exit 3 during rush hour.';
      if (raw.contains('로데오') || raw.contains('카페')) return '[영어 번역] Lively crowd at Sinsa Garosu-gil & Apgujeong cafes right now.';
      if (raw.contains('자전거') || raw.contains('한강')) return '[영어 번역] Partial detour on Han River Jamwon bike path due to maintenance work.';
      return '[영어 자동번역] Live field update: $raw';
    }
    if (lang == '일본어' || lang == '日本語') {
      if (raw.contains('백화점')) return '[일본어 번역] 狎鴎亭デパート前で激しい交通渋滞が発生しています。徐行してください。';
      if (raw.contains('버스')) return '[일본어 번역] 退勤時間帯、狎鴎亭駅3番出口のバス停に長い待機列ができています。';
      if (raw.contains('로데오') || raw.contains('카페')) return '[일본어 번역] 新沙カロスキル・カフェ周辺のリアルタイム混雑状況です。';
      if (raw.contains('자전거') || raw.contains('한강')) return '[일본어 번역] 漢江蚕院地区の自転車道路は補修工事のため一部迂回が必要です。';
      return '[일본어 자동번역] 現場リアルタイム字幕: $raw';
    }
    return raw;
  }

  /// Spec #7 & #30: CC Subtitles & Translation Bottom Sheet
  void _showCaptionSheet(BuildContext parentContext) {
    const langs = ['원문', '영어', '일본어', '한국어', '꺼짐'];
    showModalBottomSheet(
      context: parentContext,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.closed_caption_rounded, color: AppColors.accent, size: 22),
                    SizedBox(width: 8),
                    Text(
                      '자막 및 자동 번역 설정',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  '번역은 자막 텍스트만 변경하며 현장의 원본 음성은 그대로 유지됩니다.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: langs.map((lang) {
                    final selected = _captionLang == lang;
                    return ChoiceChip(
                      label: Text(lang),
                      selected: selected,
                      selectedColor: AppColors.primary,
                      backgroundColor: AppColors.background,
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : AppColors.textMuted,
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (_) {
                        setState(() => _captionLang = lang);
                        if (lang != '꺼짐') {
                          ApiService.defaultCaptionLangNotifier.value = lang;
                        }
                        Navigator.pop(ctx);
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _syncCountsFromData() {
    _likeCount = int.tryParse(widget.videoData['like_count']?.toString() ?? '0') ?? 0;
    _commentCount = int.tryParse(widget.videoData['comment_count']?.toString() ?? '0') ?? 0;
    _isLiked = widget.videoData['is_liked'] == true;
  }

  @override
  void didUpdateWidget(covariant VideoFeedItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoData['id'] != widget.videoData['id']) {
      _syncCountsFromData();
    }
    if (oldWidget.videoData['video_url'] != widget.videoData['video_url']) {
      _disposeVideoPlayer();
      _initVideoPlayer();
    }
  }

  Future<void> _handleToggleLike() async {
    final videoId = widget.videoData['id']?.toString() ?? '';
    setState(() {
      _isLiked = !_isLiked;
      _likeCount = _isLiked ? _likeCount + 1 : math.max(0, _likeCount - 1);
      widget.videoData['like_count'] = _likeCount;
      widget.videoData['is_liked'] = _isLiked;
    });

    if (videoId.isEmpty) return;
    final res = await ApiService.toggleLike(videoId);
    if (mounted && res.isNotEmpty) {
      setState(() {
        if (res.containsKey('liked')) {
          _isLiked = res['liked'] == true;
          widget.videoData['is_liked'] = _isLiked;
        }
        if (res.containsKey('like_count')) {
          _likeCount = (res['like_count'] as num).toInt();
          widget.videoData['like_count'] = _likeCount;
        }
      });
    }
  }

  void _openUserProfile(BuildContext context, {String? userId, String? username}) {
    final wasPlaying = _videoController != null && _videoController!.value.isPlaying;
    if (wasPlaying) {
      _videoController?.pause();
      setState(() => _isPlaying = false);
    }
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          targetUserId: userId ?? username,
          targetUsername: username,
        ),
      ),
    )
        .then((_) {
      if (mounted && wasPlaying && _videoController != null) {
        _videoController!.play();
        setState(() => _isPlaying = true);
      }
    });
  }

  void _showOriginalCaptureDialog(BuildContext context) {
    final locationName = widget.videoData['location_name']?.toString() ?? '서울';
    final createdAt = widget.videoData['created_at']?.toString() ?? '방금 전';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.verified_rounded, color: AppColors.accent, size: 22),
            SizedBox(width: 8),
            Text(
              '원본 촬영 인증',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'NOWFIELD 현장 직찍 인증\n\n'
          '• 촬영 위치: $locationName\n'
          '• 게시 시각: $createdAt\n\n'
          'NOWFIELD 앱 카메라에서 편집 없이 원테이크로 직접 촬영된 현장 영상입니다.',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  void _handleShare(BuildContext parentContext) {
    final videoId = widget.videoData['id']?.toString() ?? 'field';
    final title = widget.videoData['title']?.toString() ?? 'NOWFIELD 현장 영상';
    final uploaderName = widget.videoData['uploader_name']?.toString() ?? '@seoul_walker';
    final locationName = widget.videoData['location_name']?.toString() ?? 'Seoul';
    final thumbUrl = ApiService.resolveMediaUrl(
      (widget.videoData['thumbnail_url'] ?? widget.videoData['preview_url']) as String?,
    );
    final shareUrl = 'https://nowfield.app/v/$videoId';
    bool isCopied = false;

    showModalBottomSheet(
      context: parentContext,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            void copyLink({String? channelName}) {
              Clipboard.setData(ClipboardData(text: '$title - $shareUrl'));
              setSheetState(() => isCopied = true);
              if (channelName != null) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(parentContext).showSnackBar(
                  SnackBar(
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    backgroundColor: AppColors.card,
                    content: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: AppColors.accent, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '$channelName 공유용 링크가 복사되었습니다.',
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '현장 영상 공유하기',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 22),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Video preview card inside share sheet
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.cardBorder.withOpacity(0.5)),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 56,
                              height: 56,
                              child: thumbUrl.isNotEmpty
                                  ? Image.network(
                                      thumbUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        color: AppColors.card,
                                        child: const Icon(Icons.videocam, color: Colors.white24),
                                      ),
                                    )
                                  : Container(
                                      color: AppColors.card,
                                      child: const Icon(Icons.videocam, color: Colors.white24),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$uploaderName · $locationName',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.accent.withOpacity(0.4)),
                            ),
                            child: const Text(
                              '원본 촬영',
                              style: TextStyle(color: AppColors.accent, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Share channel buttons row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildShareChannelItem(
                          icon: Icons.link_rounded,
                          label: '링크 복사',
                          bgColor: AppColors.primary,
                          iconColor: Colors.white,
                          onTap: () => copyLink(channelName: '클립보드'),
                        ),
                        _buildShareChannelItem(
                          icon: Icons.chat_bubble_rounded,
                          label: '카카오톡',
                          bgColor: const Color(0xFFFEE500),
                          iconColor: const Color(0xFF191919),
                          onTap: () => copyLink(channelName: '카카오톡'),
                        ),
                        _buildShareChannelItem(
                          icon: Icons.sms_rounded,
                          label: '메시지',
                          bgColor: const Color(0xFF34C759),
                          iconColor: Colors.white,
                          onTap: () => copyLink(channelName: '메시지'),
                        ),
                        _buildShareChannelItem(
                          icon: Icons.alternate_email_rounded,
                          label: 'SNS 공유',
                          bgColor: const Color(0xFF1DA1F2),
                          iconColor: Colors.white,
                          onTap: () => copyLink(channelName: 'SNS'),
                        ),
                        _buildShareChannelItem(
                          icon: Icons.ios_share_rounded,
                          label: 'OS 공유',
                          bgColor: AppColors.background,
                          iconColor: AppColors.accent,
                          onTap: () => copyLink(channelName: '시스템'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Direct URL copy bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.cardBorder.withOpacity(0.6)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.public_rounded, color: AppColors.textMuted, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              shareUrl,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 32,
                            child: ElevatedButton.icon(
                              onPressed: () => copyLink(),
                              icon: Icon(
                                isCopied ? Icons.check_rounded : Icons.copy_rounded,
                                size: 14,
                              ),
                              label: Text(
                                isCopied ? '복사됨' : '복사',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isCopied ? Colors.green.shade600 : AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildShareChannelItem({
    required IconData icon,
    required String label,
    required Color bgColor,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white12, width: 1),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
              ],
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _initVideoPlayer() async {
    final videoUrl = ApiService.resolveMediaUrl(widget.videoData['video_url'] as String?);
    if (videoUrl.isEmpty) return;

    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      _videoController = controller;
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (mounted) {
        setState(() {
          _isVideoReady = true;
          _isPlaying = true;
        });
      }
    } catch (_) {
      // Fallback to preview/thumbnail image if video player initialization fails
    }
  }

  void _disposeVideoPlayer() {
    _videoController?.dispose();
    _videoController = null;
    _isVideoReady = false;
  }

  void _togglePlayPause() {
    final controller = _videoController;
    if (controller == null || !_isVideoReady) return;
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
        _isPlaying = false;
      } else {
        controller.play();
        _isPlaying = true;
      }
    });
  }

  @override
  void dispose() {
    _disposeVideoPlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final videoData = widget.videoData;
    final index = widget.index;
    final title = videoData['title'] as String? ?? 'NOWFIELD Field Recording';
    final subtitleRaw = videoData['subtitle'] as String? ?? '';
    final locationName = videoData['location_name'] as String? ?? 'Seoul';
    final uploaderName = videoData['uploader_name'] as String? ?? '@field_contributor';
    final timeAgo = formatVideoTimeAgo(videoData['created_at'] ?? videoData['time']);
    final previewUrl = ApiService.resolveMediaUrl(
      (videoData['thumbnail_url'] ?? videoData['preview_url']) as String?,
    );
    final likeCount = videoData['like_count']?.toString() ?? '0';
    final commentCount = videoData['comment_count']?.toString() ?? '0';

    // Parse auto-subtitles if available
    String rawCaption = subtitleRaw.isNotEmpty ? subtitleRaw : title;
    if (videoData.containsKey('subtitles_json') && videoData['subtitles_json'] != null) {
      try {
        final decoded = json.decode(videoData['subtitles_json']);
        if (decoded is List && decoded.isNotEmpty) {
          rawCaption = decoded[0]['text'] ?? rawCaption;
        }
      } catch (_) {}
    }
    final String displaySubtitle = _translateCaptionText(rawCaption, _captionLang);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePlayPause,
      // Spec #27: Long Press pauses video while held
      onLongPressStart: (_) {
        if (_videoController != null && _isVideoReady && _videoController!.value.isPlaying) {
          _videoController!.pause();
          setState(() => _isPlaying = false);
        }
      },
      onLongPressEnd: (_) {
        if (_videoController != null && _isVideoReady && !_videoController!.value.isPlaying) {
          _videoController!.play();
          setState(() => _isPlaying = true);
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Video Player or Preview / Thumbnail Background
          if (_isVideoReady && _videoController != null)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: _videoController!.value.size.width > 0 ? _videoController!.value.size.width : 720,
                height: _videoController!.value.size.height > 0 ? _videoController!.value.size.height : 1280,
                child: VideoPlayer(_videoController!),
              ),
            )
          else if (previewUrl.isNotEmpty)
            Image.network(
              previewUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: AppColors.background,
                  child: const Center(
                    child: Icon(Icons.videocam_off, color: Colors.white24, size: 60),
                  ),
                );
              },
            )
          else
            Image.network(
              'https://picsum.photos/seed/${index + 10}/800/1600',
              fit: BoxFit.cover,
            ),

          // Pause indicator overlay (Spec #27: Tap -> Pause / Play)
          if (_isVideoReady && !_isPlaying)
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 48),
              ),
            ),

          // Gradient overlay for better contrast and text readability
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.background.withOpacity(0.6),
                  Colors.transparent,
                  AppColors.background.withOpacity(0.4),
                  AppColors.background.withOpacity(0.92),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.25, 0.7, 1.0],
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Stack(
              children: [
                // Back button when opened as full-screen VideoDetailScreen from Nearby
                if (widget.showBackButton)
                  Positioned(
                    top: 6,
                    left: 8,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 22),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),

                // Top Left Title: 1 line + Marquee, moved slightly higher up
                Positioned(
                  top: 10,
                  left: widget.showBackButton ? 48 : 16,
                  right: 56,
                  child: MarqueeText(
                    text: title,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      shadows: [
                        Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 1)),
                      ],
                    ),
                  ),
                ),

                // Bottom Left: Subtitles + User Info stacked in a single Column so they never overlap
                Positioned(
                  bottom: 18,
                  left: 16,
                  right: 75,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (displaySubtitle.isNotEmpty) ...[
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _showCaptionSheet(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.subtitleBackground,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppColors.accent.withOpacity(0.25),
                                width: 0.6,
                              ),
                            ),
                            child: Text(
                              displaySubtitle,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 15,
                                height: 1.3,
                                fontWeight: FontWeight.w400,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _openUserProfile(
                              context,
                              userId: videoData['uploader_id']?.toString(),
                              username: uploaderName,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppColors.accent, width: 1.2),
                                  ),
                                  child: ClipOval(
                                    child: Image.network(
                                      'https://i.pravatar.cc/100?img=${(uploaderName.hashCode.abs() % 20) + 1}',
                                      width: 34,
                                      height: 34,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) => Container(
                                        width: 34,
                                        height: 34,
                                        color: AppColors.card,
                                        child: const Icon(Icons.person, color: AppColors.accent, size: 20),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  uploaderName,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _showOriginalCaptureDialog(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.85),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '원본 촬영',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          // Spec #7 & #30: CC Subtitle & Translation Toggle Pill
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _showCaptionSheet(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.subtitleBackground,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.accent.withOpacity(0.45), width: 0.7),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.closed_caption_rounded, size: 12, color: AppColors.accent),
                                  const SizedBox(width: 3),
                                  Text(
                                    '자막 · $_captionLang',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.accent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.location_on, size: 14, color: AppColors.accent),
                              const SizedBox(width: 4),
                              Text(
                                '$locationName · $timeAgo',
                                style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                              ),
                            ],
                          ),
                          // Spec #9 & #53.3: Multiple Angles
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _showMultipleAnglesSheet(context, locationName),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.card.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.accent.withOpacity(0.45), width: 0.8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.switch_video_outlined, size: 12, color: AppColors.accent),
                                  SizedBox(width: 4),
                                  Text(
                                    '이 장소의 다른 시선 3개',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: AppColors.accent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Right Actions
                Positioned(
                  bottom: 16,
                  right: 10,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _buildActionIcon(
                        icon: _isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        iconColor: _isLiked ? Colors.redAccent : AppColors.textPrimary,
                        label: _likeCount.toString(),
                        onTap: _handleToggleLike,
                      ),
                      const SizedBox(height: 12),
                      _buildActionIcon(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: _commentCount.toString(),
                        onTap: () => _showCommentsBottomSheet(context),
                      ),
                      const SizedBox(height: 12),
                      _buildActionIcon(
                        icon: Icons.reply,
                        flipIcon: true,
                        label: '공유',
                        onTap: () => _handleShare(context),
                      ),
                      const SizedBox(height: 12),
                      IconButton(
                        icon: const Icon(Icons.more_horiz, color: AppColors.textPrimary, size: 28),
                        onPressed: () => _showMoreBottomSheet(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionIcon({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color iconColor = AppColors.textPrimary,
    bool flipIcon = false,
  }) {
    Widget iconWidget = Icon(
      icon,
      color: iconColor,
      size: 30,
      shadows: const [
        Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1)),
      ],
    );

    if (flipIcon) {
      iconWidget = Transform(
        alignment: Alignment.center,
        transform: Matrix4.rotationY(math.pi),
        child: iconWidget,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Column(
          children: [
            iconWidget,
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                shadows: [
                  Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCommentsBottomSheet(BuildContext parentContext) {
    final videoId = widget.videoData['id']?.toString() ?? '';
    final TextEditingController textController = TextEditingController();
    List<Map<String, dynamic>> comments = [];
    bool isLoadingComments = true;
    bool isSubmitting = false;

    showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            if (isLoadingComments) {
              isLoadingComments = false;
              if (videoId.isNotEmpty) {
                ApiService.getComments(videoId).then((fetched) {
                  if (ctx.mounted) {
                    setSheetState(() {
                      comments = fetched;
                    });
                    if (mounted && fetched.length > _commentCount) {
                      setState(() {
                        _commentCount = fetched.length;
                        widget.videoData['comment_count'] = _commentCount;
                      });
                    }
                  }
                });
              }
            }

            Future<void> submitComment() async {
              final text = textController.text.trim();
              if (text.isEmpty || isSubmitting) return;
              setSheetState(() => isSubmitting = true);
              textController.clear();

              Map<String, dynamic> created = {};
              if (videoId.isNotEmpty) {
                created = await ApiService.postComment(videoId, text);
              }
              if (created.isEmpty) {
                created = {
                  'id': 'cmt_local_${DateTime.now().millisecondsSinceEpoch}',
                  'video_id': videoId,
                  'user_id': 'u_seoul_walker',
                  'username': '@seoul_walker',
                  'content': text,
                  'created_at': DateTime.now().toUtc().toIso8601String(),
                };
              }

              if (ctx.mounted) {
                setSheetState(() {
                  comments.insert(0, created);
                  isSubmitting = false;
                });
              }
              if (mounted) {
                setState(() {
                  _commentCount += 1;
                  widget.videoData['comment_count'] = _commentCount;
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SafeArea(
                child: SizedBox(
                  height: MediaQuery.of(ctx).size.height * 0.62,
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '댓글 $_commentCount개',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: AppColors.textMuted, size: 20),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                      ),
                      const Divider(color: Colors.white12, height: 1),
                      Expanded(
                        child: comments.isEmpty
                            ? const Center(
                                child: Text(
                                  '아직 작성된 현장 댓글이 없습니다.\n첫 번째 댓글을 남겨보세요!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: AppColors.textMuted, fontSize: 14, height: 1.5),
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                itemCount: comments.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 14),
                                itemBuilder: (context, idx) {
                                  final c = comments[idx];
                                  final username = c['username']?.toString() ?? '@seoul_walker';
                                  final content = c['content']?.toString() ?? '';
                                  final timeStr = formatVideoTimeAgo(c['created_at']);
                                  return Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      GestureDetector(
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          _openUserProfile(
                                            parentContext,
                                            userId: c['user_id']?.toString(),
                                            username: username,
                                          );
                                        },
                                        child: CircleAvatar(
                                          radius: 16,
                                          backgroundColor: AppColors.background,
                                          child: Text(
                                            username.replaceAll('@', '').isNotEmpty
                                                ? username.replaceAll('@', '')[0].toUpperCase()
                                                : 'U',
                                            style: const TextStyle(
                                              color: AppColors.accent,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                GestureDetector(
                                                  onTap: () {
                                                    Navigator.pop(ctx);
                                                    _openUserProfile(
                                                      parentContext,
                                                      userId: c['user_id']?.toString(),
                                                      username: username,
                                                    );
                                                  },
                                                  child: Text(
                                                    username,
                                                    style: const TextStyle(
                                                      color: AppColors.textMuted,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  timeStr,
                                                  style: const TextStyle(
                                                    color: Colors.white38,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              content,
                                              style: const TextStyle(
                                                color: AppColors.textPrimary,
                                                fontSize: 14,
                                                height: 1.35,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: '댓글 신고',
                                        icon: const Icon(Icons.flag_outlined, color: Colors.white38, size: 16),
                                        onPressed: () {
                                          Navigator.pop(ctx);
                                          _showReportDialog(parentContext, videoId, isComment: true);
                                        },
                                      ),
                                    ],
                                  );
                                },
                              ),
                      ),
                      const Divider(color: Colors.white12, height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: textController,
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => submitComment(),
                                decoration: InputDecoration(
                                  hintText: '현장 상황에 대한 댓글을 남겨보세요...',
                                  hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                                  filled: true,
                                  fillColor: AppColors.background,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    borderSide: BorderSide(color: AppColors.cardBorder.withOpacity(0.5)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    borderSide: BorderSide(color: AppColors.cardBorder.withOpacity(0.5)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    borderSide: const BorderSide(color: AppColors.accent),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              style: IconButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.send_rounded, size: 18),
                              onPressed: submitComment,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showMoreBottomSheet(BuildContext context) {
    final videoId = widget.videoData['id'] as String? ?? '';
    final uploaderName = widget.videoData['uploader_name'] as String? ?? '@user';
    final licensePrice = widget.videoData['license_price'] ?? 10000;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if ((licensePrice is int ? licensePrice : int.tryParse('$licensePrice') ?? 0) > 0) ...[
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.monetization_on_outlined, color: AppColors.accent, size: 24),
                  ),
                  title: const Text(
                    '영상 라이선스 구매',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    '표준 판매가 ₩$licensePrice (크리에이터 80% 정산)',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: AppColors.accent),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showLicenseConfirmation(context, videoId, licensePrice);
                  },
                ),
                const Divider(color: Colors.white12, height: 1),
              ] else ...[
                const ListTile(
                  leading: Icon(Icons.money_off_csred_outlined, color: AppColors.textMuted, size: 22),
                  title: Text(
                    '라이선스 판매 비활성화',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                  ),
                  subtitle: Text(
                    '크리에이터가 이 영상의 라이선스 판매를 껐습니다.',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
                const Divider(color: Colors.white12, height: 1),
              ],
              _buildBottomSheetItem(
                Icons.bookmark_border,
                '저장하기',
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('영상이 북마크에 저장되었습니다.'),
                      backgroundColor: AppColors.primary,
                    ),
                  );
                },
              ),
              _buildBottomSheetItem(
                Icons.report_outlined,
                '신고하기',
                color: Colors.redAccent,
                onTap: () {
                  Navigator.pop(ctx);
                  _showReportDialog(context, videoId);
                },
              ),
              _buildBottomSheetItem(
                Icons.block,
                '$uploaderName 차단하기',
                onTap: () {
                  Navigator.pop(ctx);
                  ApiService.blockUser(uploaderName);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$uploaderName 사용자를 차단하여 피드에서 제외했습니다. (설정 > 차단한 사용자에서 해제 가능)'),
                      backgroundColor: AppColors.card,
                    ),
                  );
                },
              ),
              _buildBottomSheetItem(
                Icons.visibility_off_outlined,
                '관심 없음',
                onTap: () {
                  Navigator.pop(ctx);
                  ApiService.markNotInterested(videoId);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('해당 영상을 피드에서 숨기고 유사 추천 노출을 줄입니다.'),
                      backgroundColor: AppColors.card,
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// Spec #9 & #53.3: Multiple Angles Bottom Sheet
  void _showMultipleAnglesSheet(BuildContext parentContext, String locationName) {
    final rawPool = widget.allVideos ?? [widget.videoData];
    final angles = rawPool
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .take(4)
        .toList();

    showModalBottomSheet(
      context: parentContext,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.switch_video_rounded, color: AppColors.accent, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$locationName의 다른 시선 ${angles.length}개',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  '동일 장소·시간대에 여러 사용자가 독립적으로 촬영한 현장 기록을 비교해 볼 수 있습니다.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 14),
                ...List.generate(angles.length, (i) {
                  final v = angles[i];
                  final isCurrent = v['id'] == widget.videoData['id'];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isCurrent ? AppColors.primary.withOpacity(0.2) : AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isCurrent ? AppColors.accent : AppColors.cardBorder,
                      ),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor: AppColors.card,
                        child: Text(
                          'A${i + 1}',
                          style: const TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(
                        v['title']?.toString() ?? '현장 영상',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${v['uploader_name'] ?? '@user'} · ${v['location_name'] ?? locationName}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                      ),
                      trailing: isCurrent
                          ? const Text('현재 시청 중', style: TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.bold))
                          : const Icon(Icons.play_circle_fill_rounded, color: AppColors.accent, size: 22),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.of(parentContext).push(
                          MaterialPageRoute(
                            builder: (_) => VideoDetailScreen(
                              videoData: v,
                              videoList: angles,
                              initialIndex: i,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showReportDialog(BuildContext context, String videoId, {bool isComment = false}) {
    final reasons = <Map<String, String>>[
      {'key': 'sexual_content', 'label': '성적·음란 콘텐츠'},
      {'key': 'violence', 'label': '폭력·위험 행위'},
      {'key': 'privacy', 'label': '개인정보 침해'},
      {'key': 'harassment', 'label': '괴롭힘·혐오 표현'},
      {'key': 'misleading', 'label': '허위·오해 소지 정보'},
      {'key': 'copyright', 'label': '저작권 침해'},
      {'key': 'spam', 'label': '스팸·광고'},
      {'key': 'other', 'label': '기타'},
    ];
    String selectedReason = reasons.first['key']!;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.card,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(
                isComment ? '댓글 신고하기' : '신고 사유 선택',
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: reasons
                      .map(
                        (r) => RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          activeColor: AppColors.accent,
                          title: Text(
                            r['label']!,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                          ),
                          value: r['key']!,
                          groupValue: selectedReason,
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => selectedReason = val);
                            }
                          },
                        ),
                      )
                      .toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('취소', style: TextStyle(color: AppColors.textMuted)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    if (videoId.isNotEmpty) {
                      await ApiService.reportContent(
                        videoId: videoId,
                        reason: selectedReason,
                        details: isComment ? 'Comment report' : 'Video report',
                      );
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isComment ? '댓글 신고가 접수되었습니다.' : '영상 신고가 접수되었습니다.'),
                          backgroundColor: AppColors.primary,
                        ),
                      );
                    }
                  },
                  child: const Text('신고 제출'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showLicenseConfirmation(BuildContext context, String videoId, dynamic price) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.verified, color: AppColors.accent, size: 22),
              SizedBox(width: 8),
              Text('라이선스 구매', style: TextStyle(color: AppColors.textPrimary, fontSize: 18)),
            ],
          ),
          content: Text(
            'NOWFIELD의 검증된 원본 촬영 영상을 보도 및 상업적 용도로 활용할 수 있는 사용권을 구매합니다.\n\n'
            '• 판매 금액: ₩$price\n'
            '• 크리에이터 정산(80%): ₩${(price * 0.8).toInt()}\n'
            '• 플랫폼 수수료(20%): ₩${(price * 0.2).toInt()}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소', style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                await ApiService.purchaseLicense(videoId);
                if (context.mounted) {
                  // Spec #44: License purchased completion modal
                  showDialog(
                    context: context,
                    builder: (doneCtx) => AlertDialog(
                      backgroundColor: AppColors.card,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: Row(
                        children: const [
                          Icon(Icons.check_circle_rounded, color: AppColors.success, size: 24),
                          SizedBox(width: 8),
                          Text(
                            '라이선스 구매 완료',
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      content: const Text(
                        '이 영상의 상업적 사용권(표준 상업 라이선스)이 발급되었습니다.\n라이선스 관리 화면에서 언제든 확인하실 수 있습니다.',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13.5, height: 1.45),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(doneCtx),
                          child: const Text('닫기', style: TextStyle(color: AppColors.textMuted)),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            Navigator.pop(doneCtx);
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const EarningsScreen(initialTabIndex: 1)),
                            );
                          },
                          icon: const Icon(Icons.workspace_premium_outlined, size: 16),
                          label: const Text('구매한 라이선스 보기'),
                        ),
                      ],
                    ),
                  );
                }
              },
              child: Text('구매 진행 (₩$price)'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBottomSheetItem(
    IconData icon,
    String title, {
    Color color = AppColors.textPrimary,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: color, size: 22),
      title: Text(title, style: TextStyle(color: color, fontSize: 15)),
      onTap: onTap ?? () {},
    );
  }
}
