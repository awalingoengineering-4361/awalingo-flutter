import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// Mirrors neolingo/src/components/AudioPlayer.tsx: a simple play/pause
// toggle next to a neo suggestion, disabled/greyed out when there's no
// audioUrl, and — like the web version pausing every other <audio> element
// on play — pausing whichever other row is currently playing.
class NeoAudioPlayButton extends StatefulWidget {
  final String? audioUrl;
  const NeoAudioPlayButton({super.key, required this.audioUrl});

  @override
  State<NeoAudioPlayButton> createState() => _NeoAudioPlayButtonState();
}

class _NeoAudioPlayButtonState extends State<NeoAudioPlayButton> {
  static _NeoAudioPlayButtonState? _currentlyPlaying;

  final _player = AudioPlayer();
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlaying = false);
    });
  }

  @override
  void dispose() {
    if (_currentlyPlaying == this) _currentlyPlaying = null;
    _player.dispose();
    super.dispose();
  }

  Future<void> _pause() async {
    if (!_isPlaying) return;
    await _player.pause();
    if (mounted) setState(() => _isPlaying = false);
  }

  Future<void> _toggle() async {
    final url = widget.audioUrl;
    if (url == null || url.isEmpty) return;

    if (_isPlaying) {
      await _pause();
      return;
    }

    if (_currentlyPlaying != null && _currentlyPlaying != this) {
      await _currentlyPlaying!._pause();
    }
    _currentlyPlaying = this;

    await _player.play(UrlSource(url));
    if (mounted) setState(() => _isPlaying = true);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    final hasAudio = widget.audioUrl != null && widget.audioUrl!.isNotEmpty;
    return GestureDetector(
      onTap: hasAudio ? _toggle : null,
      child: Icon(
        _isPlaying ? Icons.pause_circle_outline : Icons.play_arrow,
        size: 22,
        color: hasAudio ? c.foreground : c.mutedForeground.withValues(alpha: 0.4),
      ),
    );
  }
}
