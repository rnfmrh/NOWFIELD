import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../services/api_service.dart';
import 'earnings_screen.dart';
import 'home_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String? targetUserId;
  final String? targetUsername;

  const ProfileScreen({
    super.key,
    this.targetUserId,
    this.targetUsername,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _profileData;
  List<Map<String, dynamic>> _allUsers = [];
  bool _isFollowing = false;
  int _followerCount = 0;

  bool get _isViewingOtherUser {
    if (widget.targetUserId == null) return false;
    final currentId = ApiService.currentUser?['id']?.toString();
    final currentUsername = ApiService.currentUser?['username']?.toString();
    final resolvedId = (_profileData?['user'] as Map?)?['id']?.toString() ?? widget.targetUserId;
    if (currentId != null && resolvedId == currentId) return false;
    if (currentUsername != null && widget.targetUsername == currentUsername) return false;
    return true;
  }

  @override
  void initState() {
    super.initState();
    ApiService.currentUserNotifier.addListener(_onAuthChanged);
    _loadProfileData();
  }

  @override
  void dispose() {
    ApiService.currentUserNotifier.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) {
      _loadProfileData();
    }
  }

  Future<void> _loadProfileData() async {
    final currentUser = ApiService.currentUser;
    if (widget.targetUserId == null && currentUser == null) {
      final users = await ApiService.getAllUsers();
      if (mounted) {
        setState(() {
          _profileData = null;
          _allUsers = users;
          _isLoading = false;
        });
      }
      return;
    }

    setState(() => _isLoading = true);
    final lookupId = widget.targetUserId ??
        widget.targetUsername ??
        currentUser?['id']?.toString() ??
        'u_seoul_walker';
    final results = await Future.wait([
      ApiService.getUserProfile(lookupId),
      ApiService.getAllUsers(),
    ]);

    if (mounted) {
      final data = results[0] as Map<String, dynamic>;
      setState(() {
        _profileData = data;
        _allUsers = results[1] as List<Map<String, dynamic>>;
        _isFollowing = data['is_following'] == true;
        _followerCount = (data['follower_count'] as num?)?.toInt() ?? 0;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleToggleFollow() async {
    final targetId = (_profileData?['user'] as Map?)?['id']?.toString() ??
        widget.targetUserId ??
        widget.targetUsername ??
        '';
    setState(() {
      _isFollowing = !_isFollowing;
      _followerCount = _isFollowing ? _followerCount + 1 : (_followerCount > 0 ? _followerCount - 1 : 0);
    });
    if (targetId.isEmpty) return;
    final res = await ApiService.toggleFollow(targetId);
    if (mounted && res.isNotEmpty) {
      setState(() {
        if (res.containsKey('following')) {
          _isFollowing = res['following'] == true;
        }
        if (res.containsKey('follower_count')) {
          _followerCount = (res['follower_count'] as num).toInt();
        }
      });
    }
  }

  String _countryToLocationLabel(String? countryCode) {
    switch (countryCode?.toUpperCase()) {
      case 'KR':
        return '대한민국 서울';
      case 'US':
        return '미국 뉴욕';
      case 'JP':
        return '일본 도쿄';
      default:
        return countryCode ?? '대한민국 서울';
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ApiService.currentUser;
    final isPushedProfile = widget.targetUserId != null || widget.targetUsername != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          isPushedProfile
              ? ((_profileData?['user'] as Map?)?['username']?.toString() ??
                  widget.targetUsername ??
                  '프로필')
              : '프로필',
          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh, color: AppColors.textPrimary, size: 22),
            onPressed: _loadProfileData,
          ),
          if (!_isViewingOtherUser)
            IconButton(
              tooltip: '설정 및 계정 관리',
              icon: const Icon(Icons.settings_outlined, color: AppColors.textPrimary),
              onPressed: () => _showSettingsSheet(context),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : (!isPushedProfile && currentUser == null)
              ? _buildLoggedOutView(context)
              : DefaultTabController(
                  length: 2,
                  child: NestedScrollView(
                    // Makes the whole page (avatar, stats, tabs, and grid) scroll together
                    headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
                      return [
                        SliverToBoxAdapter(
                          child: _buildProfileHeader(
                            currentUser ??
                                <String, dynamic>{
                                  'id': widget.targetUserId ?? 'u_seoul_walker',
                                  'username': widget.targetUsername ?? '@seoul_walker',
                                  'country': 'KR',
                                },
                          ),
                        ),
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _TabBarDelegate(
                            TabBar(
                              indicatorColor: AppColors.primary,
                              indicatorSize: TabBarIndicatorSize.tab,
                              labelColor: AppColors.primary,
                              unselectedLabelColor: AppColors.textMuted,
                              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              indicatorWeight: 2.5,
                              tabs: const [
                                Tab(text: '영상'),
                                Tab(text: '크리에이터 후원'),
                              ],
                            ),
                          ),
                        ),
                      ];
                    },
                    body: TabBarView(
                      children: [
                        _buildVideoGrid(),
                        _buildCreatorSupportTab(),
                      ],
                    ),
                  ),
                ),
    );
  }

  /// Spec #24 & #25: Login UI when logged out
  Widget _buildLoggedOutView(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.card,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.accent.withOpacity(0.5), width: 1.5),
              ),
              child: const Icon(Icons.public_rounded, color: AppColors.accent, size: 46),
            ),
            const SizedBox(height: 18),
            const Text(
              'NOWFIELD',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '현장에서 전하는 실시간 소식',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.g_mobiledata_rounded, size: 26),
                label: const Text(
                  'Google 계정으로 계속하기',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                onPressed: () => _showAccountPickerDialog(context, provider: 'Google'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.card,
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: AppColors.cardBorder),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.apple, size: 22),
                label: const Text(
                  'Apple 계정으로 계속하기',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                onPressed: () => _showAccountPickerDialog(context, provider: 'Apple'),
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => _showCreateProfileDialog(context),
              icon: const Icon(Icons.person_add_alt_1_rounded, color: AppColors.accent, size: 18),
              label: const Text(
                '새 프로필 생성하기',
                style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(Map<String, dynamic> fallbackUser) {
    final userObj = (_profileData?['user'] as Map?)?.cast<String, dynamic>() ?? fallbackUser;
    final username = userObj['username']?.toString() ?? widget.targetUsername ?? '@seoul_walker';
    final country = userObj['country']?.toString() ?? 'KR';
    final locationLabel = _countryToLocationLabel(country);

    final videoCount = _profileData?['video_count'] ?? 0;
    final followingCount = _profileData?['following_count'] ?? 0;
    final avatarSeed = username.hashCode.abs() % 30 + 1;

    return Column(
      children: [
        const SizedBox(height: 16),
        // User Avatar with brand accent ring
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.accent, width: 2),
          ),
          child: ClipOval(
            child: Image.network(
              'https://i.pravatar.cc/150?img=$avatarSeed',
              width: 84,
              height: 84,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                width: 84,
                height: 84,
                color: AppColors.card,
                child: const Icon(Icons.person, color: AppColors.accent, size: 48),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Username & Badge
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              username,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.25),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.accent.withOpacity(0.5), width: 0.8),
              ),
              child: Text(
                _isViewingOtherUser ? '현장 크리에이터' : '로그인됨',
                style: const TextStyle(color: AppColors.accent, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_on, size: 14, color: AppColors.accent),
            const SizedBox(width: 4),
            Text(
              locationLabel,
              style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
            ),
          ],
        ),
        if (_isViewingOtherUser) ...[
          const SizedBox(height: 14),
          Builder(
            builder: (context) {
              final rawSupport = _profileData?['support_account'];
              final supportMap = rawSupport is Map ? Map<String, dynamic>.from(rawSupport) : null;
              final hasActiveSupport = supportMap != null &&
                  supportMap['active'] == true &&
                  supportMap['ownership_status'] == 'verified' &&
                  (supportMap['support_url']?.toString().isNotEmpty ?? false);

              return Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  SizedBox(
                    width: hasActiveSupport ? 136 : 160,
                    height: 36,
                    child: ElevatedButton.icon(
                      onPressed: _handleToggleFollow,
                      icon: Icon(
                        _isFollowing ? Icons.check_rounded : Icons.person_add_alt_1_rounded,
                        size: 16,
                      ),
                      label: Text(
                        _isFollowing ? '팔로잉' : '팔로우',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isFollowing ? AppColors.card : AppColors.primary,
                        foregroundColor: _isFollowing ? AppColors.accent : Colors.white,
                        side: _isFollowing ? const BorderSide(color: AppColors.accent, width: 1) : null,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  if (hasActiveSupport)
                    SizedBox(
                      height: 36,
                      child: OutlinedButton.icon(
                        onPressed: () => _showProfileSupportDialog(
                          context,
                          username: username,
                          supportAccount: supportMap,
                        ),
                        icon: const Icon(Icons.volunteer_activism_rounded, size: 16, color: Color(0xFFFF6B8B)),
                        label: const Text(
                          '후원하기',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFFFF6B8B)),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFFF6B8B), width: 1.1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
        const SizedBox(height: 20),
        // Stats in branded container
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder.withOpacity(0.4)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatItem(videoCount.toString(), '영상'),
              Container(width: 1, height: 28, color: AppColors.cardBorder),
              GestureDetector(
                onTap: () => _showFollowListSheet(context, '팔로워'),
                child: _buildStatItem(_followerCount.toString(), '팔로워'),
              ),
              Container(width: 1, height: 28, color: AppColors.cardBorder),
              GestureDetector(
                onTap: () => _showFollowListSheet(context, '팔로잉'),
                child: _buildStatItem(followingCount.toString(), '팔로잉'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildStatItem(String count, String label) {
    return Column(
      children: [
        Text(
          count,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ],
    );
  }

  Widget _buildVideoGrid() {
    final rawVideos = (_profileData?['videos'] as List<dynamic>?) ?? [];
    final videos = rawVideos
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    if (videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_outlined, color: Colors.white30, size: 44),
            const SizedBox(height: 10),
            Text(
              '${ApiService.currentUsername} 계정에 등록된 현장 영상이 없습니다.',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 6),
            const Text(
              '하단 촬영 탭에서 새 현장 영상을 촬영해 게시해 보세요.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(2),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        childAspectRatio: 9 / 16,
      ),
      itemCount: videos.length,
      itemBuilder: (context, index) {
        final v = videos[index];
        final thumbUrl = ApiService.resolveMediaUrl(
          (v['thumbnail_url'] ?? v['preview_url']) as String?,
        );
        final title = v['title']?.toString() ?? '';
        final likeCount = v['like_count']?.toString() ?? '0';

        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => VideoDetailScreen(
                  videoData: v,
                  videoList: videos,
                  initialIndex: index,
                ),
              ),
            );
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                thumbUrl.isNotEmpty
                    ? thumbUrl
                    : 'https://picsum.photos/seed/${index + 20}/300/500',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: AppColors.card,
                  child: const Center(child: Icon(Icons.videocam, color: Colors.white24)),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black.withOpacity(0.75)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              Positioned(
                bottom: 24,
                left: 6,
                right: 6,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Positioned(
                bottom: 6,
                left: 6,
                right: 6,
                child: Row(
                  children: [
                    const Icon(Icons.favorite_rounded, color: Colors.redAccent, size: 13),
                    const SizedBox(width: 4),
                    Text(
                      likeCount,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// CR-01: Replaces legacy License tab with Creator Support & Ad Revenue tab
  Widget _buildCreatorSupportTab() {
    final rawVideos = (_profileData?['videos'] as List<dynamic>?) ?? [];
    final allVideos = rawVideos
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final supportEnabledVideos = allVideos
        .where((v) => v['support_enabled'] == true)
        .toList();

    final rawSupport = _profileData?['support_account'];
    final supportAccount = rawSupport is Map ? Map<String, dynamic>.from(rawSupport) : null;
    final hasVerifiedSupport = supportAccount != null &&
        supportAccount['active'] == true &&
        supportAccount['ownership_status'] == 'verified' &&
        (supportAccount['support_url']?.toString().isNotEmpty ?? false);
    final supportUrl = supportAccount?['support_url']?.toString() ?? '';
    final provider = supportAccount?['provider']?.toString().toUpperCase() ?? 'KO-FI';
    final totalSupportClicks = _profileData?['total_support_clicks'] ??
        supportEnabledVideos.fold<int>(
          0,
          (sum, v) => sum + ((v['support_click_count'] as num?)?.toInt() ?? 0),
        );
    final username = ((_profileData?['user'] as Map?)?['username']?.toString()) ??
        widget.targetUsername ??
        ApiService.currentUsername;

    return Column(
      children: [
        // CR-01: Creator Support & Ad Pool Banner
        GestureDetector(
          onTap: () {
            if (_isViewingOtherUser) {
              if (hasVerifiedSupport) {
                _showProfileSupportDialog(
                  context,
                  username: username,
                  supportAccount: supportAccount,
                );
              }
            } else {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(builder: (_) => const EarningsScreen(initialTabIndex: 1)),
                  )
                  .then((_) => _loadProfileData());
            }
          },
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: hasVerifiedSupport
                    ? const Color(0xFFFF6B8B).withOpacity(0.55)
                    : AppColors.cardBorder.withOpacity(0.45),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.volunteer_activism_rounded, color: Color(0xFFFF6B8B), size: 15),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _isViewingOtherUser
                                  ? '외부 크리에이터 후원'
                                  : '크리에이터 후원 연결 · 광고 수익 정산 관리',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        hasVerifiedSupport
                            ? '$provider 연결됨 · $supportUrl'
                            : (_isViewingOtherUser ? '연결된 외부 후원 페이지 없음' : '외부 후원 URL 미연결'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: hasVerifiedSupport ? AppColors.accent : AppColors.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '후원 활성 ${supportEnabledVideos.length}건 · 클릭 $totalSupportClicks회',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded, color: AppColors.accent, size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: supportEnabledVideos.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      _isViewingOtherUser
                          ? '이 크리에이터가 후원 버튼을 활성화한 영상이 없습니다.'
                          : '후원 버튼이 활성화된 영상이 없습니다.\n촬영 시 또는 [수익 및 후원 관리]에서 외부 후원 계정을 연결하고 영상별 후원 버튼을 켤 수 있습니다.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.5),
                    ),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(2),
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                    childAspectRatio: 9 / 16,
                  ),
                  itemCount: supportEnabledVideos.length,
                  itemBuilder: (context, index) {
                    final v = supportEnabledVideos[index];
                    final thumbUrl = ApiService.resolveMediaUrl(
                      (v['thumbnail_url'] ?? v['preview_url']) as String?,
                    );
                    final clickCount = (v['support_click_count'] as num?)?.toInt() ?? 0;

                    return GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => VideoDetailScreen(
                              videoData: v,
                              videoList: supportEnabledVideos,
                              initialIndex: index,
                            ),
                          ),
                        );
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            thumbUrl.isNotEmpty
                                ? thumbUrl
                                : 'https://picsum.photos/seed/${index + 50}/300/500',
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(color: AppColors.card),
                          ),
                          Container(
                            color: Colors.black.withOpacity(0.25),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF6B8B),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '후원 ON',
                                style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 8,
                            left: 6,
                            right: 6,
                            child: Row(
                              children: [
                                const Icon(Icons.volunteer_activism, color: Color(0xFFFF6B8B), size: 12),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '클릭 $clickCount회',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showProfileSupportDialog(
    BuildContext parentContext, {
    required String username,
    required Map<String, dynamic> supportAccount,
  }) {
    final supportUrl = supportAccount['support_url']?.toString() ?? '';
    final provider = supportAccount['provider']?.toString().toUpperCase() ?? 'KO-FI';

    showDialog(
      context: parentContext,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.volunteer_activism_rounded, color: Color(0xFFFF6B8B), size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$username 크리에이터 후원하기',
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFF6B8B).withOpacity(0.45)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '외부 후원 서비스 · $provider',
                    style: const TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    supportUrl,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '• NOWFIELD 플랫폼 수수료 0%: 후원금은 외부 결제 페이지를 통해 크리에이터에게 직접 전달됩니다.\n'
              '• 자발적 후원 안내: 후원 여부에 따라 앱 내 디지털 기능, 배지, 독점 콘텐츠 잠금해제 또는 노출 우대 혜택이 제공되지 않습니다.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('외부 후원 페이지 열기', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: supportUrl));
              if (ctx.mounted) Navigator.pop(ctx);
              if (parentContext.mounted) {
                ScaffoldMessenger.of(parentContext).showSnackBar(
                  SnackBar(
                    content: Text('외부 후원 링크로 이동합니다: $supportUrl'),
                    backgroundColor: AppColors.primary,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  /// Spec #50: Complete Settings & Account Management Bottom Sheet
  void _showSettingsSheet(BuildContext parentContext) {
    final currentUser = ApiService.currentUser;

    showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final blockedCount = ApiService.blockedUsersNotifier.value.length;
            final notifOn = ApiService.notificationsEnabledNotifier.value;
            final appLang = ApiService.appLanguageNotifier.value;
            final captionLang = ApiService.defaultCaptionLangNotifier.value;

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.78,
              minChildSize: 0.5,
              maxChildSize: 0.92,
              builder: (_, scrollCtrl) {
                return ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '설정 및 계정 관리',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (currentUser != null)
                            Text(
                              currentUser['username']?.toString() ?? '',
                              style: const TextStyle(
                                color: AppColors.accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white12),

                    // 1. Account
                    ListTile(
                      leading: const Icon(Icons.manage_accounts_outlined, color: AppColors.accent),
                      title: const Text(
                        '계정 전환 및 로그인',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        currentUser != null
                            ? '현재 로그인 계정: ${currentUser['username']}'
                            : '로그아웃 상태',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showAccountPickerDialog(parentContext);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.person_add_alt_1_outlined, color: AppColors.textPrimary),
                      title: const Text(
                        '새 프로필 생성',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showCreateProfileDialog(parentContext);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.slideshow_rounded, color: AppColors.accent),
                      title: const Text(
                        '서비스 소개 및 소셜 로그인 안내',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.of(parentContext).push(
                          MaterialPageRoute(builder: (_) => const OnboardingLoginScreen()),
                        );
                      },
                    ),
                    const Divider(color: Colors.white12),

                    // 2. Earnings & Creator Support (CR-01)
                    ListTile(
                      leading: const Icon(Icons.account_balance_wallet_outlined, color: AppColors.success),
                      title: const Text(
                        '광고 수익 정산 관리',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        '크리에이터 풀 광고 수익 자동 정산 내역',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.of(parentContext)
                            .push(
                              MaterialPageRoute(builder: (_) => const EarningsScreen(initialTabIndex: 0)),
                            )
                            .then((_) => _loadProfileData());
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.volunteer_activism_outlined, color: Color(0xFFFF6B8B)),
                      title: const Text(
                        '크리에이터 후원 계정 연결',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Ko-fi · Buy Me a Coffee · PayPal.Me 연결 및 영상별 후원 버튼 설정',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.of(parentContext)
                            .push(
                              MaterialPageRoute(builder: (_) => const EarningsScreen(initialTabIndex: 1)),
                            )
                            .then((_) => _loadProfileData());
                      },
                    ),
                    const Divider(color: Colors.white12),

                    // 3. Privacy, Blocked Users, Notifications, Language, Captions, Location
                    ListTile(
                      leading: const Icon(Icons.block_flipped, color: AppColors.warning),
                      title: const Text(
                        '차단한 사용자 관리',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
                      ),
                      subtitle: const Text(
                        '차단한 사용자의 영상/댓글 노출 제한 및 차단 해제',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showBlockedUsersDialog(parentContext);
                      },
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.notifications_active_outlined, color: AppColors.textPrimary),
                      activeColor: AppColors.accent,
                      title: const Text(
                        '푸시 알림 설정',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
                      ),
                      subtitle: const Text(
                        '소셜, 운영·검토, 크리에이터 후원 연결, 월별 광고 정산 알림 수신',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                      value: notifOn,
                      onChanged: (val) {
                        ApiService.notificationsEnabledNotifier.value = val;
                        setSheetState(() {});
                      },
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.gps_fixed_rounded, color: AppColors.accent),
                      activeColor: AppColors.accent,
                      title: const Text(
                        '정확한 위치 공개 사전 동의',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
                      ),
                      subtitle: const Text(
                        '영상 업로드 시 정확한 위치 기본 선택을 위한 명시적 사전 동의',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                      value: ApiService.exactLocationConsentNotifier.value,
                      onChanged: (val) async {
                        await ApiService.recordExactLocationConsent(val);
                        setSheetState(() {});
                      },
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.location_searching_rounded, color: AppColors.textPrimary),
                      activeColor: AppColors.accent,
                      title: const Text(
                        'OS 정밀 위치 권한 상태',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
                      ),
                      subtitle: const Text(
                        '비활성화 시 정확한 위치 선택이 제한되며 대략적 위치로 대체됩니다',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                      value: ApiService.preciseLocationPermissionNotifier.value,
                      onChanged: (val) {
                        ApiService.preciseLocationPermissionNotifier.value = val;
                        setSheetState(() {});
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.language_rounded, color: AppColors.textPrimary),
                      title: const Text(
                        '앱 표시 언어',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
                      ),
                      trailing: Text(
                        appLang,
                        style: const TextStyle(color: AppColors.accent, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      onTap: () {
                        final next = appLang == '한국어' ? '영어' : '한국어';
                        ApiService.appLanguageNotifier.value = next;
                        setSheetState(() {});
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.closed_caption_outlined, color: AppColors.textPrimary),
                      title: const Text(
                        '기본 자막 및 번역 언어 설정',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
                      ),
                      trailing: Text(
                        captionLang == 'Original' ? '원문' : captionLang,
                        style: const TextStyle(color: AppColors.accent, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      onTap: () {
                        const langs = ['원문', '한국어', '영어', '일본어'];
                        final currentIdx = langs.indexOf(captionLang == 'Original' ? '원문' : captionLang);
                        final nextIdx = (currentIdx + 1) % langs.length;
                        ApiService.defaultCaptionLangNotifier.value = langs[nextIdx];
                        setSheetState(() {});
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.radar_rounded, color: AppColors.textPrimary),
                      title: const Text(
                        '다른 시선 반경 설정',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
                      ),
                      subtitle: const Text(
                        '영상 주변의 "다른 시선" 검색 반경',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showAnglesRadiusDialog(parentContext);
                      },
                    ),
                    const ListTile(
                      leading: Icon(Icons.my_location_rounded, color: AppColors.textPrimary),
                      title: Text(
                        '위치 공개 정밀도 및 지도 핀 정책',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
                      ),
                      subtitle: Text(
                        '영상별 정확한 위치 / 대략적 위치 / 위치 미표시 선택 가능 · 내 주변 지도 핀은 게시 후 60분간만 노출',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.policy_outlined, color: AppColors.textPrimary),
                      title: const Text(
                        '콘텐츠 운영 정책 · 이용약관 · 개인정보 처리방침 · 고객센터',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showPolicyInfoDialog(parentContext);
                      },
                    ),
                    const Divider(color: Colors.white12),

                    // Developer: API Server URL
                    ListTile(
                      leading: const Icon(Icons.dns_outlined, color: AppColors.textMuted),
                      title: const Text(
                        'API 서버 주소',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
                      ),
                      subtitle: Text(
                        ApiService.baseUrl,
                        style: const TextStyle(color: AppColors.accent, fontSize: 11.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.edit_outlined, color: AppColors.textMuted, size: 20),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showApiUrlDialog(parentContext);
                      },
                    ),

                    if (currentUser != null) ...[
                      const Divider(color: Colors.white12),
                      ListTile(
                        leading: const Icon(Icons.logout_rounded, color: Colors.orangeAccent),
                        title: const Text(
                          '로그아웃',
                          style: TextStyle(color: Colors.orangeAccent, fontSize: 14.5, fontWeight: FontWeight.w600),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          ApiService.logout();
                          ScaffoldMessenger.of(parentContext).showSnackBar(
                            const SnackBar(
                              content: Text('로그아웃되었습니다.'),
                              backgroundColor: AppColors.card,
                            ),
                          );
                        },
                      ),
                      // Spec #1 & #50: Delete Account
                      ListTile(
                        leading: const Icon(Icons.delete_forever_rounded, color: AppColors.danger),
                        title: const Text(
                          '계정 영구 삭제',
                          style: TextStyle(color: AppColors.danger, fontSize: 14.5, fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text(
                          '계정 및 프로필 데이터를 영구 삭제합니다.',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          _showDeleteAccountConfirmDialog(parentContext);
                        },
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _showApiUrlDialog(BuildContext parentContext) {
    final controller = TextEditingController(text: ApiService.baseUrl);
    final presets = [
      'http://127.0.0.1:8000',
      'http://10.0.2.2:8000',
      'https://nothing-cash-spoke-burns.trycloudflare.com',
    ];

    showDialog(
      context: parentContext,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text(
            'API 서버 주소 변경',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'https://example.com',
                  hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear, color: AppColors.textMuted, size: 18),
                    onPressed: () => controller.clear(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '프리셋',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              ...presets.map((url) => InkWell(
                onTap: () => controller.text = url,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: Row(
                    children: [
                      Icon(
                        url == ApiService.baseUrl ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: url == ApiService.baseUrl ? AppColors.accent : AppColors.textMuted,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          url,
                          style: TextStyle(
                            color: url == ApiService.baseUrl ? AppColors.accent : AppColors.textPrimary,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              )),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소', style: TextStyle(color: AppColors.textMuted)),
            ),
            TextButton(
              onPressed: () {
                final newUrl = controller.text.trim();
                if (newUrl.isNotEmpty) {
                  ApiService.setBaseUrl(newUrl);
                  Navigator.pop(ctx);
                  _loadProfileData();
                  ScaffoldMessenger.of(parentContext).showSnackBar(
                    SnackBar(
                      content: Text('API 서버 주소가 저장되어 변경되었습니다:\n${ApiService.baseUrl}'),
                      backgroundColor: AppColors.card,
                    ),
                  );
                }
              },
              child: const Text('적용', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showFollowListSheet(BuildContext parentContext, String type) {
    final userId = (_profileData?['user'] as Map?)?['id']?.toString() ?? ApiService.currentUserId;

    showModalBottomSheet(
      context: parentContext,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: type == '팔로워'
              ? ApiService.getFollowers(userId)
              : ApiService.getFollowing(userId),
          builder: (context, snapshot) {
            final list = snapshot.data ?? [];
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '$type ${list.length}명',
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
                      )
                    else if (list.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            '$type이 없습니다',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
                          ),
                        ),
                      )
                    else
                      ...list.map((user) => ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.background,
                          backgroundImage: user['profile_image'] != null
                              ? NetworkImage(ApiService.resolveMediaUrl(user['profile_image']))
                              : null,
                          child: user['profile_image'] == null
                              ? const Icon(Icons.person, color: AppColors.textMuted, size: 20)
                              : null,
                        ),
                        title: Text(
                          user['username'] ?? '@unknown',
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
                        onTap: () {
                          Navigator.pop(ctx);
                          Navigator.of(parentContext).push(
                            MaterialPageRoute(
                              builder: (_) => ProfileScreen(
                                targetUserId: user['user_id'],
                                targetUsername: user['username'],
                              ),
                            ),
                          );
                        },
                      )),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAnglesRadiusDialog(BuildContext parentContext) {
    final controller = TextEditingController();
    bool loading = true;

    showDialog(
      context: parentContext,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (loading) {
              ApiService.getAdminSettings().then((settings) {
                final current = settings['angles_radius_km'] ?? 1.0;
                controller.text = current.toString();
                setDialogState(() => loading = false);
              });
            }
            return AlertDialog(
              backgroundColor: AppColors.card,
              title: const Text('다른 시선 반경 설정', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
              content: loading
                  ? const SizedBox(height: 48, child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '영상 위치 기준으로 주변 영상을 검색할 반경을 설정합니다.',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: controller,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: '반경 (km)',
                            labelStyle: const TextStyle(color: AppColors.textMuted),
                            suffixText: 'km',
                            suffixStyle: const TextStyle(color: AppColors.accent),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: AppColors.cardBorder),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: AppColors.accent),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('취소', style: TextStyle(color: AppColors.textMuted)),
                ),
                TextButton(
                  onPressed: () async {
                    final val = double.tryParse(controller.text);
                    if (val != null && val > 0) {
                      await ApiService.updateAdminSettings({'angles_radius_km': val});
                      if (context.mounted) Navigator.pop(ctx);
                    }
                  },
                  child: const Text('저장', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showBlockedUsersDialog(BuildContext parentContext) {
    showDialog(
      context: parentContext,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final blocked = ApiService.blockedUsersNotifier.value.toList();
            return AlertDialog(
              backgroundColor: AppColors.card,
              title: const Text(
                '차단한 사용자 관리',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: blocked.isEmpty
                    ? const Text(
                        '현재 차단된 사용자가 없습니다.\n영상 더보기(⋯) 메뉴에서 사용자를 차단하면 피드 및 검색 노출이 제한됩니다.',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.45),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: blocked.map((uname) {
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.person_off_outlined, color: AppColors.warning),
                            title: Text(uname, style: const TextStyle(color: AppColors.textPrimary)),
                            trailing: TextButton(
                              onPressed: () {
                                ApiService.unblockUser(uname);
                                setDialogState(() {});
                              },
                              child: const Text('차단 해제', style: TextStyle(color: AppColors.accent)),
                            ),
                          );
                        }).toList(),
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('닫기', style: TextStyle(color: AppColors.textMuted)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showPolicyInfoDialog(BuildContext parentContext) {
    showDialog(
      context: parentContext,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          '서비스 운영 정책 및 약관',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: const SingleChildScrollView(
          child: Text(
            '• 원테이크·최대 60초: NOWFIELD 카메라로 직접 촬영한 최대 60초 현장 영상만 게시합니다.\n'
            '• 크리에이터 후원: 영상 라이선스 마켓은 운영하지 않으며, Ko-fi·Buy Me a Coffee·PayPal.Me 등 외부 후원 링크를 통해 플랫폼 수수료 0%로 크리에이터에게 직접 후원할 수 있습니다.\n'
            '• 위치 공개 정밀도 선택: 영상별로 정확한 위치, 약 100~200m 범위, 위치 미표시 중 선택할 수 있으며 원본 촬영 좌표는 외부 API에 노출되지 않습니다.\n'
            '• 업로드 일시 표기: 상대 시간 대신 실제 서버 게시 시각 기준 절대 날짜·시간을 표시합니다.\n'
            '• 내 주변 지도 핀 60분 자동 만료: 반경 1km 이내, 게시 후 60분 이내의 공개 영상만 내 주변 지도에 핀으로 표시되며 60분 경과 시 지도 핀에서만 자동 제외됩니다.\n'
            '• 광고 수익 배분: 광고 순수익의 크리에이터 풀은 월별 자동 정산되며 외부 후원금과 별도로 집계됩니다.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.55),
          ),
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

  void _showDeleteAccountConfirmDialog(BuildContext parentContext) {
    final uname = ApiService.currentUsername;
    showDialog(
      context: parentContext,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          '계정 삭제 확인',
          style: TextStyle(color: AppColors.danger, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Text(
          '현재 로그인된 $uname 계정을 삭제하시겠습니까?\n삭제 후에는 로그아웃 상태로 전환되며, 설정에서 언제든 다른 계정으로 전환하거나 새 프로필을 만들 수 있습니다.',
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await ApiService.deleteCurrentAccount();
              if (parentContext.mounted) {
                ScaffoldMessenger.of(parentContext).showSnackBar(
                  SnackBar(
                    content: Text('$uname 계정이 삭제되고 로그아웃되었습니다.'),
                    backgroundColor: AppColors.danger,
                  ),
                );
              }
            },
            child: const Text('계정 영구 삭제'),
          ),
        ],
      ),
    );
  }

  void _showAccountPickerDialog(BuildContext parentContext, {String provider = 'NOWFIELD'}) {
    final users = _allUsers.isNotEmpty
        ? _allUsers
        : <Map<String, dynamic>>[
            {'id': 'u_seoul_walker', 'username': '@seoul_walker', 'country': 'KR'},
            {'id': 'u_apgu_now', 'username': '@apgu_now', 'country': 'KR'},
            {'id': 'u_commuter', 'username': '@commuter', 'country': 'KR'},
            {'id': 'u_han_biker', 'username': '@han_biker', 'country': 'KR'},
          ];

    showDialog(
      context: parentContext,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            '$provider 계정 선택',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...users.map((u) {
                  final isCurrent = ApiService.currentUser?['id'] == u['id'];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: AppColors.background,
                      child: Icon(
                        Icons.person,
                        color: isCurrent ? AppColors.accent : AppColors.textMuted,
                      ),
                    ),
                    title: Text(
                      u['username']?.toString() ?? '',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      _countryToLocationLabel(u['country']?.toString()),
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                    trailing: isCurrent
                        ? const Icon(Icons.check_circle, color: AppColors.accent, size: 20)
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      ApiService.loginAs(u);
                      ScaffoldMessenger.of(parentContext).showSnackBar(
                        SnackBar(
                          content: Text('${u['username']} 계정으로 로그인되었습니다.'),
                          backgroundColor: AppColors.primary,
                        ),
                      );
                    },
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _showCreateProfileDialog(parentContext);
              },
              child: const Text('새 프로필 추가', style: TextStyle(color: AppColors.accent)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('닫기', style: TextStyle(color: AppColors.textMuted)),
            ),
          ],
        );
      },
    );
  }

  /// Spec #25: Create your profile (@Username, Country)
  void _showCreateProfileDialog(BuildContext parentContext) {
    final usernameController = TextEditingController();
    String selectedCountry = 'KR';

    showDialog(
      context: parentContext,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.card,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text(
                '새 프로필 만들기',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '사용자 아이디 (@포함)',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: usernameController,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: '@my_field_id',
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppColors.cardBorder.withOpacity(0.5)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '국가 / 지역',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: selectedCountry,
                    dropdownColor: AppColors.background,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'KR', child: Text('대한민국')),
                      DropdownMenuItem(value: 'US', child: Text('미국')),
                      DropdownMenuItem(value: 'JP', child: Text('일본')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedCountry = val);
                      }
                    },
                  ),
                ],
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
                  ),
                  onPressed: () async {
                    final raw = usernameController.text.trim();
                    if (raw.isEmpty) return;
                    Navigator.pop(ctx);
                    final user = await ApiService.createOrLoginUser(raw, country: selectedCountry);
                    if (user.isNotEmpty && parentContext.mounted) {
                      ScaffoldMessenger.of(parentContext).showSnackBar(
                        SnackBar(
                          content: Text('${user['username']} 프로필로 로그인되었습니다.'),
                          backgroundColor: AppColors.primary,
                        ),
                      );
                    }
                  },
                  child: const Text('생성 완료'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _TabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.background,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) => false;
}
