import 'package:flutter_test/flutter_test.dart';
import 'package:checkpoint_scanner/main.dart';

void main() {
  testWidgets('App renders', (WidgetTester tester) async {
    await tester.pumpWidget(const CheckpointApp());
    expect(find.text('Checkpoint Scanner'), findsOneWidget);
  });
}
