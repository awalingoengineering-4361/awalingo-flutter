import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/certificate_export_service.dart';
import '../theme/app_theme.dart';

enum _ExportAction { image, pdf }

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
  final _pdfKey = GlobalKey();
  late final _defaultExporter = CertificateExportService();
  _ExportAction? _busy;

  CertificateExportService get _exporter => widget.exporter ?? _defaultExporter;
  bool _isCurrent(CertificateDetails details) =>
      mounted &&
      widget.certificate == details &&
      ModalRoute.of(context)?.isCurrent != false;

  Future<void> _export(_ExportAction action) async {
    if (_busy != null) return;
    final details = widget.certificate;
    final exporter = _exporter;
    setState(() => _busy = action);
    try {
      final bytes = action == _ExportAction.image
          ? await exporter.createImage(details)
          : await exporter.createPdf(details);
      if (!_isCurrent(details)) return;
      final key = action == _ExportAction.image ? _imageKey : _pdfKey;
      final box = key.currentContext!.findRenderObject() as RenderBox;
      final bounds = box.localToGlobal(Offset.zero) & box.size;
      if (action == _ExportAction.image) {
        await exporter.shareImage(details, bytes, bounds);
      } else {
        await exporter.sharePdf(details, bytes, bounds);
      }
    } catch (_) {
      if (mounted && _isCurrent(details)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == _ExportAction.image
                  ? 'Unable to share certificate. Please try again.'
                  : 'Failed to generate certificate. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
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

  Widget _icon(_ExportAction action, IconData icon) => _busy == action
      ? const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Icon(icon, size: 16);

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
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            ElevatedButton.icon(
              key: _imageKey,
              onPressed: _busy == null
                  ? () => _export(_ExportAction.image)
                  : null,
              icon: _icon(_ExportAction.image, Icons.share_outlined),
              label: Text(
                _busy == _ExportAction.image
                    ? 'Preparing...'
                    : 'Share Certificate',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.primary,
                foregroundColor: c.primaryForeground,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: const StadiumBorder(),
                elevation: 0,
                textStyle: textStyle,
              ),
            ),
            OutlinedButton.icon(
              key: _pdfKey,
              onPressed: _busy == null
                  ? () => _export(_ExportAction.pdf)
                  : null,
              icon: _icon(_ExportAction.pdf, Icons.download_rounded),
              label: Text(
                _busy == _ExportAction.pdf
                    ? 'Preparing...'
                    : 'Download Certificate',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: const StadiumBorder(),
                textStyle: textStyle,
              ),
            ),
          ],
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
