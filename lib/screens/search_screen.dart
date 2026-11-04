import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/api_service.dart';
import 'home_screen.dart';
import 'profile_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = '전체';
  bool _isLoading = true;
  List<Map<String, dynamic>> _videos = [];
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _places = [];

  static const List<String> _categories = [
    '전체',
    '동네·일상',
    '교통·정체',
    '인파·혼잡',
    '날씨·재난',
    '문화·행사',
  ];

  static const List<String> _suggestedKeywords = [
    '신사동',
    '테스트',
    '@seoul_walker',
    '강남',
    '압구정',
  ];

  @override
  void initState() {
    super.initState();
    _executeSearch('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _executeSearch(String query, {String? category}) async {
    final activeCategory = category ?? _selectedCategory;
    setState(() {
      _isLoading = true;
      if (category != null) {
        _selectedCategory = category;
      }
    });

    final res = await ApiService.searchUnified(
      query.trim(),
      category: activeCategory,
    );

    if (!mounted) return;

    final rawVideos = (res['videos'] as List<dynamic>?) ?? [];
    final rawUsers = (res['users'] as List<dynamic>?) ?? [];
    final rawPlaces = (res['places'] as List<dynamic>?) ?? [];

    setState(() {
      _videos = rawVideos.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      _users = rawUsers.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      _places = rawPlaces.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      _isLoading = false;
    });
  }

  void _applyKeyword(String kw) {
    _searchController.text = kw;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: kw.length),
    );
    _executeSearch(kw);
  }

  @override
  Widget build(BuildContext context) {
    final queryText = _searchController.text.trim();
    final hasAnyResult = _videos.isNotEmpty || _users.isNotEmpty || _places.isNotEmpty;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          titleSpacing: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.cardBorder.withOpacity(0.55)),
              ),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                textInputAction: TextInputAction.search,
                onChanged: (val) => _executeSearch(val),
                onSubmitted: (val) => _executeSearch(val),
                decoration: InputDecoration(
                  hintText: '@사용자명, 영상 제목, 지역(신사동 등) 검색...',
                  hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.accent, size: 20),
                  suffixIcon: queryText.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: AppColors.textMuted, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _executeSearch('');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(92),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category chips (Spec #14: Category filter)
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    itemCount: _categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final cat = _categories[index];
                      final isSelected = _selectedCategory == cat;
                      return ChoiceChip(
                        label: Text(cat),
                        selected: isSelected,
                        selectedColor: AppColors.primary,
                        backgroundColor: AppColors.card,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: isSelected ? AppColors.accent : AppColors.cardBorder.withOpacity(0.4),
                          ),
                        ),
                        onSelected: (_) => _executeSearch(_searchController.text, category: cat),
                      );
                    },
                  ),
                ),
                // Result Tabs (All / Videos / @Users / Locations)
                TabBar(
                  indicatorColor: AppColors.accent,
                  labelColor: AppColors.accent,
                  unselectedLabelColor: Colors.white54,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  tabs: [
                    const Tab(text: '전체'),
                    Tab(text: '영상 (${_videos.length})'),
                    Tab(text: '사용자 (${_users.length})'),
                    Tab(text: '장소 (${_places.length})'),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: Column(
          children: [
            // Suggested quick tags when query is empty
            if (queryText.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      '추천 검색어:',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    ..._suggestedKeywords.map(
                      (kw) => ActionChip(
                        backgroundColor: AppColors.card,
                        side: BorderSide(color: AppColors.cardBorder.withOpacity(0.4)),
                        label: Text(
                          kw,
                          style: const TextStyle(color: AppColors.accent, fontSize: 12),
                        ),
                        onPressed: () => _applyKeyword(kw),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                  : !hasAnyResult
                      ? _buildEmptySearchState(queryText)
                      : TabBarView(
                          children: [
                            _buildAllTab(),
                            _buildVideosTab(),
                            _buildUsersTab(),
                            _buildPlacesTab(),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  /// Spec #51: No search results state
  Widget _buildEmptySearchState(String query) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, color: Colors.white30, size: 54),
            const SizedBox(height: 12),
            Text(
              '"$query"에 대한 검색 결과가 없습니다.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '다른 검색어(@username, 영상 제목, 지역명)로 검색하거나\n카테고리 필터를 "전체"로 변경해 보세요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_videos.isNotEmpty) ...[
          const Text(
            '현장 영상',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          ..._videos.map((v) => _buildVideoCard(v)),
          const SizedBox(height: 18),
        ],
        if (_users.isNotEmpty) ...[
          const Text(
            '사용자',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          ..._users.map((u) => _buildUserTile(u)),
          const SizedBox(height: 18),
        ],
        if (_places.isNotEmpty) ...[
          const Text(
            '장소 검색 결과',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          ..._places.map((p) => _buildPlaceTile(p)),
        ],
      ],
    );
  }

  Widget _buildVideosTab() {
    if (_videos.isEmpty) {
      return _buildEmptySearchState(_searchController.text);
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _videos.length,
      itemBuilder: (context, index) => _buildVideoCard(_videos[index]),
    );
  }

  Widget _buildUsersTab() {
    if (_users.isEmpty) {
      return _buildEmptySearchState(_searchController.text);
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _users.length,
      itemBuilder: (context, index) => _buildUserTile(_users[index]),
    );
  }

  Widget _buildPlacesTab() {
    if (_places.isEmpty) {
      return Center(
        child: Text(
          _searchController.text.trim().isEmpty
              ? '장소명(예: 신사동, 압구정역, 서울역)을 입력하면\n카카오 로컬 장소 결과가 표시됩니다.'
              : '해당 키워드의 장소 검색 결과가 없습니다.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.5),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _places.length,
      itemBuilder: (context, index) => _buildPlaceTile(_places[index]),
    );
  }

  Widget _buildVideoCard(Map<String, dynamic> video) {
    final title = video['title']?.toString() ?? '현장 영상';
    final subtitle = video['subtitle']?.toString() ?? '';
    final uploaderName = video['uploader_name']?.toString() ?? '@seoul_walker';
    final locationName = video['location_name']?.toString() ?? 'Seoul';
    final timeStr = formatVideoTimeAgo(video['created_at']);
    final likeCount = video['like_count']?.toString() ?? '0';
    final commentCount = video['comment_count']?.toString() ?? '0';
    final thumbUrl = ApiService.resolveMediaUrl(
      (video['thumbnail_url'] ?? video['preview_url']) as String?,
    );

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VideoDetailScreen(videoData: video),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder.withOpacity(0.45)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 96,
                height: 76,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    thumbUrl.isNotEmpty
                        ? Image.network(
                            thumbUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: AppColors.background,
                              child: const Icon(Icons.videocam, color: Colors.white24),
                            ),
                          )
                        : Container(
                            color: AppColors.background,
                            child: const Icon(Icons.videocam, color: Colors.white24),
                          ),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                  ],
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
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 12, color: AppColors.accent),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          '$locationName · $uploaderName · $timeStr',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.favorite_rounded, size: 12, color: Colors.redAccent),
                      const SizedBox(width: 3),
                      Text(likeCount, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                      const SizedBox(width: 10),
                      const Icon(Icons.chat_bubble_outline_rounded, size: 12, color: AppColors.textMuted),
                      const SizedBox(width: 3),
                      Text(commentCount, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserTile(Map<String, dynamic> user) {
    final userId = user['id']?.toString() ?? '';
    final username = user['username']?.toString() ?? '@user';
    final country = user['country']?.toString() ?? 'KR';
    final avatarSeed = username.hashCode.abs() % 30 + 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder.withOpacity(0.4)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage: NetworkImage('https://i.pravatar.cc/100?img=$avatarSeed'),
          backgroundColor: AppColors.background,
        ),
        title: Text(
          username,
          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          '현장 크리에이터 · $country',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.accent),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProfileScreen(
                targetUserId: userId,
                targetUsername: username,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlaceTile(Map<String, dynamic> place) {
    final placeName = place['place_name']?.toString() ?? '';
    final addressName = (place['road_address_name']?.toString().isNotEmpty == true)
        ? place['road_address_name'].toString()
        : (place['address_name']?.toString() ?? '');
    final categoryName = place['category_group_name']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder.withOpacity(0.4)),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.place_rounded, color: AppColors.accent, size: 20),
        ),
        title: Text(
          placeName,
          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          categoryName.isNotEmpty ? '$addressName · $categoryName' : addressName,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        trailing: const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 18),
        onTap: () {
          // Extract dong/gu or place name to search matching field videos
          final parts = addressName.split(' ');
          final searchKw = parts.length >= 3 ? parts[2] : placeName;
          _applyKeyword(searchKw);
        },
      ),
    );
  }
}
