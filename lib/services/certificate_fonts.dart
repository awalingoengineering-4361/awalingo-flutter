import 'package:bidi/bidi.dart' as bidi;

final certificateArabicPattern = RegExp(
  r'[\u0600-\u06ff\u0750-\u077f\u08a0-\u08ff\ufb50-\ufdff\ufe70-\ufeff]',
);
final _arabicRuns = RegExp(
  r'[\u0600-\u06ff\u0750-\u077f\u08a0-\u08ff]+(?: [\u0600-\u06ff\u0750-\u077f\u08a0-\u08ff]+)*',
);

class UnsupportedCertificateCharacters extends FormatException {
  const UnsupportedCertificateCharacters()
    : super(
        'This certificate cannot render some characters. Please check the name and language.',
      );
}

List<String> requiredCertificateFallbackAssets(String text) => [
  if (certificateArabicPattern.hasMatch(text))
    'assets/certificate/Amiri-Regular.ttf',
  if (RegExp(r'[\u1200-\u139f\u2d80-\u2ddf\uab00-\uab2f]').hasMatch(text))
    'assets/certificate/NotoSansEthiopic-Regular.ttf',
  if (RegExp(r'[\u2e80-\u9fff\uac00-\ud7af\uf900-\ufaff]').hasMatch(text))
    'assets/certificate/NotoSansCJK-Regular.ttf',
];

/// The surrounding certificate is LTR; shape and reorder only connected Arabic
/// runs, leaving Latin, CJK and Ethiopic positions in the mixed name intact.
String certificatePdfArabic(String text) => text.replaceAllMapped(
  _arabicRuns,
  (match) => String.fromCharCodes(bidi.logicalToVisual(match.group(0)!)),
);
