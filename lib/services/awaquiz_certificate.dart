import 'dart:math' as math;
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// Ports createAwaQuizCertificate (neolingo/src/lib/awaquiz-certificate.ts)
// using the pdf package's low-level PdfGraphics canvas, which mirrors
// jsPDF's imperative circle/triangle/text drawing calls closely enough to
// keep this a line-by-line port rather than a re-design.
//
// jsPDF's Y axis runs top-down from the page's top edge; PdfGraphics' Y
// axis runs bottom-up from the page's bottom edge. Every coordinate below
// is ported as `pageHeight - yFromTheTsSource` at the point it's used —
// there's no single global flip, since a blanket Y-flip transform would
// also mirror (upside-down) any text drawn under it.

const _black = PdfColor.fromInt(0x08080A);
const _bodyText = PdfColor.fromInt(0x272320);
const _dotColor = PdfColor.fromInt(0xD7D1C7);
const _gold = PdfColor.fromInt(0xD69718);
const _goldDark = PdfColor.fromInt(0xAE7014);
const _goldLight = PdfColor.fromInt(0xF7C74C);
const _magenta = PdfColor.fromInt(0xC4007E);
const _navy = PdfColor.fromInt(0x141F46);
const _navyDark = PdfColor.fromInt(0x0C142F);
const _navyLight = PdfColor.fromInt(0x23305E);
const _white = PdfColors.white;

// [startX, startYFromTop] and the grid step are taken verbatim from the TS
// source's jsPDF (top-down) coordinates; the flip to bottom-up happens once
// here so every call site can just copy the original numbers.
void _drawDottedAccent(
    PdfGraphics canvas, double pageHeight, double startX, double startYFromTop, int columns, int rows) {
  canvas.setColor(_dotColor);
  final startY = pageHeight - startYFromTop;
  for (var row = 0; row < rows; row++) {
    for (var col = 0; col < columns; col++) {
      canvas.drawEllipse(startX + col * 11, startY - row * 11, 1.25, 1.25);
      canvas.fillPath();
    }
  }
}

void _fillTriangle(PdfGraphics canvas, PdfColor color, PdfPoint a, PdfPoint b, PdfPoint c) {
  canvas.setColor(color);
  canvas.moveTo(a.x, a.y);
  canvas.lineTo(b.x, b.y);
  canvas.lineTo(c.x, c.y);
  canvas.closePath();
  canvas.fillPath();
}

void _drawCornerRibbons(PdfGraphics canvas, double pageWidth, double pageHeight) {
  _drawDottedAccent(canvas, pageHeight, 116, 12, 9, 10);
  _drawDottedAccent(canvas, pageHeight, pageWidth - 210, pageHeight - 146, 9, 10);

  void corner(double size, PdfColor color) {
    // Top-left (TS: (0,0),(size,0),(0,size)) and bottom-right (TS:
    // (pageWidth,pageHeight),(pageWidth-size,pageHeight),(pageWidth,pageHeight-size)),
    // each point flipped individually (y -> pageHeight - y).
    _fillTriangle(canvas, color, PdfPoint(0, pageHeight), PdfPoint(size, pageHeight), PdfPoint(0, pageHeight - size));
    _fillTriangle(canvas, color, PdfPoint(pageWidth, 0), PdfPoint(pageWidth - size, 0), PdfPoint(pageWidth, size));
  }

  corner(205, _navyDark);
  corner(180, _navyLight);
  corner(154, _gold);
  corner(144, _navy);
  corner(105, _navyDark);
}

void _drawLogoPanel(PdfGraphics canvas, double pageWidth, double pageHeight, PdfFont helveticaBold, PdfImage? logo) {
  const panelWidth = 210.0;
  final panelX = (pageWidth - panelWidth) / 2;
  canvas.setColor(_black);
  // TS: roundedRect(panelX, -20, panelWidth, 101, 24, 24) — top edge at
  // jsY=-20, bottom edge at jsY=81; drawRRect's y is its lower edge.
  canvas.drawRRect(panelX, pageHeight - 81, panelWidth, 101, 24, 24);
  canvas.fillPath();

  if (logo == null) {
    const text = 'AWALINGO';
    const size = 23.0;
    final width = helveticaBold.stringMetrics(text).width * size;
    canvas.setColor(_white);
    canvas.drawString(helveticaBold, size, text, (pageWidth - width) / 2, pageHeight - 48);
    return;
  }

  const logoWidth = 146.0;
  final logoHeight = logoWidth / (logo.width / logo.height);
  // TS: addImage(..., y: 16, ...) — top edge at jsY=16.
  canvas.drawImage(logo, (pageWidth - logoWidth) / 2, pageHeight - 16 - logoHeight, logoWidth, logoHeight);
}

