import 'package:flutter/material.dart';
import '../services/certificate_design.dart';
import '../services/certificate_fonts.dart';

/// A fixed print composition scaled as a whole to fit the available width.
class AwaQuizCertificateCard extends StatelessWidget {
  final String recipientName;
  final String language;
  final String levelLabel;

  const AwaQuizCertificateCard({
    super.key,
    required this.recipientName,
    required this.language,
    required this.levelLabel,
  });

  @override
  Widget build(BuildContext context) {
    Widget line(
      String text,
      double size,
      String family, {
      Color color = const Color(0xFF020202),
      FontWeight weight = FontWeight.w400,
      FontStyle style = FontStyle.normal,
      double spacing = 0,
      double height = 1.25,
    }) => Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: family,
        fontFamilyFallback: const [
          'NotoSans',
          'CertificateArabic',
          'CertificateEthiopic',
          'CertificateCJK',
        ],
        fontSize: size,
        fontWeight: weight,
        fontStyle: style,
        color: color,
        height: height,
        letterSpacing: certificateArabicPattern.hasMatch(text) ? 0 : spacing,
        decoration: TextDecoration.none,
      ),
    );
    return Semantics(
      label:
          'Awalingo Certificate of Recognition for $recipientName, $language, $levelLabel',
      child: AspectRatio(
        aspectRatio: certificateWidth / certificateHeight,
        child: FittedBox(
          fit: BoxFit.contain,
          child: MediaQuery.withNoTextScaling(
            child: SizedBox(
              width: certificateWidth,
              height: certificateHeight,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/certificate/artwork.png',
                      fit: BoxFit.fill,
                      excludeFromSemantics: true,
                    ),
                  ),
                  Positioned(
                    left: 90,
                    top: 133,
                    width: 671,
                    height: 63.7435,
                    child: line(
                      certificateHeading,
                      48,
                      'Parkinsans',
                      color: const Color(0xFF2B2621),
                      height: 63.7435 / 48,
                    ),
                  ),
                  Positioned(
                    left: 90,
                    top: 199.74414,
                    width: 671,
                    height: 28,
                    child: line(
                      certificateSubtitle,
                      22.329,
                      'CertificateInter',
                      color: const Color(0xFFB1752E),
                    ),
                  ),
                  Positioned(
                    left: 90,
                    top: 234.74414,
                    width: 671,
                    height: 20,
                    child: line(
                      certificateIntroduction,
                      15.683,
                      'CertificateMontserrat',
                      weight: FontWeight.w500,
                      spacing: 0.1568,
                      height: 19 / 15.683,
                    ),
                  ),
                  Positioned(
                    left: 161,
                    top: 281.74414,
                    width: 529,
                    height: 49,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: line(
                        recipientName,
                        40,
                        'CertificateMontserrat',
                        spacing: 0.4,
                        height: 1.225,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 118,
                    top: 345.72461,
                    width: 615,
                    height: 46,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: 615,
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: const TextStyle(
                              fontFamily: 'CertificateAlbertSans',
                              fontFamilyFallback: [
                                'NotoSans',
                                'CertificateArabic',
                                'CertificateEthiopic',
                                'CertificateCJK',
                              ],
                              fontSize: 18,
                              height: 1.25,
                              color: Color(0xFF020202),
                            ),
                            children: [
                              const TextSpan(text: certificateAchievement),
                              TextSpan(
                                text: language,
                                style: const TextStyle(
                                  color: Color(0xFFBE008B),
                                ),
                              ),
                              const TextSpan(text: ', '),
                              TextSpan(
                                text: '- $levelLabel',
                                style: const TextStyle(
                                  color: Color(0xFFDE9300),
                                ),
                              ),
                              const TextSpan(text: '. $certificateCommitment'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 118,
                    top: 414.72461,
                    width: 615,
                    height: 23,
                    child: line(
                      certificateRespect,
                      18,
                      'CertificateAlbertSans',
                      weight: FontWeight.w600,
                    ),
                  ),
                  Positioned(
                    left: 118,
                    top: 458.72461,
                    width: 615,
                    height: 20,
                    child: line(
                      'Signed:',
                      16,
                      'CertificateAlbertSans',
                      style: FontStyle.italic,
                    ),
                  ),
                  Positioned(
                    left: 118,
                    top: 485.72461,
                    width: 615,
                    height: 23,
                    child: line(
                      'The Ancestors',
                      18,
                      'CertificateAlbertSans',
                      weight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
