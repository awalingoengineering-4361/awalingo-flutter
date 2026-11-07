import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'certificate_design.dart';

Future<Uint8List> buildAwaQuizCertificatePdf({
  required String language,
  required String levelLabel,
  required String recipientName,
  Uint8List? logoBytes,
}) async {
  // The Figma wordmark is part of the local artwork; logoBytes is retained for
  // compatibility with existing callers of the certificate builder.
  Future<pw.Font> font(String path) async =>
      pw.Font.ttf(await rootBundle.load(path));
  final title = await font('assets/fonts/Parkinsans-Regular.ttf');
  final subtitle = await font('assets/certificate/Inter-Regular.ttf');
  final name = await font('assets/certificate/Montserrat-Regular.ttf');
  final introduction = await font('assets/certificate/Montserrat-Medium.ttf');
  final body = await font('assets/certificate/AlbertSans-Regular.ttf');
  final medium = await font('assets/certificate/AlbertSans-Medium.ttf');
  final semibold = await font('assets/certificate/AlbertSans-SemiBold.ttf');
  final italic = await font('assets/certificate/AlbertSans-Italic.ttf');
  final fallback = await font('assets/fonts/NotoSans-Regular.ttf');
  final artwork = await rootBundle.load('assets/certificate/artwork.png');
  final image = pw.MemoryImage(artwork.buffer.asUint8List());
  final doc = pw.Document();
  pw.Widget line(
    String text,
    pw.Font face,
    double size, {
    PdfColor color = const PdfColor.fromInt(0x020202),
  }) => pw.Text(
    text,
    textAlign: pw.TextAlign.center,
    style: pw.TextStyle(
      font: face,
      fontFallback: [fallback],
      fontSize: size,
      color: color,
    ),
  );
  pw.Widget box(
    double x,
    double y,
    double width,
    double height,
    pw.Widget child,
  ) => pw.Positioned(
    left: x,
    top: y,
    child: pw.SizedBox(
      width: width,
      height: height,
      child: pw.Align(alignment: pw.Alignment.topCenter, child: child),
    ),
  );
  doc.addPage(
    pw.Page(
      pageFormat: const PdfPageFormat(certificateWidth, certificateHeight),
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Stack(
        children: [
          pw.Positioned.fill(child: pw.Image(image, fit: pw.BoxFit.fill)),
          box(
            90,
            133,
            671,
            63.7435,
            line(
              certificateHeading,
              title,
              48,
              color: const PdfColor.fromInt(0x2B2621),
            ),
          ),
          box(
            90,
            199.74414,
            671,
            28,
            line(
              certificateSubtitle,
              subtitle,
              22.329,
              color: const PdfColor.fromInt(0xB1752E),
            ),
          ),
          box(
            90,
            234.74414,
            671,
            20,
            line(certificateIntroduction, introduction, 15.683),
          ),
          box(
            161,
            281.74414,
            529,
            49,
            pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              child: line(recipientName, name, 40),
            ),
          ),
          box(
            118,
            345.72461,
            615,
            46,
            pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              alignment: pw.Alignment.topCenter,
              child: pw.SizedBox(
                width: 615,
                child: pw.RichText(
                  textAlign: pw.TextAlign.center,
                  text: pw.TextSpan(
                    style: pw.TextStyle(
                      font: body,
                      fontFallback: [fallback],
                      fontSize: 18,
                      color: const PdfColor.fromInt(0x020202),
                    ),
                    children: [
                      const pw.TextSpan(text: certificateAchievement),
                      pw.TextSpan(
                        text: language,
                        style: const pw.TextStyle(
                          color: PdfColor.fromInt(0xBE008B),
                        ),
                      ),
                      const pw.TextSpan(text: ', '),
                      pw.TextSpan(
                        text: '- $levelLabel',
                        style: const pw.TextStyle(
                          color: PdfColor.fromInt(0xDE9300),
                        ),
                      ),
                      const pw.TextSpan(text: '. $certificateCommitment'),
                    ],
                  ),
                ),
              ),
            ),
          ),
          box(118, 414.72461, 615, 23, line(certificateRespect, semibold, 18)),
          box(118, 458.72461, 615, 20, line('Signed:', italic, 16)),
          box(118, 485.72461, 615, 23, line('The Ancestors', medium, 18)),
        ],
      ),
    ),
  );
  return doc.save();
}
