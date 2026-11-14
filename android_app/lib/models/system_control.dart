class MemoryInfo {
  const MemoryInfo({
    required this.usedGb,
    required this.totalGb,
    required this.percent,
  });

  final double usedGb;
  final double totalGb;
  final double percent;

  factory MemoryInfo.fromJson(Map<String, dynamic> json) {
    return MemoryInfo(
      usedGb: (json['used_gb'] as num?)?.toDouble() ?? 0.0,
      totalGb: (json['total_gb'] as num?)?.toDouble() ?? 0.0,
      percent: (json['percent'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class BatteryInfo {
  const BatteryInfo({
    required this.present,
    required this.percent,
    required this.status,
  });

  final bool present;
  final int percent;
  final String status;

  factory BatteryInfo.fromJson(Map<String, dynamic> json) {
    return BatteryInfo(
      present: json['present'] == true,
      percent: (json['percent'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString() ?? 'none',
    );
  }
}

class AudioSink {
  const AudioSink({
    required this.id,
    required this.name,
    required this.description,
    required this.active,
  });

  final String id;
  final String name;
  final String description;
  final bool active;

  String get displayLabel => description.isNotEmpty ? description : name;

  factory AudioSink.fromJson(Map<String, dynamic> json) {
    return AudioSink(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      active: json['active'] == true,
    );
  }

  AudioSink copyWith({bool? active}) {
    return AudioSink(
      id: id,
      name: name,
      description: description,
      active: active ?? this.active,
    );
  }
}

class MediaPlayerState {
  const MediaPlayerState({
    required this.available,
    required this.busName,
    required this.identity,
    required this.status,
    required this.title,
    required this.artist,
    required this.album,
    required this.artUrl,
    required this.lengthMs,
    required this.positionMs,
    this.shuffle,
    this.loopStatus,
  });

  final bool available;
  final String busName;
  final String identity;
  final String status;
  final String title;
  final String artist;
  final String album;
  final String artUrl;
  final int lengthMs;
  final int positionMs;
  final bool? shuffle;
  final String? loopStatus;

  factory MediaPlayerState.fromJson(Map<String, dynamic> json) {
    return MediaPlayerState(
      available: json['available'] == true,
      busName: json['bus_name']?.toString() ?? '',
      identity: json['identity']?.toString() ?? '',
      status: json['status']?.toString() ?? 'Stopped',
      title: json['title']?.toString() ?? '',
      artist: json['artist']?.toString() ?? '',
      album: json['album']?.toString() ?? '',
      artUrl: json['art_url']?.toString() ?? '',
      lengthMs: (json['length_ms'] as num?)?.toInt() ?? 0,
      positionMs: (json['position_ms'] as num?)?.toInt() ?? 0,
      shuffle: json['shuffle'] as bool?,
      loopStatus: json['loop_status']?.toString(),
    );
  }

  MediaPlayerState copyWith({
    String? status,
    bool? shuffle,
    String? loopStatus,
  }) {
    return MediaPlayerState(
      available: available,
      busName: busName,
      identity: identity,
      status: status ?? this.status,
      title: title,
      artist: artist,
      album: album,
      artUrl: artUrl,
      lengthMs: lengthMs,
      positionMs: positionMs,
      shuffle: shuffle ?? this.shuffle,
      loopStatus: loopStatus ?? this.loopStatus,
    );
  }
}

class AudioState {
  const AudioState({
    required this.volume,
    required this.muted,
    required this.micMuted,
    required this.defaultSink,
    required this.sinks,
    required this.player,
    this.players = const [],
  });

  final int volume;
  final bool muted;
  final bool micMuted;
  final String defaultSink;
  final List<AudioSink> sinks;
  final MediaPlayerState player;
  final List<MediaPlayerState> players;

  factory AudioState.fromJson(Map<String, dynamic> json) {
    final rawSinks = json['sinks'] as List<dynamic>? ?? const [];
    final rawPlayers = json['players'] as List<dynamic>? ?? const [];
    return AudioState(
      volume: (json['volume'] as num?)?.toInt() ?? 0,
      muted: json['muted'] == true,
      micMuted: json['mic_muted'] == true,
      defaultSink: json['default_sink']?.toString() ?? '',
      sinks: rawSinks
          .whereType<Map<String, dynamic>>()
          .map(AudioSink.fromJson)
          .toList(),
      player: MediaPlayerState.fromJson(
        json['player'] as Map<String, dynamic>? ?? const {},
      ),
      players: rawPlayers
          .whereType<Map<String, dynamic>>()
          .map(MediaPlayerState.fromJson)
          .toList(),
    );
  }

  AudioState copyWith({
    int? volume,
    bool? muted,
    bool? micMuted,
    String? defaultSink,
    List<AudioSink>? sinks,
    MediaPlayerState? player,
    List<MediaPlayerState>? players,
  }) {
    return AudioState(
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      micMuted: micMuted ?? this.micMuted,
      defaultSink: defaultSink ?? this.defaultSink,
      sinks: sinks ?? this.sinks,
      player: player ?? this.player,
      players: players ?? this.players,
    );
  }
}

class BrightnessInfo {
  const BrightnessInfo({required this.available, required this.percent});

  final bool available;
  final int percent;

  factory BrightnessInfo.fromJson(Map<String, dynamic> json) {
    return BrightnessInfo(
      available: json['available'] == true,
      percent: (json['percent'] as num?)?.toInt() ?? 0,
    );
  }

  BrightnessInfo copyWith({bool? available, int? percent}) {
    return BrightnessInfo(
      available: available ?? this.available,
      percent: percent ?? this.percent,
    );
  }
}

class WorkspaceInfo {
  const WorkspaceInfo({
    required this.id,
    required this.name,
    required this.windows,
    required this.active,
  });

  final int id;
  final String name;
  final int windows;
  final bool active;

  factory WorkspaceInfo.fromJson(Map<String, dynamic> json) {
    return WorkspaceInfo(
      id: (json['id'] as num?)?.toInt() ?? 1,
      name: json['name']?.toString() ?? '1',
      windows: (json['windows'] as num?)?.toInt() ?? 0,
      active: json['active'] == true,
    );
  }

  WorkspaceInfo copyWith({bool? active}) {
    return WorkspaceInfo(
      id: id,
      name: name,
      windows: windows,
      active: active ?? this.active,
    );
  }
}

class ActiveWindowInfo {
  const ActiveWindowInfo({
    required this.title,
    required this.windowClass,
    required this.address,
  });

  final String title;
  final String windowClass;
  final String address;

  factory ActiveWindowInfo.fromJson(Map<String, dynamic> json) {
    return ActiveWindowInfo(
      title: json['title']?.toString() ?? '',
      windowClass: json['class']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
    );
  }
}

class HyprlandState {
  const HyprlandState({
    required this.workspaces,
    required this.activeWindow,
  });

  final List<WorkspaceInfo> workspaces;
  final ActiveWindowInfo activeWindow;

  factory HyprlandState.fromJson(Map<String, dynamic> json) {
    final rawWs = json['workspaces'] as List<dynamic>? ?? const [];
    return HyprlandState(
      workspaces: rawWs
          .whereType<Map<String, dynamic>>()
          .map(WorkspaceInfo.fromJson)
          .toList(),
      activeWindow: ActiveWindowInfo.fromJson(
        json['active_window'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }

  HyprlandState copyWith({
    List<WorkspaceInfo>? workspaces,
    ActiveWindowInfo? activeWindow,
  }) {
    return HyprlandState(
      workspaces: workspaces ?? this.workspaces,
      activeWindow: activeWindow ?? this.activeWindow,
    );
  }
}

class OmarchyToggles {
  const OmarchyToggles({
    required this.nightlight,
    required this.stayAwake,
    required this.barHidden,
    required this.screensaverOff,
    required this.animationsOff,
  });

  final bool nightlight;
  final bool stayAwake;
  final bool barHidden;
  final bool screensaverOff;
  final bool animationsOff;

  factory OmarchyToggles.fromJson(Map<String, dynamic> json) {
    return OmarchyToggles(
      nightlight: json['nightlight'] == true,
      stayAwake: json['stay_awake'] == true,
      barHidden: json['bar_hidden'] == true,
      screensaverOff: json['screensaver_off'] == true,
      animationsOff: json['animations_off'] == true,
    );
  }

  OmarchyToggles copyWith({
    bool? nightlight,
    bool? stayAwake,
    bool? barHidden,
    bool? screensaverOff,
    bool? animationsOff,
  }) {
    return OmarchyToggles(
      nightlight: nightlight ?? this.nightlight,
      stayAwake: stayAwake ?? this.stayAwake,
      barHidden: barHidden ?? this.barHidden,
      screensaverOff: screensaverOff ?? this.screensaverOff,
      animationsOff: animationsOff ?? this.animationsOff,
    );
  }
}

class ThemeState {
  const ThemeState({required this.current, required this.themes});

  final String current;
  final List<String> themes;

  factory ThemeState.fromJson(Map<String, dynamic> json) {
    final raw = json['themes'] as List<dynamic>? ?? const [];
    return ThemeState(
      current: json['current']?.toString() ?? '',
      themes: raw.map((e) => e.toString()).toList(),
    );
  }

  ThemeState copyWith({String? current, List<String>? themes}) {
    return ThemeState(
      current: current ?? this.current,
      themes: themes ?? this.themes,
    );
  }
}

class SecurityState {
  const SecurityState({
    required this.passwordlessSudo,
    this.bluetoothPowered,
    this.tailscaleActive,
  });

  final bool passwordlessSudo;
  final bool? bluetoothPowered;
  final bool? tailscaleActive;

  factory SecurityState.fromJson(Map<String, dynamic> json) {
    return SecurityState(
      passwordlessSudo: json['passwordless_sudo'] == true,
      bluetoothPowered: json['bluetooth_powered'] as bool?,
      tailscaleActive: json['tailscale_active'] as bool?,
    );
  }

  SecurityState copyWith({
    bool? passwordlessSudo,
    bool? bluetoothPowered,
    bool? tailscaleActive,
  }) {
    return SecurityState(
      passwordlessSudo: passwordlessSudo ?? this.passwordlessSudo,
      bluetoothPowered: bluetoothPowered ?? this.bluetoothPowered,
      tailscaleActive: tailscaleActive ?? this.tailscaleActive,
    );
  }
}

class SystemState {
  const SystemState({
    required this.hostname,
    required this.osVersion,
    required this.uptimeSeconds,
    required this.cpuPercent,
    required this.loadAvg,
    required this.memory,
    required this.battery,
    required this.audio,
    required this.brightness,
    required this.hyprland,
    required this.toggles,
    required this.theme,
    required this.security,
  });

  final String hostname;
  final String osVersion;
  final int uptimeSeconds;
  final double cpuPercent;
  final String loadAvg;
  final MemoryInfo memory;
  final BatteryInfo battery;
  final AudioState audio;
  final BrightnessInfo brightness;
  final HyprlandState hyprland;
  final OmarchyToggles toggles;
  final ThemeState theme;
  final SecurityState security;

  factory SystemState.fromJson(Map<String, dynamic> json) {
    return SystemState(
      hostname: json['hostname']?.toString() ?? 'omarchy-host',
      osVersion: json['os_version']?.toString() ?? 'Omarchy',
      uptimeSeconds: (json['uptime_seconds'] as num?)?.toInt() ?? 0,
      cpuPercent: (json['cpu_percent'] as num?)?.toDouble() ?? 0.0,
      loadAvg: json['load_avg']?.toString() ?? '0.00',
      memory: MemoryInfo.fromJson(json['memory'] as Map<String, dynamic>? ?? const {}),
      battery: BatteryInfo.fromJson(json['battery'] as Map<String, dynamic>? ?? const {}),
      audio: AudioState.fromJson(json['audio'] as Map<String, dynamic>? ?? const {}),
      brightness: BrightnessInfo.fromJson(json['brightness'] as Map<String, dynamic>? ?? const {}),
      hyprland: HyprlandState.fromJson(json['hyprland'] as Map<String, dynamic>? ?? const {}),
      toggles: OmarchyToggles.fromJson(json['toggles'] as Map<String, dynamic>? ?? const {}),
      theme: ThemeState.fromJson(json['theme'] as Map<String, dynamic>? ?? const {}),
      security: SecurityState.fromJson(json['security'] as Map<String, dynamic>? ?? const {}),
    );
  }

  factory SystemState.demo() {
    return const SystemState(
      hostname: 'arcane-tower (demo)',
      osVersion: '4.5.0-3',
      uptimeSeconds: 18420,
      cpuPercent: 14.0,
      loadAvg: '0.42',
      memory: MemoryInfo(usedGb: 13.0, totalGb: 64.0, percent: 20.3),
      battery: BatteryInfo(present: false, percent: 0, status: 'none'),
      audio: AudioState(
        volume: 42,
        muted: false,
        micMuted: false,
        defaultSink: 'demo-speakers',
        sinks: [
          AudioSink(
            id: '59',
            name: 'demo-speakers',
            description: 'Audioengine 2+ Desktop Speakers',
            active: true,
          ),
          AudioSink(
            id: '183',
            name: 'demo-hdmi',
            description: 'Odyssey G95C HDMI Audio',
            active: false,
          ),
        ],
        player: MediaPlayerState(
          available: true,
          busName: 'org.mpris.MediaPlayer2.spotify',
          identity: 'Spotify',
          status: 'Playing',
          title: 'Starfall Sanctum',
          artist: 'Omarchy Synth',
          album: 'Arcane Sessions',
          artUrl: '',
          lengthMs: 215000,
          positionMs: 42000,
          shuffle: false,
          loopStatus: 'None',
        ),
        players: [
          MediaPlayerState(
            available: true,
            busName: 'org.mpris.MediaPlayer2.spotify',
            identity: 'Spotify',
            status: 'Playing',
            title: 'Starfall Sanctum',
            artist: 'Omarchy Synth',
            album: 'Arcane Sessions',
            artUrl: '',
            lengthMs: 215000,
            positionMs: 42000,
            shuffle: false,
            loopStatus: 'None',
          ),
        ],
      ),
      brightness: BrightnessInfo(available: true, percent: 75),
      hyprland: HyprlandState(
        workspaces: [
          WorkspaceInfo(id: 1, name: '1', windows: 2, active: false),
          WorkspaceInfo(id: 2, name: '2', windows: 3, active: true),
          WorkspaceInfo(id: 3, name: '3', windows: 1, active: false),
        ],
        activeWindow: ActiveWindowInfo(
          title: 'omarchy_wizard — Agy',
          windowClass: 'ghostty',
          address: '0x1',
        ),
      ),
      toggles: OmarchyToggles(
        nightlight: false,
        stayAwake: true,
        barHidden: false,
        screensaverOff: false,
        animationsOff: false,
      ),
      theme: ThemeState(
        current: 'Everforest',
        themes: ['Everforest', 'Catppuccin', 'Gruvbox', 'Hackerman', 'Tokyo Night'],
      ),
      security: SecurityState(
        passwordlessSudo: false,
        bluetoothPowered: true,
        tailscaleActive: false,
      ),
    );
  }

  SystemState copyWith({
    AudioState? audio,
    BrightnessInfo? brightness,
    HyprlandState? hyprland,
    OmarchyToggles? toggles,
    ThemeState? theme,
    SecurityState? security,
  }) {
    return SystemState(
      hostname: hostname,
      osVersion: osVersion,
      uptimeSeconds: uptimeSeconds,
      cpuPercent: cpuPercent,
      loadAvg: loadAvg,
      memory: memory,
      battery: battery,
      audio: audio ?? this.audio,
      brightness: brightness ?? this.brightness,
      hyprland: hyprland ?? this.hyprland,
      toggles: toggles ?? this.toggles,
      theme: theme ?? this.theme,
      security: security ?? this.security,
    );
  }
}

class FileBookmark {
  const FileBookmark({required this.label, required this.path});

  final String label;
  final String path;

  factory FileBookmark.fromJson(Map<String, dynamic> json) {
    return FileBookmark(
      label: json['label']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
    );
  }
}

class FileEntry {
  const FileEntry({
    required this.name,
    required this.path,
    required this.isDir,
    required this.isSymlink,
    required this.size,
    required this.modified,
    required this.extension,
  });

  final String name;
  final String path;
  final bool isDir;
  final bool isSymlink;
  final int size;
  final String modified;
  final String extension;

  factory FileEntry.fromJson(Map<String, dynamic> json) {
    return FileEntry(
      name: json['name']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      isDir: json['is_dir'] == true,
      isSymlink: json['is_symlink'] == true,
      size: (json['size'] as num?)?.toInt() ?? 0,
      modified: json['modified']?.toString() ?? '',
      extension: json['extension']?.toString() ?? '',
    );
  }
}

class DirectoryListing {
  const DirectoryListing({
    required this.path,
    required this.parent,
    required this.showHidden,
    required this.truncated,
    required this.bookmarks,
    required this.entries,
  });

  final String path;
  final String? parent;
  final bool showHidden;
  final bool truncated;
  final List<FileBookmark> bookmarks;
  final List<FileEntry> entries;

  factory DirectoryListing.fromJson(Map<String, dynamic> json) {
    final rawBm = json['bookmarks'] as List<dynamic>? ?? const [];
    final rawEntries = json['entries'] as List<dynamic>? ?? const [];
    return DirectoryListing(
      path: json['path']?.toString() ?? '/',
      parent: json['parent']?.toString(),
      showHidden: json['show_hidden'] == true,
      truncated: json['truncated'] == true,
      bookmarks: rawBm
          .whereType<Map<String, dynamic>>()
          .map(FileBookmark.fromJson)
          .toList(),
      entries: rawEntries
          .whereType<Map<String, dynamic>>()
          .map(FileEntry.fromJson)
          .toList(),
    );
  }

  factory DirectoryListing.demo([String? path]) {
    final target = path ?? '/home/wizard/Projects';
    return DirectoryListing(
      path: target,
      parent: target == '/' ? null : '/home/wizard',
      showHidden: false,
      truncated: false,
      bookmarks: const [
        FileBookmark(label: 'Home', path: '/home/wizard'),
        FileBookmark(label: 'Projects', path: '/home/wizard/Projects'),
        FileBookmark(label: 'Downloads', path: '/home/wizard/Downloads'),
      ],
      entries: [
        FileEntry(
          name: 'omarchy_wizard',
          path: '$target/omarchy_wizard',
          isDir: true,
          isSymlink: false,
          size: 0,
          modified: '2026-11-13T19:00:00Z',
          extension: '',
        ),
        FileEntry(
          name: 'README.md',
          path: '$target/README.md',
          isDir: false,
          isSymlink: false,
          size: 2480,
          modified: '2026-11-13T18:30:00Z',
          extension: 'md',
        ),
        FileEntry(
          name: 'spellbook.json',
          path: '$target/spellbook.json',
          isDir: false,
          isSymlink: false,
          size: 842,
          modified: '2026-11-13T17:15:00Z',
          extension: 'json',
        ),
      ],
    );
  }
}

class FilePreview {
  const FilePreview({
    required this.path,
    required this.name,
    required this.size,
    required this.isBinary,
    required this.truncated,
    required this.content,
  });

  final String path;
  final String name;
  final int size;
  final bool isBinary;
  final bool truncated;
  final String content;

  factory FilePreview.fromJson(Map<String, dynamic> json) {
    return FilePreview(
      path: json['path']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      isBinary: json['is_binary'] == true,
      truncated: json['truncated'] == true,
      content: json['content']?.toString() ?? '',
    );
  }
}
