import 'package:flutter_test/flutter_test.dart';

import 'package:vt/main.dart';

void main() {
  testWidgets('App launches', (WidgetTester tester) async {
    await tester.pumpWidget(const VTApp());
    expect(find.text('VT Accident Detection'), findsOneWidget);
  });
}
