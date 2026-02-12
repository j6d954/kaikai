import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Insurance advisor home renders key sections', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: InsuranceAdvisorApp()));
    await tester.pumpAndSettle();

    expect(find.text('個人保險顧問'), findsOneWidget);
    expect(find.text('總覽'), findsOneWidget);
    expect(find.text('評估'), findsOneWidget);
    expect(find.text('建議'), findsOneWidget);
    expect(find.text('比較'), findsOneWidget);
    expect(find.text('保單'), findsOneWidget);

    await tester.tap(find.text('總覽'));
    await tester.pumpAndSettle();

    expect(find.text('保障全景'), findsOneWidget);

    await tester.tap(find.text('比較'));
    await tester.pumpAndSettle();

    expect(find.text('方案比較'), findsOneWidget);

    await tester.tap(find.text('保單'));
    await tester.pumpAndSettle();

    expect(find.text('保單管理'), findsOneWidget);
    expect(find.textContaining('7 日內繳費提醒'), findsOneWidget);
    expect(find.textContaining('60 日內到期提醒'), findsOneWidget);
  });
}
