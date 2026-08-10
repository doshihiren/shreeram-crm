import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shreeram_crm/app/app.dart';

void main() {
  testWidgets('ShreeRam app boots to login brand', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ShreeRamApp()));
    await tester.pumpAndSettle();
    expect(find.text('ShreeRam'), findsWidgets);
  });
}
