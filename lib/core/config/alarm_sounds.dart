class AlarmSound {
  final String id;
  final String name;
  final String assetPath;

  const AlarmSound({required this.id, required this.name, required this.assetPath});
}

/// Built-in alarm sounds bundled as assets (see `assets/sounds/*.wav` -
/// placeholder tones, swap for real audio before shipping).
class AlarmSounds {
  AlarmSounds._();

  static const List<AlarmSound> all = [
    AlarmSound(id: 'classic', name: 'Classic Beep', assetPath: 'assets/sounds/classic.wav'),
    AlarmSound(id: 'energetic', name: 'Energetic Bells', assetPath: 'assets/sounds/energetic.wav'),
    AlarmSound(id: 'gentle', name: 'Gentle Wake', assetPath: 'assets/sounds/gentle.wav'),
    AlarmSound(id: 'siren', name: 'Siren', assetPath: 'assets/sounds/siren.wav'),
  ];

  static AlarmSound byId(String id) => all.firstWhere((s) => s.id == id, orElse: () => all.first);

  static AlarmSound get defaultSound => all.first;
}
