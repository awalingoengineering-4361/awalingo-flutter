import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

// Mirrors neolingo/src/components/AudioRecorder.tsx: record → upload to the
// same 'neo-audio-recordings' Supabase Storage bucket → store the public URL.
// The bar shows "Voice" + a record button when empty, "Recording..." + a
// pulsing stop button while recording, and — once there's a clip — the text
// is replaced entirely by Play/Pause, a waveform glyph, and Trash spread
// across the bar, exactly like the web component's three visual states.
const kNeoAudioBucket = 'neo-audio-recordings';

class AudioRecorderField extends StatefulWidget {
  final String? audioUrl;
  final ValueChanged<String?> onChanged;

  const AudioRecorderField({
    super.key,
    required this.audioUrl,
    required this.onChanged,
  });

  @override
  State<AudioRecorderField> createState() => _AudioRecorderFieldState();
}

class _AudioRecorderFieldState extends State<AudioRecorderField> {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  bool _recording = false;
  bool _uploading = false;
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
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(fontFamily: 'Metropolis')),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        _toast('Microphone access denied');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      if (mounted) setState(() => _recording = true);
    } catch (_) {
      _toast('Microphone access denied');
    }
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    if (mounted) setState(() { _recording = false; _uploading = true; });
    if (path == null) {
      if (mounted) setState(() => _uploading = false);
      return;
    }
    await _upload(File(path));
  }

  Future<void> _upload(File file) async {
    try {
      final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final storage = Supabase.instance.client.storage.from(kNeoAudioBucket);
      await storage.upload(
        fileName,
        file,
        fileOptions: const FileOptions(
          contentType: 'audio/m4a',
          cacheControl: '3600',
          upsert: false,
        ),
      );
      widget.onChanged(storage.getPublicUrl(fileName));
    } catch (_) {
      _toast('Failed to upload audio. Please try again.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _togglePlay() async {
    final url = widget.audioUrl;
    if (url == null) return;
    if (_isPlaying) {
      await _player.pause();
      if (mounted) setState(() => _isPlaying = false);
    } else {
      await _player.play(UrlSource(url));
      if (mounted) setState(() => _isPlaying = true);
    }
  }

  Future<void> _delete() async {
    final url = widget.audioUrl;
    widget.onChanged(null);
    setState(() => _isPlaying = false);
    if (url == null) return;
    try {
      final fileName = Uri.parse(url).pathSegments.last;
      await Supabase.instance.client.storage.from(kNeoAudioBucket).remove([fileName]);
    } catch (_) {
      // Non-critical — an orphaned storage file isn't worth surfacing.
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    final hasAudio = widget.audioUrl != null;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: hasAudio
            ? [
                GestureDetector(
                  onTap: _togglePlay,
                  child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, size: 20, color: c.foreground),
                ),
                Icon(Icons.graphic_eq, size: 20, color: c.mutedForeground),
                GestureDetector(
                  onTap: _delete,
                  child: Icon(Icons.delete_outline, size: 20, color: c.foreground),
                ),
              ]
            : !_recording
                ? [
                    Text(
                      _uploading ? 'Uploading...' : 'Voice',
                      style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, color: c.mutedForeground),
                    ),
                    if (_uploading)
                      SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: c.mutedForeground),
                      )
                    else
                      _RoundIconButton(
                        icon: Icons.mic_none,
                        color: c.mutedForeground,
                        onTap: _startRecording,
                      ),
                  ]
                : [
                    const Text(
                      'Recording...',
                      style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, color: Color(0xFFB91C1C)),
                    ),
                    _RoundIconButton(
                      icon: Icons.stop_rounded,
                      color: const Color(0xFFB91C1C),
                      background: const Color(0xFFFEE2E2),
                      borderColor: const Color(0xFFFCA5A5),
                      pulsing: true,
                      onTap: _stopRecording,
                    ),
                  ],
      ),
    );
  }
}

// Matches the web button's `rounded-2xl h-12 w-12` — a rounded square, not
// a circle — with an optional pulsing background for the recording state.
class _RoundIconButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final Color? background;
  final Color? borderColor;
  final bool pulsing;
  final VoidCallback onTap;

  const _RoundIconButton({
    required this.icon,
    required this.color,
    this.background,
    this.borderColor,
    this.pulsing = false,
    required this.onTap,
  });

  @override
  State<_RoundIconButton> createState() => _RoundIconButtonState();
}

class _RoundIconButtonState extends State<_RoundIconButton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final button = Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.background ?? Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: widget.borderColor != null ? Border.all(color: widget.borderColor!) : null,
      ),
      child: Icon(widget.icon, size: 20, color: widget.color),
    );

    return GestureDetector(
      onTap: widget.onTap,
      child: widget.pulsing
          ? FadeTransition(opacity: Tween(begin: 0.5, end: 1.0).animate(_controller), child: button)
          : button,
    );
  }
}
