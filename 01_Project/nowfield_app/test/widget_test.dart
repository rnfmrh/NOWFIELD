import 'package:flutter_test/flutter_test.dart';
import 'package:nowfield_app/main.dart';
import 'package:nowfield_app/services/api_service.dart';

void main() {
  testWidgets('NOWFIELD app smoke test & CR-01~04 unit checks', (WidgetTester tester) async {
    await tester.pumpWidget(const NowfieldApp());
    expect(find.text('홈'), findsOneWidget);
    expect(find.text('내 주변'), findsOneWidget);
    expect(find.text('촬영'), findsOneWidget);
    expect(find.text('알림'), findsOneWidget);
    expect(find.text('프로필'), findsOneWidget);

    // CR-01: Support URL validation
    expect(ApiService.validateSupportUrl('kofi', 'https://ko-fi.com/seoul_walker'), isNull);
    expect(ApiService.validateSupportUrl('buymeacoffee', 'https://buymeacoffee.com/apgu_now'), isNull);
    expect(ApiService.validateSupportUrl('kofi', 'http://ko-fi.com/seoul_walker'), isNotNull);
    expect(ApiService.validateSupportUrl('kofi', 'https://evil-domain.com/seoul_walker'), isNotNull);

    // CR-02: Location privacy label formatting
    expect(ApiService.formatLocationPrivacyLabel('exact'), '정확한 위치');
    expect(ApiService.formatLocationPrivacyLabel('approximate'), '약 100~200m 범위');
    expect(ApiService.formatLocationPrivacyLabel('hidden'), '위치 미표시');

    // CR-03: Absolute timestamp formatting (Korean & English)
    ApiService.appLanguageNotifier.value = '한국어';
    final koTime = ApiService.formatPublishedDateTime('2026-11-12T10:30:00Z', timezone: 'Asia/Seoul');
    expect(koTime, '2026.11.12. 오후 7:30');

    ApiService.appLanguageNotifier.value = '영어';
    final enTime = ApiService.formatPublishedDateTime('2026-11-12T10:30:00Z', timezone: 'Asia/Seoul');
    expect(enTime, '7:30 PM · Nov 12, 2026');
    ApiService.appLanguageNotifier.value = '한국어';
  });
}
