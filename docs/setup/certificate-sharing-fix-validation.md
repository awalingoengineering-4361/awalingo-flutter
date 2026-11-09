# Certificate sharing feedback — 2026-11-08

The Flutter certificate now has one **Share Certificate** action and a separate
**Copy message** action. The previous **Download Certificate** button also
opened a native share sheet for a PDF; it has been removed, along with that
unused PDF-sharing service method. PDF creation remains the source for PNG
rasterization. The Next.js certificate download is unchanged.

The share payload is one named `image/png` attachment without accompanying
text. The existing caption remains available through Copy message. This avoids
the documented image-plus-text compatibility problem in some receiving apps:
https://pub.dev/packages/share_plus#sharing-images--text

A particular failing destination was not identified, so this is a fix for the
reproduced duplicate action and known mixed-payload incompatibility, rather than
a claim that every third-party receiving app has been tested.

## Verification

- Two regressions failed before implementation: the extra export control and
  a text field in the image payload. All 12 focused tests subsequently passed.
- `scripts/verify-change`: 189 tests passed, one existing skip; static analysis
  has 33 existing informational findings; Android build/install/launch passed.
  Launch screenshot and UI hierarchy were inspected.
- Android integration fixture: 12 checks plus teardown passed. It generates and
  decodes real certificate PNGs twice, checks image-only payloads and nonzero
  anchor bounds, and exercises retry, double-tap protection, current details,
  cancellation, navigation away and caption copy.
- Real Android native chooser: opened and dismissed twice; both image previews
  were captured and inspected, with the button usable again after cancellation.
- iPhone simulator fixture: the same 12 checks plus teardown passed, including
  real PNG generation and repeat payload validation. This first run used a
  simulator-only deployment override because Xcode rejects the current iOS 13
  target. It verifies image generation and payloads, not the iOS native chooser.
- The emulator has no WhatsApp, Facebook or Instagram installation; those app
  integrations are unverified. No recipients were selected and no messages sent.

Artifacts are retained in the local `certificate-sharing-fix` visualization
folder, including action and native share-sheet screenshots and test logs.