double _fitFontSize(PdfFont font, String text, double preferredSize, double minimumSize, double maximumWidth) {
  final measuredWidth = font.stringMetrics(text).width * preferredSize;
  if (measuredWidth <= maximumWidth) return preferredSize;
  final fitted = preferredSize * maximumWidth / measuredWidth;
  return math.max(minimumSize, fitted);
}

class _TextSegment {
  final PdfColor color;
  final String text;
  final double gapAfter;
  const _TextSegment(this.color, this.text, {this.gapAfter = 0});
}

void _drawCenteredSegments(
    PdfGraphics canvas, PdfFont font, double pageWidth, double baselineY, List<_TextSegment> segments) {
  // Narrower than the TS source's 650pt, and forces the shrink-to-fit path
  // rather than relying on it only kicking in past that width: rendering
  // and visually inspecting the actual output showed this line reaching
  // close enough to the bottom-right corner ribbon to risk overlapping it,
  // even though its natural width never exceeded 650pt.
  const maximumWidth = 480.0;
  const preferredSize = 18.0;
  const minimumSize = 13.0;

  double widthAt(double size) => segments.fold(0.0, (w, s) => w + font.stringMetrics(s.text).width * size + s.gapAfter);

  final preferredWidth = widthAt(preferredSize);
  final fittedSize = math.max(minimumSize, math.min(preferredSize, preferredSize * maximumWidth / preferredWidth));

  final totalWidth = widthAt(fittedSize);
  var currentX = (pageWidth - totalWidth) / 2;
  for (final segment in segments) {
    canvas.setColor(segment.color);
    canvas.drawString(font, fittedSize, segment.text, currentX, baselineY);
    currentX += font.stringMetrics(segment.text).width * fittedSize + segment.gapAfter;
  }
}

// centerY is already in PdfGraphics (bottom-up) space; every relative
// offset from it below has its sign flipped relative to the TS source,
// since "down the page" is -Y here but was +Y (jsPDF) there.
void _drawSeal(PdfGraphics canvas, double centerX, double centerY) {
  canvas.setColor(_gold);
  for (var i = 0; i < 24; i++) {
    final angle = (i / 24) * math.pi * 2;
    canvas.drawEllipse(centerX + math.cos(angle) * 34, centerY - math.sin(angle) * 34, 9, 9);
    canvas.fillPath();
  }
  canvas.drawEllipse(centerX, centerY, 35, 35);
  canvas.fillPath();

  canvas.setColor(_goldLight);
  canvas.setLineWidth(2.5);
  canvas.drawEllipse(centerX, centerY, 29, 29);
  canvas.strokePath();

  canvas.setColor(_goldDark);
  canvas.setLineWidth(1.5);
  canvas.drawEllipse(centerX, centerY, 22, 22);
  canvas.strokePath();

  // TS ribbon wings: (cx-15,cy-4),(cx,cy-12),(cx+15,cy-4) and
  // (cx-15,cy-4),(cx,cy+3),(cx+15,cy-4).
  _fillTriangle(canvas, _goldLight, PdfPoint(centerX - 15, centerY + 4), PdfPoint(centerX, centerY + 12),
      PdfPoint(centerX + 15, centerY + 4));
  _fillTriangle(canvas, _goldLight, PdfPoint(centerX - 15, centerY + 4), PdfPoint(centerX, centerY - 3),
      PdfPoint(centerX + 15, centerY + 4));

  // TS: rect(cx-9, cy+2, 18, 5) spans jsY [cy+2, cy+7] (top to bottom);
  // drawRect's y is its lower edge, so that's centerY-7 here.
  canvas.setColor(_goldLight);
  canvas.drawRect(centerX - 9, centerY - 7, 18, 5);
  canvas.fillPath();

  // TS tail: line((cx+15,cy-4) -> (cx+15,cy+9)), dot at (cx+15, cy+11).
  canvas.setColor(_goldLight);
  canvas.setLineWidth(1.2);
  canvas.moveTo(centerX + 15, centerY + 4);
  canvas.lineTo(centerX + 15, centerY - 9);
  canvas.strokePath();
  canvas.drawEllipse(centerX + 15, centerY - 11, 1.5, 1.5);
  canvas.fillPath();
}

