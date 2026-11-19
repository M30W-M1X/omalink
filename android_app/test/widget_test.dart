import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:omalink/main.dart';
import 'package:omalink/models/wizard_avatar.dart';
import 'package:omalink/models/wizard_mood.dart';
import 'package:omalink/services/bridge_client.dart';
import 'package:omalink/widgets/arcane_wizard_mascot.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Wizard app renders mascot, tabs, and casts a demo spell',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'wizard_demo': true});
    final client = BridgeClient();
    await client.init();

    await tester.pumpWidget(OmarchyWizardApp(client: client));
    await tester.pump();

    expect(find.text('Tools'), findsOneWidget);
    expect(find.text('Sessions'), findsOneWidget);
    expect(find.text('Desktop'), findsOneWidget);
    expect(find.text('Trackpad'), findsOneWidget);
    expect(find.text('Continuity'), findsOneWidget);
    expect(client.mood, WizardMood.idle);

    // Peek into Live Agent Sessions and respond to a pending question
    await tester.tap(find.text('Sessions'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.text('Live Agent Sessions'), findsOneWidget);
    expect(find.text('OmaLink Marketplace Build'), findsOneWidget);
    await tester.tap(find.text('OmaLink Marketplace Build'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.text('NEEDS YOUR RESPONSE'), findsOneWidget);
    await tester.tap(find.text('Yes, tag & publish now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(client.sessions.first.state, 'running');
    await tester.tap(find.byTooltip('Back').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('Back').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Tap the mascot to boop Arcane Agy
    await tester.tap(find.byType(ArcaneWizardMascot));
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

    // Switch to Terminal tab and verify interactive Demo shell + quick keys
    await tester.tap(find.text('Terminal'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Omarchy Terminal'), findsOneWidget);
    expect(find.text('Demo Familiar Shell'), findsOneWidget);
    expect(find.text('CTRL'), findsOneWidget);
    expect(find.text('Pair Live'), findsOneWidget);

    // Return to Wizard tab, scroll back to top, and open Remote Desktop via labeled tile
    await tester.tap(find.text('Wizard'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, 600));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Desktop'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Omarchy Remote Desktop'), findsOneWidget);
    expect(find.text('Demo Familiar Desktop'), findsOneWidget);
    expect(find.text('R-Click'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('Tools'), findsOneWidget);

    // Open Tools -> Mascot Avatar & App Icon, switch to Anime Wizard, and apply icon
    await tester.tap(find.text('Tools'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Mascot Avatar & App Icon'), findsOneWidget);
    await tester.tap(find.text('Mascot Avatar & App Icon'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Anime Wizard'), findsOneWidget);
    await tester.tap(find.text('Anime Wizard'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(client.avatarStyle, WizardAvatarStyle.animeGirl);
    await tester.tap(find.text('Set "Anime Wizard" as App Icon'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(client.launcherIcon, WizardAvatarStyle.animeGirl);
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Open Tools menu sheet and tap Continuity & Notifications
    await tester.tap(find.text('Tools'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('COMPANION TOOLS'), findsOneWidget);
    await tester.tap(find.text('Continuity & Notifications'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('Omarchy Continuity'), findsOneWidget);
    expect(find.text('UNIVERSAL CLIPBOARD'), findsOneWidget);

    await tester.tap(find.text('Test Call'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('Sent call alert to Omarchy'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('CONTINUE ON OMARCHY'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('CONTINUE ON OMARCHY'), findsOneWidget);

    // Pop Continuity, open Control -> Trackpad & Presentation Remote
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    await tester.tap(find.text('Control'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.scrollUntilVisible(
      find.text('Trackpad'),
      -350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Trackpad'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('Wireless Trackpad'), findsOneWidget);
    await tester.tap(find.byTooltip('Presentation Mode'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('NEXT SLIDE'), findsOneWidget);
  });
}
