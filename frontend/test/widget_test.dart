import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:preciops_frontend/main.dart';

void main() {
  testWidgets('App boots to the guest dashboard with a visible SOS button', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PreciopsApp()));
    await tester.pumpAndSettle();

    expect(find.text('SOS'), findsOneWidget);
    expect(find.text('Preciops'), findsOneWidget);
  });
}