Future<Uint8List> buildAwaQuizCertificatePdf({
  required String language,
  required String levelLabel,
  required String recipientName,
  Uint8List? logoBytes,
}) async {
  final doc = pw.Document();
  final pageFormat = PdfPageFormat.a4.landscape;
  final logoProvider = logoBytes != null ? pw.MemoryImage(logoBytes) : null;
  final helveticaFont = pw.Font.helvetica();
  final helveticaBoldFont = pw.Font.helveticaBold();
  final timesItalicFont = pw.Font.timesItalic();

  doc.addPage(pw.Page(
    pageFormat: pageFormat,
    build: (context) {
      final helvetica = helveticaFont.getFont(context);
      final helveticaBold = helveticaBoldFont.getFont(context);
      final timesItalic = timesItalicFont.getFont(context);
      final logo = logoProvider?.buildImage(context);

      return pw.CustomPaint(
        size: PdfPoint(pageFormat.width, pageFormat.height),
        painter: (canvas, size) {
          final pageWidth = size.x;
          final pageHeight = size.y;

          canvas.setColor(_white);
          canvas.drawRect(0, 0, pageWidth, pageHeight);
          canvas.fillPath();

          _drawCornerRibbons(canvas, pageWidth, pageHeight);
          _drawLogoPanel(canvas, pageWidth, pageHeight, helveticaBold, logo);

          canvas.setColor(_bodyText);
          const certText = 'CERTIFICATE';
          final certWidth = helvetica.stringMetrics(certText).width * 48;
          canvas.drawString(helvetica, 48, certText, (pageWidth - certWidth) / 2, pageHeight - 176);

          canvas.setColor(_goldDark);
          const ofText = 'OF ACHIEVEMENT';
          final ofWidth = helvetica.stringMetrics(ofText).width * 21;
          canvas.drawString(helvetica, 21, ofText, (pageWidth - ofWidth) / 2, pageHeight - 210);

          canvas.setColor(_black);
          const certifyText = 'This is to certify that';
          final certifyWidth = helvetica.stringMetrics(certifyText).width * 17;
          canvas.drawString(helvetica, 17, certifyText, (pageWidth - certifyWidth) / 2, pageHeight - 255);

          final nameSize = _fitFontSize(helvetica, recipientName, 39, 24, 650);
          final nameWidth = helvetica.stringMetrics(recipientName).width * nameSize;
          canvas.drawString(helvetica, nameSize, recipientName, (pageWidth - nameWidth) / 2, pageHeight - 331);

          canvas.setColor(_goldDark);
          canvas.setLineWidth(1.2);
          canvas.moveTo(160, pageHeight - 346);
          canvas.lineTo(pageWidth - 160, pageHeight - 346);
          canvas.strokePath();

          _drawCenteredSegments(canvas, helvetica, pageWidth, pageHeight - 389, [
            _TextSegment(_black, 'Has aced the Awalingo Language Quiz for '),
            _TextSegment(_magenta, '$language,', gapAfter: 3),
            _TextSegment(_gold, levelLabel),
            _TextSegment(_black, ' Level.'),
          ]);

          canvas.setColor(_black);
          const respectText = 'Please put some respect on their name!';
          final respectWidth = helvetica.stringMetrics(respectText).width * 18;
          canvas.drawString(helvetica, 18, respectText, (pageWidth - respectWidth) / 2, pageHeight - 425);

          _drawSeal(canvas, 103, pageHeight - 508);

          canvas.setColor(_black);
          const signedText = 'Signed:';
          final signedWidth = timesItalic.stringMetrics(signedText).width * 18;
          canvas.drawString(timesItalic, 18, signedText, (pageWidth - signedWidth) / 2, pageHeight - 493);

          const ancestorsText = 'The Ancestors';
          final ancestorsWidth = helveticaBold.stringMetrics(ancestorsText).width * 20;
          canvas.drawString(helveticaBold, 20, ancestorsText, (pageWidth - ancestorsWidth) / 2, pageHeight - 526);
        },
      );
    },
  ));

  return doc.save();
}
