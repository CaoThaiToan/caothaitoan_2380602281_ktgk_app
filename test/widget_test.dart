import 'package:flutter_test/flutter_test.dart';
import 'package:caothaitoan_2380602281_ktgk_app/main.dart';

void main() {
  testWidgets('KidsSafeApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const KidsSafeApp());
    expect(find.byType(KidsSafeApp), findsOneWidget);
  });
}
