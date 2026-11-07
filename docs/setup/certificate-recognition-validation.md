# Certificate recognition validation — 2026-11-07

Source: Figma file `6g5L1KK1aGkla75XEM5syK`, certificate `2481:3238`.

The result preview and PDF use the supplied recognition layout, local artwork
and fonts, actual recipient/language, and the completed stage with CEFR wording.
The existing PNG share caption, retry behavior and perfect-score eligibility
remain covered by the certificate action tests.

Validation completed:

- `scripts/verify-change`: 168 tests passed, one existing skip; 33 informational
  analysis findings; Android debug build/install/launch passed on API 34.
- `flutter drive --driver=test_driver/certificate_design.dart
  --target=integration_test/certificate_design_test.dart -d emulator-5580`:
  native fixture and teardown passed. Actual PDF and rasterized PNG exports were
  generated for the design sample and a long accented recipient/language.
- Inspected the launch screenshot/UI hierarchy, both preview captures and actual
  exported image. `pdftotext -layout` confirmed accented recipient/language text
  survives PDF export, including Ọ, ẹ, ṣ and combining tone marks.
- Native artifacts: `build/verification/certificate/` (preview screenshots,
  `certificate-0.pdf/png`, `certificate-1.pdf/png`).

The first emulator attempts were limited by host/device storage. The successful
run used a clean disposable emulator after sufficient host space was available;
no existing emulator app data was wiped.

## Rendering choice

`assets/certificate/artwork.svg` composes the original unchanged Figma vector
assets with their measured transforms, pattern and panel geometry.
`artwork.png` is its 3× rasterization, shared with Next.js so the PDF libraries
render all decorations consistently. Text stays dynamic and remains vector in
PDF output. Illustration detail is bounded by this 3× artwork rather than
remaining infinitely scalable.
