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
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  int _tabIndex = 0;
  bool _pairingDialogOpen = false;
  bool _shareDialogOpen = false;
  PendingPairingRequest? _displayedPairingRequest;
  BuildContext? _pairingDialogContext;
  PendingShareRequest? _displayedShareRequest;
  BuildContext? _shareDialogContext;
  bool _isForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.client.addListener(_checkPendingSecurityPrompts);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPendingSecurityPrompts());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (_isForeground != fg) {
      setState(() => _isForeground = fg);
    }
    widget.client.setAppLifecycle(isForeground: fg);
  }

  @override
  void dispose() {
    widget.client.removeListener(_checkPendingSecurityPrompts);
    WidgetsBinding.instance.removeObserver(this);
    widget.client.dispose();
    super.dispose();
  }

  void _checkPendingSecurityPrompts() {
    if (!mounted) return;
    final ctx = _navKey.currentContext;
    if (ctx == null) return;

    final pendingPair = widget.client.pendingPairing;
    if (_pairingDialogOpen && _displayedPairingRequest != null) {
      final displayed = _displayedPairingRequest!;
      if (pendingPair == null ||
          !identical(pendingPair, displayed) ||
          !pendingPair.matches(displayed)) {
        widget.client.dismissPendingPairing(displayed);
        final dCtx = _pairingDialogContext;
        _pairingDialogContext = null;
        if (dCtx != null && dCtx.mounted) {
          Navigator.of(dCtx).pop(false);
        }
        return;
      }
    }

    final pendingShare = widget.client.pendingShare;
    if (_shareDialogOpen && _displayedShareRequest != null) {
      final displayed = _displayedShareRequest!;
      if (pendingShare == null ||
          !identical(pendingShare, displayed) ||
          !pendingShare.matches(displayed)) {
        widget.client.dismissPendingShare(displayed);
        final dCtx = _shareDialogContext;
        _shareDialogContext = null;
        if (dCtx != null && dCtx.mounted) {
          Navigator.of(dCtx).pop(false);
        }
        return;
      }
    }

    if (pendingPair != null && !_pairingDialogOpen) {
      _pairingDialogOpen = true;
      _displayedPairingRequest = pendingPair;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          _pairingDialogOpen = false;
          _displayedPairingRequest = null;
          return;
        }
        _showPairingConfirmation(pendingPair);
      });
      return;
    }

    if (pendingShare != null && !_shareDialogOpen && !_pairingDialogOpen) {
      _shareDialogOpen = true;
      _displayedShareRequest = pendingShare;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          _shareDialogOpen = false;
          _displayedShareRequest = null;
          return;
        }
        _showShareConfirmation(pendingShare);
      });
    }
  }

  Future<void> _showPairingConfirmation(PendingPairingRequest req) async {
    final ctx = _navKey.currentContext;
    final current = widget.client.pendingPairing;
    if (ctx == null ||
        current == null ||
        !identical(current, req) ||
        !current.matches(req)) {
      _pairingDialogOpen = false;
      _displayedPairingRequest = null;
      _pairingDialogContext = null;
      widget.client.dismissPendingPairing(req);
      return;
    }
    final hasPin = req.tlsFingerprint.length == 64;
    final fpPreview = hasPin
        ? '${req.tlsFingerprint.substring(0, 16)}...${req.tlsFingerprint.substring(48)}'
        : 'None (unpinned)';
    final confirmed = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) {
        _pairingDialogContext = dialogCtx;
        return AlertDialog(
          backgroundColor: WizardColors.surfaceCard,
          title: Text(
            'Pair with New Omarchy Host?',
            style: TextStyle(color: WizardColors.textPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Confirming will switch your OmaLink destination and may relay private phone notifications, clipboard contents, and desktop controls to:',
                style: TextStyle(color: WizardColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Text(
                'Host: ${req.host}:${req.port}',
                style: TextStyle(
                  color: WizardColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Transport: ${req.useTls ? 'TLS Encrypted' : 'WARNING: Unencrypted HTTP'}',
                style: TextStyle(
                  color: req.useTls ? WizardColors.emeraldSage : WizardColors.coralError,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              if (req.useTls) ...[
                const SizedBox(height: 4),
                Text(
                  'Cert SHA-256: $fpPreview',
                  style: TextStyle(
                    color: hasPin ? WizardColors.cyanArcane : WizardColors.coralError,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
              if (req.useTls && !hasPin) ...[
                const SizedBox(height: 8),
                Text(
                  'Warning: Missing SHA-256 certificate pin. Self-signed TLS connections without a pin will be rejected.',
                  style: TextStyle(color: WizardColors.coralError, fontSize: 12),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final latest = widget.client.pendingPairing;
                final matchesDisplayed = latest != null &&
                    identical(latest, req) &&
                    latest.matches(req);
                Navigator.of(dialogCtx).pop(matchesDisplayed);
              },
              child: const Text('Confirm & Pair'),
            ),
          ],
        );
      },
    );
    _pairingDialogContext = null;
    _displayedPairingRequest = null;
    _pairingDialogOpen = false;
    if (confirmed == true) {
      await widget.client.confirmPendingPairing(req);
    } else {
      widget.client.dismissPendingPairing(req);
    }
    _checkPendingSecurityPrompts();
  }

  Future<void> _showShareConfirmation(PendingShareRequest req) async {
    final ctx = _navKey.currentContext;
    final current = widget.client.pendingShare;
    if (ctx == null ||
        current == null ||
        !identical(current, req) ||
        !current.matches(req)) {
      _shareDialogOpen = false;
      _displayedShareRequest = null;
      _shareDialogContext = null;
      widget.client.dismissPendingShare(req);
      return;
    }
    final summary = req.isFile ? 'File: ${req.filename}' : req.text;
    final confirmed = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) {
        _shareDialogContext = dialogCtx;
        return AlertDialog(
          backgroundColor: WizardColors.surfaceCard,
          title: Text(
            req.isFile ? 'Send File to Omarchy?' : 'Continue on Omarchy?',
            style: TextStyle(color: WizardColors.textPrimary),
          ),
          content: Text(
            summary.length > 260 ? '${summary.substring(0, 260)}...' : summary,
            style: TextStyle(color: WizardColors.textMuted, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final latest = widget.client.pendingShare;
                final matchesDisplayed = latest != null &&
                    identical(latest, req) &&
                    latest.matches(req);
                Navigator.of(dialogCtx).pop(matchesDisplayed);
              },
              child: const Text('Send to Omarchy'),
            ),
          ],
        );
      },
    );
    _shareDialogContext = null;
    _displayedShareRequest = null;
    _shareDialogOpen = false;
    if (confirmed == true) {
      await widget.client.confirmPendingShare(req);
    } else {
      widget.client.dismissPendingShare(req);
    }
    _checkPendingSecurityPrompts();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.client,
      builder: (context, _) {
        final palette = widget.client.activePalette;
        WizardColors.apply(palette);
        return MaterialApp(
          navigatorKey: _navKey,
          title: 'OmaLink',
          debugShowCheckedModeBanner: false,
          theme: WizardTheme.fromPalette(palette),
          home: Scaffold(
            body: TickerMode(
              enabled: _isForeground,
              child: IndexedStack(
                index: _tabIndex,
                children: [
                  WizardHomeScreen(
                    client: widget.client,
                    onOpenSettings: () => setState(() => _tabIndex = 4),
                  ),
                  ControlPlaneScreen(client: widget.client),
                  TerminalScreen(
                    client: widget.client,
                    isActive: _tabIndex == 2 && _isForeground,
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
