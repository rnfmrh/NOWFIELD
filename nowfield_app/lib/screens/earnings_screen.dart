import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/api_service.dart';
import 'home_screen.dart';

/// v1.1 CR-01: Creator Earnings (Ad Creator Pool 30%) & External Creator Support Account Screen
/// License sales & license revenue have been completely removed.
class EarningsScreen extends StatefulWidget {
  final int initialTabIndex; // 0: Ad Earnings, 1: Creator Support Account (CR-01)

  const EarningsScreen({super.key, this.initialTabIndex = 0});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  Map<String, dynamic>? _profileData;
  Map<String, dynamic>? _supportAccount;
  String _selectedPayoutMethod = '카카오뱅크 · 3333-02-XXXXXX';

  String _selectedProvider = 'kofi';
  final TextEditingController _supportUrlController = TextEditingController();
  String? _supportFormError;
  bool _isSavingSupport = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTabIndex);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      ApiService.getUserProfile(ApiService.currentUserId),
      ApiService.getSupportAccount(ApiService.currentUserId),
      ApiService.getAdStats(),
    ]);
    final data = results[0] as Map<String, dynamic>;
    final acc = results[1] as Map<String, dynamic>?;
    if (!mounted) return;
    setState(() {
      _profileData = data;
      _supportAccount = acc ?? (data['support_account'] as Map<String, dynamic>?);
      if (_supportAccount != null) {
        _selectedProvider = (_supportAccount!['provider']?.toString() ?? 'kofi').toLowerCase();
        _supportUrlController.text = _supportAccount!['support_url']?.toString() ?? '';
      } else {
        _supportUrlController.text = 'https://ko-fi.com/${ApiService.currentUsername.replaceAll('@', '')}';
      }
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _supportUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int totalSupportClicks = (_profileData?['total_support_clicks'] as int?) ?? 14;

    final rawVideos = (_profileData?['videos'] as List<dynamic>?) ?? [];
    final videos = rawVideos.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('광고 수익 및 크리에이터 후원'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textMuted,
          tabs: const [
            Tab(text: '광고 수익 정산'),
            Tab(text: '크리에이터 후원 연결'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : ValueListenableBuilder<int>(
              valueListenable: ApiService.creatorPoolRevenueNotifier,
              builder: (_, liveAdRev, __) {
                final int adRev = liveAdRev > 0
                    ? liveAdRev
                    : ((_profileData?['ad_creator_pool_revenue'] as num?)?.toInt() ?? 51240);
                return TabBarView(
                  controller: _tabController,
                  children: [
                    _buildAdEarningsTab(adRev: adRev),
                    _buildCreatorSupportTab(
                      videos: videos,
                      totalSupportClicks: totalSupportClicks,
                    ),
                  ],
                );
              },
            ),
    );
  }

  /// v1.1 Section 11 & 13: Ad Revenue Settlement UI (External support donations are NOT mixed here)
  Widget _buildAdEarningsTab({required int adRev}) {
    final bool hasVerifiedSupport = _supportAccount != null &&
        _supportAccount!['active'] == true &&
        _supportAccount!['ownership_status'] == 'verified';

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        // Available Ad Pool Balance Card
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1D4ED8), Color(0xFF183459)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.accent.withOpacity(0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '이번 달 광고 수익 정산 가능 금액',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      ApiService.currentUsername,
                      style: const TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '₩${_formatCurrency(adRev)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '크리에이터 풀 배분',
                style: TextStyle(color: AppColors.accent, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Live Web Ad Network (Kakao AdFit / Google AdSense) & Real-time Pool Accumulation Card
        ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: ApiService.adStatsCacheNotifier,
          builder: (_, stats, __) {
            final int impressions = (stats['total_impressions'] as num?)?.toInt() ?? 0;
            final int clicks = (stats['total_clicks'] as num?)?.toInt() ?? 0;
            final int livePool = (stats['live_accumulated_pool_krw'] as num?)?.toInt() ?? 0;
            final int interval = (stats['feed_ad_interval'] as num?)?.toInt() ?? 3;
            final String network = (stats['web_ad_network']?.toString() ?? 'adfit').toUpperCase();

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.accent.withOpacity(0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.ads_click_rounded, color: AppColors.accent, size: 19),
                          SizedBox(width: 6),
                          Text(
                            '웹 광고 네트워크 실시간 풀 적립 현황',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.22),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$network · ${interval}개 영상마다 노출',
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatMiniBox('광고 노출수', '$impressions회'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildStatMiniBox('광고 클릭수', '$clicks회'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildStatMiniBox('실시간 30% 적립', '+₩${_formatCurrency(livePool)}'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),

        // Breakdown Card (Advertising Only + External Support Notice)
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '수익 구성 및 외부 후원 분리 안내',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              _buildRevenueRow(
                icon: Icons.campaign_outlined,
                title: '광고 수익',
                subtitle: '산정식: 크리에이터 풀 × 내 유효 조회 품질 지수 ÷ 전체 지수',
                amount: '₩${_formatCurrency(adRev)}',
                badgeColor: AppColors.accent,
              ),
              const Divider(color: AppColors.cardBorder, height: 24),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.volunteer_activism_rounded, color: AppColors.success, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '외부 크리에이터 후원금',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          hasVerifiedSupport
                              ? '연결됨: ${_supportAccount!['support_url']}'
                              : '외부 후원 서비스에서 크리에이터에게 직접 입금되며 NOWFIELD 정산 잔액과 합산하지 않습니다.',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _tabController.animateTo(1),
                    child: const Text('관리', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // WQV Quality Formula Explanation Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Icon(Icons.info_outline_rounded, color: AppColors.accent, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '유효 조회 품질 지수(WQV): 단순 조회수가 아닌 실제 시청 시간 비율을 반영하며, 비정상·반복 조회 및 제재 영상은 정산에서 제외됩니다.\n'
                  '최초 1회 정산 계좌 및 본인확인(KYC) 등록 후 월별 자동 정산이 진행됩니다.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.45),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Action Buttons: [ Payment Settings ] & [ Payout History ]
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.cardBorder, width: 1.2),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _showPaymentSettingsDialog,
                icon: const Icon(Icons.account_balance_outlined, size: 18, color: AppColors.accent),
                label: const Text('정산 계좌 설정', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _showPayoutHistorySheet(adRev),
                icon: const Icon(Icons.receipt_long_rounded, size: 18),
                label: const Text('정산 지급 내역', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// CR-01: External Creator Support Account Linking & Verification Tab
  Widget _buildCreatorSupportTab({
    required List<Map<String, dynamic>> videos,
    required int totalSupportClicks,
  }) {
    final bool isConnected = _supportAccount != null &&
        _supportAccount!['active'] == true &&
        _supportAccount!['ownership_status'] == 'verified';
    final int enabledVideoCount = videos.where((v) => v['support_enabled'] == true).length;

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        // Principle Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.accent.withOpacity(0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.volunteer_activism_rounded, color: AppColors.accent, size: 22),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Creator-first Support · 플랫폼 수수료 0%',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isConnected
                          ? AppColors.success.withOpacity(0.2)
                          : AppColors.warning.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isConnected ? '검증 완료' : '미연결',
                      style: TextStyle(
                        color: isConnected ? AppColors.success : AppColors.warning,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '• 시청자가 영상의 [후원하기] 버튼을 누르면 연결된 외부 후원 페이지가 열립니다.\n'
                '• NOWFIELD는 후원금을 수취·보관하지 않으며 플랫폼 수수료 0%로 전액 크리에이터에게 전달됩니다.\n'
                '• 스토어 정책 준수를 위해 후원 대가로 앱 내 디지털 배지·독점 콘텐츠·우선 노출 등 혜택을 제공하지 않습니다.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Summary Stats Row
        Row(
          children: [
            Expanded(
              child: _buildStatBox(
                '연결 상태',
                isConnected ? (_supportAccount!['provider']?.toString().toUpperCase() ?? 'KOFI') : '미연결',
                Icons.verified_user_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildStatBox(
                '후원 활성 영상',
                '$enabledVideoCount / ${videos.length}개',
                Icons.videocam_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildStatBox(
                '외부 이동 클릭',
                '$totalSupportClicks회',
                Icons.ads_click_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Support Account Form Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '외부 후원 서비스 계정 연결 및 소유 검증',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                '외부 후원 서비스 비밀번호는 절대 수집하지 않으며, 허용된 도메인의 공개 URL만 등록됩니다.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.4),
              ),
              const SizedBox(height: 14),

              // Provider selector chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildProviderChip('kofi', 'Ko-fi'),
                  _buildProviderChip('buymeacoffee', 'Buy Me a Coffee'),
                  _buildProviderChip('paypal', 'PayPal.Me'),
                ],
              ),
              const SizedBox(height: 14),

              TextField(
                controller: _supportUrlController,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5),
                decoration: InputDecoration(
                  labelText: '외부 후원 페이지 URL',
                  labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  hintText: _selectedProvider == 'kofi'
                      ? 'https://ko-fi.com/seoul_walker'
                      : (_selectedProvider == 'buymeacoffee'
                          ? 'https://buymeacoffee.com/seoul_walker'
                          : 'https://paypal.me/seoulwalker'),
                  hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.cardBorder),
                  ),
                ),
              ),
              if (_supportFormError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _supportFormError!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ],
              const SizedBox(height: 14),

              Row(
                children: [
                  if (isConnected) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _isSavingSupport
                            ? null
                            : () async {
                                setState(() => _isSavingSupport = true);
                                await ApiService.disconnectSupportAccount(ApiService.currentUserId);
                                await _loadData();
                                if (mounted) {
                                  setState(() => _isSavingSupport = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('외부 후원 계정 연결이 해제되었으며 모든 영상의 후원 버튼이 비활성화되었습니다.'),
                                      backgroundColor: AppColors.card,
                                    ),
                                  );
                                }
                              },
                        icon: const Icon(Icons.link_off_rounded, size: 17),
                        label: const Text('연결 해제', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _isSavingSupport
                          ? null
                          : () async {
                              final url = _supportUrlController.text.trim();
                              final err = ApiService.validateSupportUrl(_selectedProvider, url);
                              if (err != null) {
                                setState(() => _supportFormError = err);
                                return;
                              }
                              setState(() {
                                _supportFormError = null;
                                _isSavingSupport = true;
                              });
                              final res = await ApiService.saveSupportAccount(
                                provider: _selectedProvider,
                                supportUrl: url,
                              );
                              if (!mounted) return;
                              setState(() => _isSavingSupport = false);
                              if (res.containsKey('error')) {
                                setState(() => _supportFormError = res['error']?.toString());
                              } else {
                                setState(() => _supportAccount = res);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('외부 후원 페이지($url) 도메인 및 소유 검증이 완료되었습니다!'),
                                    backgroundColor: AppColors.primary,
                                  ),
                                );
                              }
                            },
                      icon: const Icon(Icons.verified_rounded, size: 17),
                      label: Text(
                        isConnected ? '후원 URL 업데이트 및 재검증' : '후원 계정 연결 및 검증',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Per-Video Support & Location Privacy Status List
        const Text(
          '내 영상별 후원 버튼 및 위치 공개 정밀도 관리',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          '각 영상 업로드 시 또는 아래 목록에서 영상별 [후원 버튼 표시] 및 [위치 공개 정밀도]를 언제든 변경할 수 있습니다.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        if (videos.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '게시한 현장 영상이 없습니다.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          )
        else
          ...videos.map((v) {
            final String videoId = v['id']?.toString() ?? '';
            final bool vSupport = isConnected && (v['support_enabled'] == true);
            final String currentMode = (v['location_display_mode'] ?? 'exact').toString().toLowerCase();
            final String privacyLabel = ApiService.formatLocationPrivacyLabel(currentMode);
            final String pubStr = ApiService.formatPublishedDateTime(
              v['published_at'] ?? v['created_at'],
              timezone: v['display_timezone']?.toString(),
            );
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        vSupport ? Icons.volunteer_activism_rounded : Icons.videocam_outlined,
                        color: vSupport ? AppColors.accent : AppColors.textMuted,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              v['title']?.toString() ?? '현장 영상',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '게시: $pubStr · $privacyLabel · ${vSupport ? '후원 버튼 노출 중' : '후원 버튼 미표시'}',
                              style: TextStyle(
                                color: vSupport ? AppColors.accent : AppColors.textMuted,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        activeColor: AppColors.accent,
                        value: vSupport,
                        onChanged: (val) async {
                          if (!isConnected) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('먼저 위에서 외부 후원 페이지 URL을 연결 및 검증해주세요.'),
                              ),
                            );
                            return;
                          }
                          setState(() {
                            v['support_enabled'] = val;
                            if (val) {
                              v['creator_support_url'] = _supportAccount!['support_url'];
                              v['creator_support_provider'] = _supportAccount!['provider'];
                            }
                          });
                          if (videoId.isNotEmpty) {
                            final updated = await ApiService.updateVideoSettings(
                              videoId: videoId,
                              supportEnabled: val,
                            );
                            if (mounted) {
                              setState(() {
                                v.addAll(updated);
                              });
                            }
                          }
                        },
                      ),
                      IconButton(
                        tooltip: '영상 보기',
                        icon: const Icon(Icons.play_circle_outline, color: AppColors.accent),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => VideoDetailScreen(videoData: v)),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.my_location_rounded, size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 6),
                      const Text(
                        '위치 공개 정밀도:',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            {'mode': 'exact', 'label': '정확한 위치'},
                            {'mode': 'approximate', 'label': '약 100~200m'},
                            {'mode': 'hidden', 'label': '위치 미표시'},
                          ].map((opt) {
                            final modeKey = opt['mode']!;
                            final selected = currentMode == modeKey;
                            return GestureDetector(
                              onTap: () async {
                                if (selected) return;
                                if (modeKey == 'exact' && !ApiService.exactLocationConsentNotifier.value) {
                                  await ApiService.recordExactLocationConsent(true);
                                }
                                setState(() {
                                  v['location_display_mode'] = modeKey;
                                  v['location_privacy_label'] = ApiService.formatLocationPrivacyLabel(modeKey);
                                });
                                if (videoId.isNotEmpty) {
                                  final updated = await ApiService.updateVideoSettings(
                                    videoId: videoId,
                                    locationDisplayMode: modeKey,
                                    exactLocationConsented: true,
                                  );
                                  if (mounted) {
                                    setState(() {
                                      v.addAll(updated);
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '위치 공개 정밀도가 [${ApiService.formatLocationPrivacyLabel(v['location_display_mode']?.toString())}]로 변경되었습니다.',
                                        ),
                                        backgroundColor: AppColors.primary,
                                      ),
                                    );
                                  }
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: selected ? AppColors.primary.withOpacity(0.28) : AppColors.background,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: selected ? AppColors.accent : AppColors.cardBorder,
                                    width: 0.9,
                                  ),
                                ),
                                child: Text(
                                  opt['label']!,
                                  style: TextStyle(
                                    color: selected ? AppColors.accent : AppColors.textMuted,
                                    fontSize: 10.5,
                                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildProviderChip(String key, String label) {
    final bool selected = _selectedProvider == key;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.background,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppColors.textMuted,
        fontSize: 12,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (_) {
        final handle = ApiService.currentUsername.replaceAll('@', '');
        setState(() {
          _selectedProvider = key;
          _supportFormError = null;
          if (key == 'kofi') {
            _supportUrlController.text = 'https://ko-fi.com/$handle';
          } else if (key == 'buymeacoffee') {
            _supportUrlController.text = 'https://buymeacoffee.com/$handle';
          } else {
            _supportUrlController.text = 'https://paypal.me/$handle';
          }
        });
      },
    );
  }

  void _showPaymentSettingsDialog() {
    final controller = TextEditingController(text: _selectedPayoutMethod);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('광고 수익 정산 계좌 설정', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '월별 크리에이터 풀 정산금을 지급받을 계좌를 설정합니다.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                labelText: '은행 및 계좌번호',
                labelStyle: TextStyle(color: AppColors.textMuted),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            onPressed: () {
              setState(() => _selectedPayoutMethod = controller.text.trim());
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('광고 수익 정산 계좌가 저장되었습니다.'), backgroundColor: AppColors.primary),
              );
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  void _showPayoutHistorySheet(int adRev) {
    final history = [
      {
        'month': '2026년 11월 정산',
        'amount': '₩${_formatCurrency(adRev)}',
        'status': '정산 대기',
        'detail': '크리에이터 풀 광고 수익 배분',
        'color': AppColors.warning,
      },
      {
        'month': '2026년 10월 정산',
        'amount': '₩44,400',
        'status': '지급 완료',
        'detail': '크리에이터 풀 광고 수익 배분',
        'color': AppColors.success,
      },
      {
        'month': '2026년 09월 정산',
        'amount': '₩34,600',
        'status': '지급 완료',
        'detail': '크리에이터 풀 광고 수익 배분',
        'color': AppColors.success,
      },
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '광고 수익 정산 및 지급 내역',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              '지급 계좌: $_selectedPayoutMethod',
              style: const TextStyle(color: AppColors.accent, fontSize: 12),
            ),
            const SizedBox(height: 14),
            ...history.map((item) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['month'] as String,
                              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13.5),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              item['detail'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            item['amount'] as String,
                            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item['status'] as String,
                            style: TextStyle(color: item['color'] as Color, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required String amount,
    required Color badgeColor,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: badgeColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: badgeColor, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
              ),
            ],
          ),
        ),
        Text(
          amount,
          style: TextStyle(color: badgeColor, fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildStatMiniBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: AppColors.accent,
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBox(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.accent, size: 18),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  String _formatCurrency(int val) {
    return val.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }
}

/// Spec #23 & #24: Splash / 3-Page Onboarding & Google/Apple Login Screen
class OnboardingLoginScreen extends StatefulWidget {
  const OnboardingLoginScreen({super.key});

  @override
  State<OnboardingLoginScreen> createState() => _OnboardingLoginScreenState();
}

class _OnboardingLoginScreenState extends State<OnboardingLoginScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isSigningIn = false;

  static const List<Map<String, dynamic>> _pages = [
    {
      'badge': '안내 1 · 현장 중심',
      'title': '지금 그곳에 있는 사람이 전합니다.',
      'desc': 'NOWFIELD는 전 세계 현장을 지금 그곳에 있는 사람들의 시선으로 실시간 연결하는 현장 네트워크입니다.',
      'icon': Icons.public_rounded,
    },
    {
      'badge': '안내 2 · 원테이크 · 최대 60초',
      'title': '편집하지 않습니다. 최대 60초.',
      'desc': '사진첩 업로드나 인위적인 편집 없이, NOWFIELD 카메라로 직접 촬영한 최대 60초의 원본 촬영 영상만 게시됩니다.',
      'icon': Icons.videocam_rounded,
    },
    {
      'badge': '안내 3 · 내 주변 1km · 최근 60분',
      'title': '내 주변 1km의 최근 현장을 확인하세요.',
      'desc': '지금 내 주변 반경 1km 이내에서 최근 60분 동안 올라온 생생한 현장 영상을 지도와 피드로 즉시 확인하세요.',
      'icon': Icons.location_on_rounded,
    },
  ];

  Future<void> _handleOAuthLogin(String provider) async {
    setState(() => _isSigningIn = true);
    await Future.delayed(const Duration(milliseconds: 500));
    final users = await ApiService.getAllUsers();
    if (users.isNotEmpty) {
      ApiService.loginAs(users.first);
    } else {
      await ApiService.createOrLoginUser('@seoul_walker');
    }
    if (!mounted) return;
    setState(() => _isSigningIn = false);
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$provider 계정 인증 완료! (${ApiService.currentUsername} 로그인됨)'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('서비스 안내 및 로그인'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // 3-Page Onboarding Carousel (Spec #23)
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _pages.length,
                  onPageChanged: (idx) => setState(() => _currentPage = idx),
                  itemBuilder: (context, idx) {
                    final p = _pages[idx];
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(26),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.accent.withOpacity(0.4), width: 1.5),
                          ),
                          child: Icon(p['icon'] as IconData, color: AppColors.accent, size: 56),
                        ),
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            p['badge'] as String,
                            style: const TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          p['title'] as String,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          p['desc'] as String,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 14, height: 1.5),
                        ),
                      ],
                    );
                  },
                ),
              ),

              // Page Indicators
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _pages.length,
                  (idx) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentPage == idx ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _currentPage == idx ? AppColors.accent : Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Spec #24: Login UI
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isSigningIn ? null : () => _handleOAuthLogin('Google'),
                  icon: const Icon(Icons.g_mobiledata_rounded, size: 28, color: Colors.blue),
                  label: const Text(
                    'Google 계정으로 계속하기',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: AppColors.card,
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: AppColors.cardBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isSigningIn ? null : () => _handleOAuthLogin('Apple'),
                  icon: const Icon(Icons.apple_rounded, size: 22, color: Colors.white),
                  label: const Text(
                    'Apple 계정으로 계속하기',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
