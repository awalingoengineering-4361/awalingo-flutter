# Certificate recognition validation — 2026-11-08

Source: Figma file `6g5L1KK1aGkla75XEM5syK`, certificate `2481:3238`.

The result preview and PDF use the supplied recognition layout, local artwork
and fonts, actual recipient/language, and the completed stage with CEFR wording.
The existing PNG share caption, retry behavior and perfect-score eligibility
remain covered by the certificate action tests.

Validation completed:

- `scripts/verify-change`: 171 tests passed, one existing skip; 33 informational
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

## Final review and regression checks

One fresh reviewer checked both branches. All four findings were addressed in
one fix pass: missing non-Latin PDF glyphs, absent Intl.Segmenter on older
browsers, mirrored pattern instances and incorrect outer-frame clipping.
No findings were deferred.

Real preview and PDF/PNG fixtures include `Amina أمينة 李明 አማርኛ` and
`العربية 中文`; visually inspected exports preserve connected Arabic forms,
Chinese and Ethiopic glyphs. Unsupported glyphs now show a clear export error.
The browser fixtures cover sample, narrow/dark long accented text, mixed
scripts and Intl.Segmenter disabled, with actual downloads and no page errors.
The web suite passed 988 tests (10 existing skips); lint has 170 existing
warnings and no errors, type-check and production build passed. Native
verification passed 171 tests (one existing skip), analysis, build, installation
and launch; the certificate integration fixture and teardown also passed.

The authoritative outer canvas is 841 × 595. Original inner coordinates are
clipped at that frame; pattern instances match Figma’s orientation. Local
Arabic, Ethiopic and BMP CJK fonts provide tested script coverage. Web PDF
resources load script fonts only when needed; the CJK asset adds approximately
19 MB to native bundles. Unsupported scripts/characters remain an explicit
export error, rather than a claim of universal Unicode support.

Review decisions: static decorations use shared 3× artwork (limits extreme-zoom
illustration detail); pre-existing web review-label/complexity warnings remain
(to avoid unrelated quiz changes); outer-frame and pattern corrections are
required Figma fidelity; additional script fonts trade bundle size for preserved
names, with explicit errors outside covered scripts. No deferred findings.
