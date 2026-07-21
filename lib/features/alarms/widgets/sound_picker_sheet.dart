import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../../core/config/alarm_sounds.dart';

Future<AlarmSound?> showSoundPickerSheet(BuildContext context, {required String currentSoundId}) {
  return showModalBottomSheet<AlarmSound>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _SoundPickerContent(currentSoundId: currentSoundId),
  );
}

class _SoundPickerContent extends StatefulWidget {
  const _SoundPickerContent({required this.currentSoundId});

  final String currentSoundId;

  @override
  State<_SoundPickerContent> createState() => _SoundPickerContentState();
}

class _SoundPickerContentState extends State<_SoundPickerContent> {
  final _player = AudioPlayer();
  String? _playingId;

  @override
  void dispose() {
    _player.stop();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePreview(AlarmSound sound) async {
    if (_playingId == sound.id) {
      await _player.stop();
      setState(() => _playingId = null);
      return;
    }
    await _player.stop();
    await _player.play(AssetSource(sound.assetPath.replaceFirst('assets/', '')));
    setState(() => _playingId = sound.id);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('Choose a sound', style: Theme.of(context).textTheme.titleLarge),
          ),
          const SizedBox(height: 12),
          ...AlarmSounds.all.map((sound) {
            final isSelected = sound.id == widget.currentSoundId;
            final isPlaying = sound.id == _playingId;
            return ListTile(
              title: Text(sound.name),
              leading: Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: isSelected ? Colors.deepPurpleAccent : Colors.grey,
              ),
              trailing: IconButton(
                icon: Icon(isPlaying ? Icons.stop_circle_outlined : Icons.play_circle_outline),
                onPressed: () => _togglePreview(sound),
              ),
              onTap: () => Navigator.of(context).pop(sound),
            );
          }),
        ],
      ),
    );
  }
}
