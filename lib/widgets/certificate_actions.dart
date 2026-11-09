import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/certificate_export_service.dart';
import '../services/certificate_fonts.dart';
import '../theme/app_theme.dart';

class CertificateActions extends StatefulWidget {
  final CertificateDetails certificate;
  final CertificateExportService? exporter;

  const CertificateActions({
    super.key,
    required this.certificate,
    this.exporter,
  });

  @override
  State<CertificateActions> createState() => _CertificateActionsState();
}

class _CertificateActionsState extends State<CertificateActions> {
  final _imageKey = GlobalKey();
  late final _defaultExporter = CertificateExportService();
  bool _busy = false;

  CertificateExportService get _exporter => widget.exporter ?? _defaultExporter;
  bool _isCurrent(CertificateDetails details) =>
      mounted &&
      widget.certificate == details &&
      ModalRoute.of(context)?.isCurrent != false;

  Future<void> _share() async {
    if (_busy) return;
    final details = widget.certificate;
    final exporter = _exporter;
    setState(() => _busy = true);
    try {
      final bytes = await exporter.createImage(details);
      if (!_isCurrent(details)) return;
      final box = _imageKey.currentContext!.findRenderObject() as RenderBox;
      final bounds = box.localToGlobal(Offset.zero) & box.size;
      await exporter.shareImage(details, bytes, bounds);
    } catch (error) {
      final String message;
      if (error is UnsupportedCertificateCharacters) {
        message = error.message;
      } else {
        message = 'Unable to share certificate. Please try again.';
      }
      if (mounted && _isCurrent(details)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyMessage() async {
    final details = widget.certificate;
    await Clipboard.setData(ClipboardData(text: details.message));
    if (!mounted) return;
    if (_isCurrent(details)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Message copied.')));
    }
  }

  Widget _icon() => _busy
      ? const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : const Icon(Icons.share_outlined, size: 16);

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    final textStyle = const TextStyle(
      fontFamily: 'Metropolis',
      fontWeight: FontWeight.w600,
      fontSize: 14,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton.icon(
          key: _imageKey,
          onPressed: _busy ? null : _share,
          icon: _icon(),
          label: Text(_busy ? 'Preparing...' : 'Share Certificate'),
          style: ElevatedButton.styleFrom(
            backgroundColor: c.primary,
            foregroundColor: c.primaryForeground,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: const StadiumBorder(),
            elevation: 0,
            textStyle: textStyle,
          ),
        ),
        TextButton.icon(
          onPressed: _copyMessage,
          icon: const Icon(Icons.copy_outlined, size: 16),
          label: const Text('Copy message'),
        ),
      ],
    );
  }
}
