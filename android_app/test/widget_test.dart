import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:omarchy_wizard/main.dart';
import 'package:omarchy_wizard/models/wizard_mood.dart';
import 'package:omarchy_wizard/services/bridge_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Wizard app renders mascot, tabs, and casts a demo spell',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'wizard_demo': true});
    final client = BridgeClient();
    await client.init();

    await tester.pumpWidget(OmarchyWizardApp(client: client));
    await tester.pump();

    expect(find.text('Omarchy Wizard'), findsOneWidget);
    expect(client.mood, WizardMood.idle);

    // Tap the mascot to boop Arcane Agy
    await tester.tap(find.byType(CustomPaint).first);
    await tester.pump();
    expect(client.mood, WizardMood.celebrating);

    // Scroll to prompt composer and cast a demo spell
    await tester.scrollUntilVisible(
      find.text('Cast Spell'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Cast Spell'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Check Omarchy services');
    await tester.tap(find.text('Cast Spell'));
    await tester.pump();

    expect(client.tasks.length, 1);
    expect(client.tasks.first.prompt, 'Check Omarchy services');
    expect(client.mood, WizardMood.casting);

    // Advance timers so demo spell finishes cleanly
    await tester.pump(const Duration(seconds: 5));
    expect(client.tasks.first.status.isTerminal, isTrue);
  });
}
