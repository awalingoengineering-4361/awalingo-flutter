import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'awaquiz_certificate.dart';

class CertificateDetails {
  final String recipientName;
  final String language;
  final String levelLabel;

  const CertificateDetails({
    required this.recipientName,
    required this.language,
    required this.levelLabel,
  });

  String get message =>
      'I have just passed Awalingo Language Quiz for $language. Check out my certificate.';

  String filename(String extension) {
    final name = recipientName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return '${name.isEmpty ? 'awalingo' : name}-awaquiz-certificate.$extension';
  }

  @override
  bool operator ==(Object other) =>
      other is CertificateDetails &&
      recipientName == other.recipientName &&
      language == other.language &&
      levelLabel == other.levelLabel;

  @override
  int get hashCode => Object.hash(recipientName, language, levelLabel);
}

/// Exports the existing certificate design without changing quiz state.
class CertificateExportService {
  final Future<ShareResult> Function(ShareParams) _share;

  CertificateExportService({Future<ShareResult> Function(ShareParams)? share})
    : _share = share ?? SharePlus.instance.share;

  Future<Uint8List> createPdf(CertificateDetails details) async {
    Uint8List? logoBytes;
    try {
      final logo = await rootBundle.load(
        'assets/branding/logo-wordmark-dark.png',
      );
      logoBytes = logo.buffer.asUint8List();
    } catch (_) {
      // The existing certificate renderer also supports a text-only logo.
    }
    return buildAwaQuizCertificatePdf(
      language: details.language,
      levelLabel: details.levelLabel,
      recipientName: details.recipientName,
      logoBytes: logoBytes,
    );
  }

  Future<Uint8List> createImage(CertificateDetails details) async {
    final pdf = await createPdf(details);
    final page = await Printing.raster(pdf, pages: [0], dpi: 144).first;
    return page.toPng();
  }

  Future<void> shareImage(
    CertificateDetails details,
    Uint8List bytes,
    Rect bounds,
  ) async {
    await _share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'image/png')],
        fileNameOverrides: [details.filename('png')],
        text: details.message,
        sharePositionOrigin: bounds,
      ),
    );
    // A chooser result cannot prove that a receiving app sent the content.
  }

  Future<void> sharePdf(
    CertificateDetails details,
    Uint8List bytes,
    Rect bounds,
  ) async {
    await Printing.sharePdf(
      bytes: bytes,
      filename: details.filename('pdf'),
      bounds: bounds,
    );
  }
}
