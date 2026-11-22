# AwaQuiz certificate of recognition

Source: https://www.figma.com/design/6g5L1KK1aGkla75XEM5syK/Awalingo?node-id=2481-3238

Apply the supplied design to Flutter and Next.js. The Figma design is the visual
specification; the recipient, language and completed stage remain live data.

## Layout and assets

Use the outer 841 × 595 landscape canvas, clipping the original
842.108 × 600.168 inner content coordinates at its edges. Keep the
certificate light-themed in either app theme. The white content panel is at
(90,119), 671 × 402.724, with a 16px corner radius and 15% black 1px border.
The black logo panel is centered at x=329, y=-47, 183.242 × 121.025.

Download and retain the actual Figma assets: balloons, smile, trophy, confetti,
purple flower, pencil body and icing, medal, wordmark and name underline. Do not
replace illustrations with emoji or icons. Reproduce the background PATTERN fill
using source node 2481:3002 at 3% opacity, horizontal hexagonal tiling and Figma's
spacing (0.41 on both axes). Record actual asset geometry and any conversion
needed for the PDF libraries; do not use the reference screenshot as artwork.

Use Parkinsans Regular for the title, Inter Regular for the subtitle,
Montserrat Regular/Medium for recipient/introduction, and Albert Sans
Regular/Italic/Medium/Semibold for body and signature. Bundle missing fonts
locally with their licenses, including the glyph coverage needed by language
names. Reuse existing exact font assets where available.

## Copy and data

- CERTIFICATE / OF RECOGNITION
- This is to recognize that
- Dynamic recipient name, fitted without ellipsis or clipping.
- For acing the Awalingo Language Quiz for {language}, - {stageLabel}.
  demonstrating commitment to learning the mothertongue.
- Please put some respect on their name!
- Signed: / The Ancestors

Use the supplied stage label as complete wording, e.g. JJC (A1 Level); never
append another “Level”. Flutter currently uses generic difficulty text; bring
its certificate label into parity with the web's existing six-stage CEFR map.
The final respect sentence removes the duplicated period after the exclamation
mark in Figma; this is an implementation recommendation for approval.

## Boundaries

Retain perfect-score eligibility and existing result navigation. Keep Flutter's
PNG share plus existing caption and PDF export, and Next.js's PDF download.
Do not add social integrations, database changes, or quiz progression changes.
Use isolated task branches in both repositories; preserve primary-checkout edits.

## Validation

Compare the actual previews and generated PDF/PNG artifacts with Figma using the
sample name, accented language names, long names and every stage. Check narrow
mobile widths and dark app themes. Repeat export actions with changed certificate
data to catch stale recipient/language/stage state. Export failures must remain
retryable. Run each repository's required checks before completion.

## Final review corrections

Match the source pattern orientation and outer-frame crop. Preserve Arabic,
Ethiopic and BMP CJK names with licensed local script fonts; load these PDF
fonts only when required. Unsupported glyphs must produce a clear export error
instead of silently disappearing. Use grapheme-aware segmentation even when
Intl.Segmenter is unavailable in an otherwise supported browser.
