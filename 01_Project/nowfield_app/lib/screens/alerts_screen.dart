import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/api_service.dart';
import 'earnings_screen.dart';
import 'profile_screen.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  String _selectedCategory = 'All';
  bool _isLoading = true;
  List<Map<String, dynamic>> _alerts = [];
  final Set<String> _reviewedAlertIds = {};

  static const List<Map<String, String>> _categories = [
    {'key': 'All', 'label': '전체'},
    {'key': 'Social', 'label': '소셜'},
    {'key': 'Moderation', 'label': '운영·검토'},
    {'key': 'License', 'label': '라이선스'},
    {'key': 'Earnings', 'label': '수익·정산'},
  ];

  String _categoryLabel(String category) {
    switch (category) {
      case 'Social':
        return '소셜';
      case 'Moderation':
        return '운영·검토';
      case 'License':
        return '라이선스';
      case 'Earnings':
        return '수익·정산';
      default:
        return '알림';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadAlerts();
    ApiService.currentUserNotifier.addListener(_loadAlerts);
  }

  @override
  void dispose() {
    ApiService.currentUserNotifier.removeListener(_loadAlerts);
    super.dispose();
  }

  Future<void> _loadAlerts() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final items = await ApiService.getAlerts();
    if (!mounted) return;
    setState(() {
      _alerts = items;
      _isLoading = false;
    });
  }

  List<Map<String, dynamic>> get _filteredAlerts {
    if (_selectedCategory == 'All') return _alerts;
    return _alerts.where((a) => a['category']?.toString() == _selectedCategory).toList();
  }

  IconData _iconForCategory(String category) {
    switch (category) {
      case 'Social':
        return Icons.person_add_alt_1_rounded;
      case 'Moderation':
        return Icons.shield_outlined;
      case 'License':
        return Icons.monetization_on_outlined;
      case 'Earnings':
        return Icons.account_balance_wallet_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _colorForCategory(String category) {
    switch (category) {
      case 'Social':
        return AppColors.accent;
      case 'Moderation':
        return AppColors.warning;
      case 'License':
        return AppColors.success;
      case 'Earnings':
        return const Color(0xFFA855F7);
      default:
        return AppColors.primary;
    }
  }

  void _handleAlertTap(Map<String, dynamic> alert) {
    final category = alert['category']?.toString() ?? 'Social';
    if (category == 'Moderation') {
      _showModerationAppealSheet(alert);
    } else if (category == 'License') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const EarningsScreen(initialTabIndex: 1)),
      );
    } else if (category == 'Earnings') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const EarningsScreen(initialTabIndex: 0)),
      );
    } else if (category == 'Social') {
      final targetUid = alert['target_user_id']?.toString() ?? 'u_apgu_now';
      final targetUname = alert['target_username']?.toString() ?? '@apgujeong_now';
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProfileScreen(targetUserId: targetUid, targetUsername: targetUname),
        ),
      );
    }
  }

  /// Spec #5.3 & #38: Post-Publication Private / Moderation Review Appeal UI
  void _showModerationAppealSheet(Map<String, dynamic> alert) {
    final alertId = alert['id']?.toString() ?? 'mod';
    final reason = alert['reason']?.toString() ?? '해당 영상에 대해 다수의 신고가 접수되어 확인 중입니다.';
    final videoTitle = alert['video_title']?.toString() ?? '현장 영상';
    final appealController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isReviewed = _reviewedAlertIds.contains(alertId);
            return Padding(
              padding: EdgeInsets.only(
                left: 22,
                right: 22,
                top: 18,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 26,
              ),
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
                  const SizedBox(height: 18),
                  Row(
                    children: const [
                      Icon(Icons.visibility_off_rounded, color: AppColors.warning, size: 26),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '영상이 임시 비공개로 전환되었습니다',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.warning.withOpacity(0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '대상 영상: $videoTitle',
                          style: const TextStyle(color: AppColors.accent, fontSize: 12.5, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '비공개 전환 사유:',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          reason == 'Multiple reports were received about this video.'
                              ? '해당 영상에 대해 다수의 신고가 접수되어 확인 중입니다.'
                              : reason,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '신고가 누적되거나 검토가 필요한 영상은 안전을 위해 임시 비공개 처리됩니다. 정책 위반이 아닌 정상적인 현장 기록이라면 재검토를 요청할 수 있습니다.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.45),
                  ),
                  const SizedBox(height: 14),
                  if (!isReviewed) ...[
                    TextField(
                      controller: appealController,
                      maxLines: 2,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: '(선택) 현장 상황 및 재검토 요청 사유를 입력해주세요',
                        hintStyle: const TextStyle(color: Colors.white30, fontSize: 12.5),
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.cardBorder),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          setState(() => _reviewedAlertIds.add(alertId));
                          setModalState(() {});
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(
                              content: Text('재검토 요청이 접수되었습니다. 운영팀 검토 후 결과가 안내됩니다.'),
                              backgroundColor: AppColors.primary,
                            ),
                          );
                        },
                        icon: const Icon(Icons.rate_review_outlined, size: 18),
                        label: const Text(
                          '재검토 요청하기',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ] else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.success),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.check_circle, color: AppColors.success, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '재검토 요청이 접수되어 운영팀 심사 대기 중입니다.',
                              style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredAlerts;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          '알림',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        actions: [
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textPrimary),
            onPressed: _loadAlerts,
          ),
        ],
      ),
      body: Column(
        children: [
          // Category Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: _categories.map((cat) {
                final key = cat['key']!;
                final label = cat['label']!;
                final isSelected = _selectedCategory == key;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: isSelected,
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.card,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : AppColors.textMuted,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12.5,
                    ),
                    onSelected: (_) => setState(() => _selectedCategory = key),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(color: AppColors.cardBorder, height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                : items.isEmpty
                    ? const Center(
                        child: Text(
                          '해당 카테고리의 알림이 없습니다.',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                        ),
                      )
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (context, index) => Divider(
                          color: AppColors.cardBorder.withOpacity(0.3),
                          height: 1,
                        ),
                        itemBuilder: (context, index) {
                          final alert = items[index];
                          final category = alert['category']?.toString() ?? 'Social';
                          final color = _colorForCategory(category);
                          final icon = _iconForCategory(category);
                          final alertId = alert['id']?.toString() ?? '';
                          final isReviewed = _reviewedAlertIds.contains(alertId);

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: CircleAvatar(
                              backgroundColor: color.withOpacity(0.18),
                              child: Icon(icon, color: color, size: 22),
                            ),
                            title: Row(
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    _categoryLabel(category),
                                    style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    alert['title']?.toString() ?? '',
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                isReviewed
                                    ? '재검토 요청 완료 · ${alert['created_at'] ?? ''}'
                                    : '${alert['subtitle'] ?? ''} · ${alert['created_at'] ?? ''}',
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 20),
                            onTap: () => _handleAlertTap(alert),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
