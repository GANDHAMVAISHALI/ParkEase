import 'package:flutter_test/flutter_test.dart';
import 'package:parkease/main.dart';

void main() {
  testWidgets('ParkEase loads successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const ParkEaseApp());

    expect(find.text('Welcome to ParkEase'), findsOneWidget);
    expect(find.text('Parking Overview'), findsOneWidget);
  });
}