import 'package:material_ui/material_ui.dart';

import 'screens/control_plane_screen.dart';
import 'screens/file_explorer_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/spellbook_screen.dart';
import 'screens/wizard_home_screen.dart';
import 'services/bridge_client.dart';
import 'services/notification_service.dart';
import 'theme/wizard_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  final client = BridgeClient();
  await client.init();
  runApp(OmarchyWizardApp(client: client));
}

class OmarchyWizardApp extends StatefulWidget {
  const OmarchyWizardApp({
    super.key,
    required this.client,
  });

  final BridgeClient client;

  @override
  State<OmarchyWizardApp> createState() => _OmarchyWizardAppState();
}

class _OmarchyWizardAppState extends State<OmarchyWizardApp> {
  int _tabIndex = 0;

  @override
  void dispose() {
    widget.client.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Omarchy Wizard',
      debugShowCheckedModeBanner: false,
      theme: WizardTheme.darkTheme(),
      home: AnimatedBuilder(
        animation: widget.client,
        builder: (context, _) {
          return Scaffold(
            body: IndexedStack(
              index: _tabIndex,
              children: [
                WizardHomeScreen(
                  client: widget.client,
                  onOpenSettings: () => setState(() => _tabIndex = 4),
                ),
                ControlPlaneScreen(client: widget.client),
                FileExplorerScreen(
                  client: widget.client,
                  onCastWizardInPath: () => setState(() => _tabIndex = 0),
                ),
                SpellbookScreen(
                  client: widget.client,
                  onInspectInHome: () => setState(() => _tabIndex = 0),
                ),
                SettingsScreen(client: widget.client),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _tabIndex,
              onDestinationSelected: (idx) => setState(() => _tabIndex = idx),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.auto_fix_high_outlined),
                  selectedIcon: Icon(Icons.auto_fix_high),
                  label: 'Wizard',
                ),
                NavigationDestination(
                  icon: Icon(Icons.tune_outlined),
                  selectedIcon: Icon(Icons.tune),
                  label: 'Control',
                ),
                NavigationDestination(
                  icon: Icon(Icons.folder_outlined),
                  selectedIcon: Icon(Icons.folder),
                  label: 'Files',
                ),
                NavigationDestination(
                  icon: Icon(Icons.menu_book_outlined),
                  selectedIcon: Icon(Icons.menu_book),
                  label: 'Spells',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Sanctum',
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
