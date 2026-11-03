import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/api_service.dart';
import 'home_screen.dart';

/// Spec #11, #13, #48: Creator Earnings & Creator Pool Ledger Screen
class EarningsScreen extends StatefulWidget {
  final int initialTabIndex; // 0: Earnings (#48), 1: License Dashboard (#49)

  const EarningsScreen({super.key, this.initialTabIndex = 0});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  Map<String, dynamic>? _profileData;
  String _selectedPayoutMethod = '카카오뱅크 · 3333-02-XXXXXX (원화)';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTabIndex);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final data = await ApiService.getUserProfile(ApiService.currentUserId);
    if (!mounted) return;
    setState(() {
      _profileData = data;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final licenseRev = (_profileData?['total_creator_revenue'] as int?) ?? 22000;
    final totalSales = (_profileData?['total_license_sales'] as int?) ?? 3;
    final adRev = 51240; // Spec #48 Advertising (Creator Pool 30% WQV share)
    final totalAvailable = adRev + (licenseRev > 0 ? licenseRev : 22000);

    final rawVideos = (_profileData?['videos'] as List<dynamic>?) ?? [];
    final videos = rawVideos.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

    final rawLicensed = (_profileData?['licensed_videos'] as List<dynamic>?) ?? [];
    final licensedVideos = rawLicensed.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('수익 및 라이선스'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textMuted,
          tabs: const [
            Tab(text: '수익 정산'),
            Tab(text: '라이선스 관리'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildEarningsTab(
                  totalAvailable: totalAvailable,
                  adRev: adRev,
                  licenseRev: licenseRev > 0 ? licenseRev : 22000,
                ),
                _buildLicenseDashboardTab(
                  activeVideos: videos,
                  licensedVideos: licensedVideos,
                  totalSales: totalSales > 0 ? totalSales : 3,
                  licenseRev: licenseRev > 0 ? licenseRev : 22000,
                ),
              ],
            ),
    );
  }

  /// Spec #48: Earnings UI
  Widget _buildEarningsTab({
    required int totalAvailable,
    required int adRev,
    required int licenseRev,
  }) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        // Available Balance Card
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
                    '정산 가능 금액',
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
                '₩${_formatCurrency(totalAvailable)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '이번 달 수익  ₩${_formatCurrency(totalAvailable)}',
                style: const TextStyle(color: AppColors.accent, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Breakdown Card (Advertising + Licenses)
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
                '수익 구성 상세',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              _buildRevenueRow(
                icon: Icons.campaign_outlined,
                title: '광고 수익 (크리에이터 풀 30%)',
                subtitle: '산정식: 크리에이터 풀 × (내 유효 조회 품질 지수 1,420 ÷ 전체 지수)',
                amount: '₩${_formatCurrency(adRev)}',
                badgeColor: AppColors.accent,
              ),
              const Divider(color: AppColors.cardBorder, height: 24),
              _buildRevenueRow(
                icon: Icons.workspace_premium_outlined,
                title: '라이선스 수익 (크리에이터 80%)',
                subtitle: '배분 가능 순액 기준 80% 크리에이터 정산 (플랫폼 수수료 20%)',
                amount: '₩${_formatCurrency(licenseRev)}',
                badgeColor: AppColors.success,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // WQV Quality Formula Explanation Card (Spec #11.1)
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
                  '유효 조회 품질 지수: 단순 조회수가 아닌 실제 시청 시간 비율을 반영하며, 비정상·반복 조회 및 제재 영상은 정산에서 제외됩니다.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.45),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Spec #48 Action Buttons: [ Payment Settings ] & [ Payout History ]
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
                onPressed: () => _showPayoutHistorySheet(totalAvailable),
                icon: const Icon(Icons.receipt_long_rounded, size: 18),
                label: const Text('정산 지급 내역', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Spec #49: License Dashboard UI
  Widget _buildLicenseDashboardTab({
    required List<Map<String, dynamic>> activeVideos,
    required List<Map<String, dynamic>> licensedVideos,
    required int totalSales,
    required int licenseRev,
  }) {
    final activeCount = activeVideos.where((v) => ((v['license_price'] as int?) ?? 10000) > 0).length;

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        // Summary Stats Row
        Row(
          children: [
            Expanded(
              child: _buildStatBox('판매 중 영상', '$activeCount', Icons.video_library_outlined),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildStatBox('총 판매 건수', '$totalSales', Icons.shopping_bag_outlined),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildStatBox('누적 수익', '₩${_formatCurrency(licenseRev)}', Icons.payments_outlined),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // [ Active Videos ] Section (with Spec #45 License Price Settings)
        const Text(
          '내 영상 라이선스 가격 설정',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        if (activeVideos.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '게시한 현장 영상이 없습니다. 촬영 탭에서 첫 영상을 촬영해보세요.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          )
        else
          ...activeVideos.map((v) {
            final price = (v['license_price'] as int?) ?? 10000;
            final isEnabled = price > 0;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.videocam_rounded, color: AppColors.accent, size: 22),
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
                          isEnabled
                              ? '표준 상업 라이선스 · ₩${_formatCurrency(price)}'
                              : '라이선스 판매 비활성화',
                          style: TextStyle(
                            color: isEnabled ? AppColors.accent : AppColors.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _showEditLicensePriceDialog(v),
                    child: const Text('가격/상태 변경', style: TextStyle(color: AppColors.accent, fontSize: 12)),
                  ),
                ],
              ),
            );
          }),

        const SizedBox(height: 18),
        const Text(
          '라이선스 거래 내역',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        if (licensedVideos.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: const Text(
              '최근 라이선스 거래 내역이 여기에 표시됩니다. (예: 표준 상업 라이선스 ₩10,000 · 크리에이터 80% 정산)',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
            ),
          )
        else
          ...licensedVideos.map((lv) {
            final price = (lv['license_price'] as int?) ?? 10000;
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              tileColor: AppColors.card,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: const Icon(Icons.verified_rounded, color: AppColors.success),
              title: Text(
                lv['title']?.toString() ?? '현장 영상',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '표준 상업 라이선스 · 결제액 ₩${_formatCurrency(price)}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
              ),
              trailing: const Icon(Icons.play_circle_outline, color: AppColors.accent),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => VideoDetailScreen(videoData: lv)),
                );
              },
            );
          }),
      ],
    );
  }

  /// Spec #45: License Price Setting Dialog
  void _showEditLicensePriceDialog(Map<String, dynamic> video) {
    int currentPrice = (video['license_price'] as int?) ?? 10000;
    bool enabled = currentPrice > 0;
    final controller = TextEditingController(text: (currentPrice > 0 ? currentPrice : 10000).toString());

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.card,
              title: const Text(
                '라이선스 판매 설정',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppColors.accent,
                    title: const Text('이 영상 라이선스 판매', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                    subtitle: Text(
                      enabled ? '● 켜짐 (판매 활성화)' : '○ 꺼짐 (판매 비활성화)',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                    value: enabled,
                    onChanged: (val) => setDialogState(() => enabled = val),
                  ),
                  if (enabled) ...[
                    const SizedBox(height: 8),
                    const Text('기본 추천 가격', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [1000, 5000, 10000, 30000].map((preset) {
                        final isSelected = controller.text == preset.toString();
                        return ChoiceChip(
                          label: Text('₩${_formatCurrency(preset)}'),
                          selected: isSelected,
                          selectedColor: AppColors.primary,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : AppColors.textMuted,
                            fontSize: 12,
                          ),
                          onSelected: (_) {
                            setDialogState(() {
                              controller.text = preset.toString();
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                      decoration: const InputDecoration(
                        labelText: '직접 가격 입력 (원)',
                        labelStyle: TextStyle(color: AppColors.textMuted, fontSize: 12),
                        prefixText: '₩ ',
                      ),
                    ),
                  ],
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
                    final newPrice = enabled ? (int.tryParse(controller.text.trim()) ?? 10000) : 0;
                    setState(() {
                      video['license_price'] = newPrice;
                    });
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                        content: Text(
                          enabled ? '라이선스 가격이 ₩${_formatCurrency(newPrice)}으로 저장되었습니다.' : '라이선스 판매가 비활성화되었습니다.',
                        ),
                        backgroundColor: AppColors.primary,
                      ),
                    );
                  },
                  child: const Text('저장'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showPaymentSettingsDialog() {
    final controller = TextEditingController(text: _selectedPayoutMethod);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('정산 계좌 설정', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '월별 크리에이터 풀 광고 수익 및 라이선스 판매 정산금을 지급받을 계좌를 설정합니다.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
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
                const SnackBar(content: Text('정산 지급 계좌가 저장되었습니다.'), backgroundColor: AppColors.primary),
              );
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  void _showPayoutHistorySheet(int totalAvailable) {
    final history = [
      {
        'month': '2026년 10월 정산 (예정)',
        'amount': '₩${_formatCurrency(totalAvailable)}',
        'status': '정산 대기',
        'detail': '광고 수익 ₩51,240 + 라이선스 ₩${_formatCurrency(totalAvailable - 51240)}',
        'color': AppColors.warning,
      },
      {
        'month': '2026년 09월 정산',
        'amount': '₩64,800',
        'status': '지급 완료',
        'detail': '광고 수익 ₩44,400 + 라이선스 ₩20,400',
        'color': AppColors.success,
      },
      {
        'month': '2026년 08월 정산',
        'amount': '₩48,200',
        'status': '지급 완료',
        'detail': '광고 수익 ₩34,600 + 라이선스 ₩13,600',
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
              '정산 및 지급 내역',
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
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
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
      'badge': '안내 3 · 내 주변 1km · 최근 1시간',
      'title': '내 주변 1km의 최근 현장을 확인하세요.',
      'desc': '지금 내 주변 반경 1km 이내에서 최근 1시간 동안 올라온 생생한 현장 영상을 지도와 피드로 즉시 확인하세요.',
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
