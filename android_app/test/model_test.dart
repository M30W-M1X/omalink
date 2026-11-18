import 'package:flutter_test/flutter_test.dart';
import 'package:omarchy_wizard/models/agent_task.dart';
import 'package:omarchy_wizard/models/system_control.dart';
import 'package:omarchy_wizard/models/wizard_mood.dart';
import 'package:omarchy_wizard/theme/wizard_theme.dart';

void main() {
  test('AgentTask.fromJson parses bridge payload', () {
    final task = AgentTask.fromJson({
      'id': 'abc123',
      'prompt': 'Summarize git diff',
      'agent': 'agy',
      'mode': 'auto',
      'effort': 'high',
      'cwd': '/home/jgillman/Work',
      'status': 'completed',
      'created_at': '2026-11-13T16:00:00Z',
      'finished_at': '2026-11-13T16:00:05Z',
      'duration_seconds': 5.0,
      'exit_code': 0,
      'summary': 'All clean!',
      'conversation_id': 'conv-42',
      'events': [
        {
          'ts': '2026-11-13T16:00:02Z',
          'stream': 'stdout',
          'kind': 'assistant',
          'text': 'Checking git status...',
        }
      ],
    });

    expect(task.id, 'abc123');
    expect(task.status, TaskStatus.completed);
    expect(task.status.isTerminal, isTrue);
    expect(task.durationSeconds, 5.0);
    expect(task.conversationId, 'conv-42');
    expect(task.events.length, 1);
    expect(task.events.first.text, 'Checking git status...');
  });

  test('WizardMood exposes badge labels and quips', () {
    for (final mood in WizardMood.values) {
      expect(mood.badgeLabel, isNotEmpty);
      expect(mood.defaultQuip, isNotEmpty);
    }
  });

  test('SystemState and DirectoryListing parse bridge control payloads', () {
    final state = SystemState.fromJson({
      'hostname': 'kitsune',
      'os_version': '4.5.0-3',
      'uptime_seconds': 3600,
      'cpu_percent': 18.0,
      'load_avg': '0.35',
      'memory': {'used_gb': 12.0, 'total_gb': 64.0, 'percent': 18.8},
      'battery': {'present': false, 'percent': 0, 'status': 'none'},
      'audio': {
        'volume': 35,
        'muted': false,
        'mic_muted': true,
        'default_sink': 'usb-1',
        'sinks': [
          {'id': '59', 'name': 'usb-1', 'description': 'Speakers', 'active': true}
        ],
        'player': {'available': false, 'status': 'Stopped', 'title': '', 'artist': ''},
      },
      'brightness': {'available': false, 'percent': 0},
      'hyprland': {
        'workspaces': [
          {'id': 2, 'name': '2', 'windows': 3, 'active': true}
        ],
        'active_window': {'title': 'Alacritty', 'class': 'Alacritty', 'address': '0x2'},
      },
      'toggles': {
        'nightlight': true,
        'stay_awake': false,
        'bar_hidden': false,
        'screensaver_off': false,
        'animations_off': false,
      },
      'theme': {
        'current': 'Everforest',
        'themes': ['Everforest', 'Catppuccin'],
      },
      'security': {
        'passwordless_sudo': true,
        'bluetooth_powered': true,
        'tailscale_active': false,
      },
    });

    expect(state.hostname, 'kitsune');
    expect(state.audio.volume, 35);
    expect(state.audio.micMuted, isTrue);
    expect(state.audio.sinks.first.displayLabel, 'Speakers');
    expect(state.toggles.nightlight, isTrue);
    expect(state.theme.current, 'Everforest');
    expect(state.security.passwordlessSudo, isTrue);

    final dir = DirectoryListing.fromJson({
      'path': '/home/jgillman/Projects',
      'parent': '/home/jgillman',
      'show_hidden': false,
      'truncated': false,
      'bookmarks': [
        {'label': 'Home', 'path': '/home/jgillman'}
      ],
      'entries': [
        {
          'name': 'omarchy_wizard',
          'path': '/home/jgillman/Projects/omarchy_wizard',
          'is_dir': true,
          'is_symlink': false,
          'size': 0,
          'modified': '2026-11-13T19:00:00Z',
          'extension': '',
        }
      ],
    });
    expect(dir.entries.length, 1);
    expect(dir.entries.first.isDir, isTrue);
    expect(dir.bookmarks.first.label, 'Home');
  });

  test('WizardPalette parses dark and light Omarchy themes dynamically', () {
    final nord = WizardPalette.fromOmarchyJson({
      'slug': 'nord',
      'name': 'Nord',
      'mode': 'dark',
      'colors': {
        'accent': '#81a1c1',
        'background': '#2e3440',
        'darker_background': '#191c23',
        'foreground': '#d8dee9',
        'cyan': '#88c0d0',
      },
    });
    expect(nord.slug, 'nord');
    expect(nord.isLight, isFalse);
    expect(nord.violetArcane.toARGB32(), 0xFF81A1C1);
    expect(nord.obsidian.toARGB32(), 0xFF191C23);

    final latte = WizardPalette.fromOmarchyJson({
      'slug': 'catppuccin-latte',
      'name': 'Catppuccin Latte',
      'mode': 'light',
      'colors': {
        'accent': '#1e66f5',
        'background': '#eff1f5',
        'dark_background': '#e3e4e8',
        'foreground': '#4c4f69',
      },
    });
    expect(latte.isLight, isTrue);
    expect(latte.obsidian.toARGB32(), 0xFFEFF1F5);
    expect(latte.textPrimary.toARGB32(), 0xFF4C4F69);
    expect(WizardTheme.fromPalette(latte).brightness.name, 'light');
  });
}
