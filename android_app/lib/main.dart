import 'package:material_ui/material_ui.dart';

import 'screens/control_plane_screen.dart';
import 'screens/file_explorer_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/terminal_screen.dart';
import 'screens/wizard_home_screen.dart';
import 'services/bridge_client.dart';
import 'services/notification_service.dart';
import 'theme/wizard_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init(requestPermissionIfNeeded: true);
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

class _OmarchyWizardAppState extends State<OmarchyWizardApp>
    with WidgetsBindingObserver {
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.client.refreshVitalsShade();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.client.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.client,
      builder: (context, _) {
        final palette = widget.client.activePalette;
        WizardColors.apply(palette);
        return MaterialApp(
          title: 'OmaLink',
          debugShowCheckedModeBanner: false,
          theme: WizardTheme.fromPalette(palette),
          home: Scaffold(
            body: IndexedStack(
              index: _tabIndex,
              children: [
                WizardHomeScreen(
                  client: widget.client,
                  onOpenSettings: () => setState(() => _tabIndex = 4),
                ),
                ControlPlaneScreen(client: widget.client),
                TerminalScreen(
                  client: widget.client,
                  isActive: _tabIndex == 2,
                  onOpenSettings: () => setState(() => _tabIndex = 4),
                ),
                FileExplorerScreen(
                  client: widget.client,
                  onCastWizardInPath: () => setState(() => _tabIndex = 0),
                  onOpenTerminalInPath: () => setState(() => _tabIndex = 2),
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
                  icon: Icon(Icons.terminal_outlined),
                  selectedIcon: Icon(Icons.terminal),
                  label: 'Terminal',
                ),
                NavigationDestination(
                  icon: Icon(Icons.folder_outlined),
                  selectedIcon: Icon(Icons.folder),
                  label: 'Files',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Sanctum',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
