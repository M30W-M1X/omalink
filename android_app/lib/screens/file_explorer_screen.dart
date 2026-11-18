import 'package:material_ui/material_ui.dart';

import '../models/system_control.dart';
import '../services/bridge_client.dart';
import '../theme/wizard_theme.dart';

class FileExplorerScreen extends StatefulWidget {
  const FileExplorerScreen({
    super.key,
    required this.client,
    required this.onCastWizardInPath,
    required this.onOpenTerminalInPath,
  });

  final BridgeClient client;
  final VoidCallback onCastWizardInPath;
  final VoidCallback onOpenTerminalInPath;

  @override
  State<FileExplorerScreen> createState() => _FileExplorerScreenState();
}

class _FileExplorerScreenState extends State<FileExplorerScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.client.currentDirectory == null) {
      widget.client.browseDirectory();
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  Future<String?> _promptTextDialog({
    required String title,
    required String label,
    String initialValue = '',
    required String confirmLabel,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WizardColors.surfaceCard,
        title: Text(title, style: TextStyle(color: WizardColors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _newFolder(String currentPath) async {
    final name = await _promptTextDialog(
      title: 'Create Folder',
      label: 'Folder name',
      confirmLabel: 'Create',
    );
    if (name == null || name.isEmpty) return;
    await widget.client.createFolder(currentPath, name);
  }

  Future<void> _renameItem(FileEntry entry) async {
    final nextName = await _promptTextDialog(
      title: 'Rename ${entry.name}',
      label: 'New name',
      initialValue: entry.name,
      confirmLabel: 'Rename',
    );
    if (nextName == null || nextName.isEmpty || nextName == entry.name) return;
    await widget.client.renameEntry(entry.path, nextName);
  }

  Future<void> _trashItem(FileEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WizardColors.surfaceCard,
        title: Text('Move to Trash?', style: TextStyle(color: WizardColors.textPrimary)),
        content: Text(
          'Move "${entry.name}" to the desktop Trash?',
          style: TextStyle(color: WizardColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: WizardColors.coralError,
              foregroundColor: WizardColors.obsidian,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Trash'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.client.trashEntry(entry.path);
    }
  }

  Future<void> _openFileSheet(FileEntry entry) async {
    final preview = await widget.client.readFilePreview(entry.path);
    if (!mounted || preview == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WizardColors.surfaceCard,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.4,
          maxChildSize: 0.94,
          expand: false,
          builder: (_, scrollCtrl) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.description_outlined, color: WizardColors.cyanArcane),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          preview.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: WizardColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        _formatSize(preview.size),
                        style: TextStyle(color: WizardColors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const Text('Open on Desktop'),
                        onPressed: () => widget.client.openFileOnDesktop(preview.path),
                      ),
                      ActionChip(
                        avatar: Icon(Icons.download_rounded, size: 16, color: WizardColors.emeraldSage),
                        label: const Text('Download'),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final saved = await widget.client.downloadFileToPhone(
                            preview.path,
                            preview.name,
                          );
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                saved != null
                                    ? 'Saved to $saved'
                                    : 'Download failed for ${preview.name}',
                              ),
                            ),
                          );
                        },
                      ),
                      ActionChip(
                        avatar: Icon(Icons.auto_fix_high, size: 16, color: WizardColors.cyanArcane),
                        label: const Text('Ask Wizard'),
                        onPressed: () {
                          final dirPath = widget.client.currentDirectory?.path ?? '~';
                          Navigator.of(ctx).pop();
                          widget.client.stageAgentInDirectory(dirPath, filePath: preview.path);
                          widget.onCastWizardInPath();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: WizardColors.obsidian,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: WizardColors.borderSubtle),
                      ),
                      child: preview.isBinary
                          ? Center(
                              child: Text(
                                'Binary file — tap "Open on Desktop" to view in its desktop application.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: WizardColors.textMuted),
                              ),
                            )
                          : SingleChildScrollView(
                              controller: scrollCtrl,
                              child: SelectableText(
                                preview.content +
                                    (preview.truncated ? '\n\n... (preview truncated at 128 KB)' : ''),
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: WizardColors.textPrimary,
                                  height: 1.4,
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final listing = client.currentDirectory;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Omarchy File Explorer',
                        style: TextStyle(
                          color: WizardColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Toggle Hidden Files',
                      onPressed: () => client.browseDirectory(
                        listing?.path,
                        !client.showHiddenFiles,
                      ),
                      icon: Icon(
                        client.showHiddenFiles
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_outlined,
                        color: client.showHiddenFiles
                            ? WizardColors.cyanArcane
                            : WizardColors.textMuted,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Open Terminal Here',
                      onPressed: listing == null
                          ? null
                          : () {
                              client.stageTerminalInDirectory(listing.path);
                              widget.onOpenTerminalInPath();
                            },
                      icon: Icon(Icons.terminal_rounded, color: WizardColors.emeraldSage),
                    ),
                    IconButton(
                      tooltip: 'New Folder',
                      onPressed: listing == null ? null : () => _newFolder(listing.path),
                      icon: Icon(Icons.create_new_folder_outlined, color: WizardColors.cyanArcane),
                    ),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: client.filesLoading
                          ? null
                          : () => client.browseDirectory(listing?.path),
                      icon: Icon(Icons.refresh_rounded, color: WizardColors.cyanArcane),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (listing != null && listing.bookmarks.isNotEmpty)
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: listing.bookmarks.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (_, idx) {
                        final bm = listing.bookmarks[idx];
                        return ChoiceChip(
                          label: Text(bm.label),
                          selected: listing.path == bm.path,
                          onSelected: (_) => client.browseDirectory(bm.path),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: WizardColors.surfaceCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: WizardColors.borderSubtle),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Parent Folder',
                        onPressed: listing?.parent == null
                            ? null
                            : () => client.browseDirectory(listing!.parent),
                        icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                      ),
                      Expanded(
                        child: Text(
                          listing?.path ?? 'Loading...',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: WizardColors.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Open in Desktop Files',
                        onPressed: listing == null
                            ? null
                            : () => client.sendControlAction(
                                  'hyprland.launch_files',
                                  params: {'path': listing.path},
                                ),
                        icon: Icon(Icons.launch_rounded, size: 17, color: WizardColors.cyanArcane),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Open Terminal Here',
                        onPressed: listing == null
                            ? null
                            : () => client.sendControlAction(
                                  'hyprland.launch_terminal',
                                  params: {'path': listing.path},
                                ),
                        icon: Icon(Icons.terminal_rounded, size: 17, color: WizardColors.goldStarlight),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Cast Wizard Here',
                        onPressed: listing == null
                            ? null
                            : () {
                                client.stageAgentInDirectory(listing.path);
                                widget.onCastWizardInPath();
                              },
                        icon: Icon(Icons.auto_fix_high, size: 17, color: WizardColors.violetArcane),
                      ),
                    ],
                  ),
                ),
                if (client.filesError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    client.filesError!,
                    style: TextStyle(color: WizardColors.coralError, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: client.filesLoading && listing == null
                ? const Center(child: CircularProgressIndicator())
                : listing == null || listing.entries.isEmpty
                    ? Center(
                        child: Text(
                          listing == null ? 'Connect to Omarchy bridge to browse files.' : 'Folder is empty',
                          style: TextStyle(color: WizardColors.textMuted),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => client.browseDirectory(listing.path),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: listing.entries.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (_, idx) {
                            final entry = listing.entries[idx];
                            return Card(
                              margin: EdgeInsets.zero,
                              child: ListTile(
                                dense: true,
                                leading: Icon(
                                  entry.isDir
                                      ? Icons.folder_rounded
                                      : Icons.insert_drive_file_outlined,
                                  color: entry.isDir
                                      ? WizardColors.goldStarlight
                                      : WizardColors.cyanArcane,
                                ),
                                title: Text(
                                  entry.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: WizardColors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  entry.isDir ? 'Directory' : _formatSize(entry.size),
                                  style: TextStyle(
                                    color: WizardColors.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                                onTap: () {
                                  if (entry.isDir) {
                                    client.browseDirectory(entry.path);
                                  } else {
                                    _openFileSheet(entry);
                                  }
                                },
                                trailing: PopupMenuButton<String>(
                                  color: WizardColors.surfaceCard,
                                  onSelected: (choice) {
                                    switch (choice) {
                                      case 'open':
                                        client.openFileOnDesktop(entry.path);
                                        break;
                                      case 'wizard':
                                        final dir = entry.isDir ? entry.path : listing.path;
                                        client.stageAgentInDirectory(
                                          dir,
                                          filePath: entry.isDir ? null : entry.path,
                                        );
                                        widget.onCastWizardInPath();
                                        break;
                                      case 'rename':
                                        _renameItem(entry);
                                        break;
                                      case 'trash':
                                        _trashItem(entry);
                                        break;
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'open', child: Text('Open on Desktop')),
                                    PopupMenuItem(value: 'wizard', child: Text('Use in Wizard')),
                                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                                    PopupMenuItem(value: 'trash', child: Text('Move to Trash')),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
