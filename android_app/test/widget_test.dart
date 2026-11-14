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

    // Switch to Control Plane tab and verify audio/theme/passwordless sudo controls
    await tester.tap(find.text('Control'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Omarchy Control Plane'), findsOneWidget);
    expect(find.text('Mute'), findsOneWidget);

    await tester.tap(find.text('Mute'));
    await tester.pump(const Duration(seconds: 3));
    expect(client.systemState.audio.muted, isTrue);

    await tester.scrollUntilVisible(
      find.text('Prompt 15m'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('PROTECTED'), findsOneWidget);

    await tester.tap(find.text('Prompt 15m'));
    await tester.pump();
    expect(client.systemState.security.passwordlessSudo, isTrue);

    // Switch to Files tab and verify File Explorer listing
    await tester.tap(find.text('Files'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Omarchy File Explorer'), findsOneWidget);
    expect(find.text('omarchy_wizard'), findsOneWidget);
  });
}
