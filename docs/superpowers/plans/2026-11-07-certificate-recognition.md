# Certificate Recognition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Match the supplied Figma certificate in Flutter and Next.js previews and existing exports.

**Architecture:** Each app gets a reusable certificate preview component and an updated PDF renderer using the same local artwork, fonts, layout measurements and dynamic wording. Keep the existing export actions; Flutter's PNG continues to rasterize the generated PDF.

**Tech Stack:** Flutter/Dart, flutter_svg, pdf, printing, share_plus; Next.js/React/TypeScript, Tailwind, jsPDF, Vitest.

**Spec:** ../specs/2026-11-07-certificate-recognition-design.md

## Global Constraints

- Figma file 6g5L1KK1aGkla75XEM5syK, node 2481:3238 is authoritative.
- Preserve real recipient, language and completed stage; no sample data in production.
- Keep existing perfect-score eligibility, sharing caption and export filenames.
- No runtime references to expiring Figma asset URLs; no screenshot as implementation artwork.
- Keep certificate white in both app themes; preserve its landscape proportions.
- Work on codex/certificate-recognition in both isolated worktrees.

## Review Focus

- Long recipient and language names must remain readable without clipping or ellipsis.
- Yoruba diacritics and other non-ASCII input must survive both preview and export.
- All six completed stages must appear with the correct CEFR label exactly once.
- Repeated exports after data changes must use current details and allow retry after failure.
- Artwork must keep the source proportions, layering and clipping at small display widths.

### Task 1: Flutter certificate

**Files:**
- Create: assets/certificate/ artwork and font assets with licenses.
- Modify: pubspec.yaml asset/font declarations.
- Create: lib/widgets/awaquiz_certificate_card.dart.
- Modify: lib/services/awaquiz_certificate.dart and certificate_export_service.dart.
- Modify: lib/features/awaquiz/awaquiz_progression.dart certificate stage formatting.
- Modify: lib/screens/main/awaquiz_screen.dart to use the extracted preview.
- Tests: certificate export/actions tests, progression tests and a certificate preview fixture.
- Create: integration_test/certificate_design_test.dart and corresponding driver if needed for artifact capture.

**Interfaces:**
- Preserve CertificateDetails(recipientName, language, levelLabel) and export/share methods.
- Preview consumes the same three fields; completed-stage formatter supplies the full CEFR label.
- Retain buildAwaQuizCertificatePdf named inputs, extending internal asset/font loading as needed.

- [x] Add failing coverage for new recognition wording, all six stage labels, long/accented input and stale export details.
- [x] Download exact artwork using Figma-provided asset URLs; acquire matching local fonts and licenses. Verify dimensions and non-empty files.
- [x] Implement the preview and PDF layout from the spec, replacing obsolete ribbon/seal painters.
- [x] Keep text measurement and wrapping inside the panel for long values; embed Unicode fonts in PDF output.
- [x] Run focused tests, then scripts/verify-change in the required order.
- [x] Capture the real certificate screen, PDF and shared PNG on a disposable emulator; visually compare artwork/text geometry to Figma, including long/accented fixtures.
- [x] Record validation and commit only the Flutter certificate change.

### Task 2: Next.js certificate

**Files:**
- Create: public/certificate/ artwork and fonts with licenses.
- Create: src/components/awaquiz/AwaQuizCertificate.tsx and local certificate styling/resources as needed.
- Modify: src/app/awaquiz/result/page.tsx.
- Modify: src/lib/awaquiz-certificate.ts; extract async resource loading into a focused helper.
- Tests: src/lib/__tests__/awaquiz-certificate.test.ts and result-page tests; add preview component tests.

**Interfaces:**
- Preview accepts recipientName, language and complete levelLabel.
- Preserve synchronous createAwaQuizCertificate(options) -> jsPDF; extend its options with prepared artwork/font resources.
- A cached async resource loader prepares those inputs for the download action, evicting failed loads so retry works.

- [ ] Add failing coverage for recognition copy, Unicode/long values, stage wording, changed details on repeated download, and retry after resource failure.
- [ ] Install the same exact local artwork/fonts as Flutter and implement the reusable preview with responsive scaling.
- [ ] Update jsPDF composition, font embedding and download resource loading. Surface retryable failure in the result page.
- [ ] Run targeted Vitest tests, npm run lint:sonar, npm run type-check and production build; investigate touched-file findings.
- [ ] Render the actual result component in a browser with deterministic certificate fixtures at desktop/mobile widths and both themes. Download and render the PDF to compare with Figma and Flutter's exported artifacts.
- [ ] Record validation and commit only the Next.js certificate change.

### Final validation

- [ ] One fresh reviewer checks the complete changes across both repositories, focusing on the five cases above.
- [ ] Resolve actionable findings and rerun the affected checks.
- [ ] Confirm both primary checkouts' unrelated changes remain preserved.
- [ ] Report artifacts, checks, limitations and both branches; open PRs when requested.
