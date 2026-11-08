# Certificate artwork

Figma: https://www.figma.com/design/6g5L1KK1aGkla75XEM5syK/Awalingo?node-id=2481-3238

SVG files retain the original vector assets, unchanged. `artwork.svg` places
those assets using the original Figma transforms, background pattern at 3% opacity
and original card/logo panels. Figma PNG exports were discarded because they
included an opaque background. `artwork.png` rasterizes that composition
at 3× for consistent rendering by Flutter, browsers and PDF libraries. No
certificate screenshot or sample text is embedded in the artwork.

Nodes: balloons 2481:3240; smile 2481:3300; trophy/confetti 2482:3430; flower
2481:3351; pencil 2481:3352; medal 2481:3372; wordmark 2481:3402; pattern
2481:3002. The underline follows 2481:3294. The outer frame is 841 × 595; the original inner content coordinates
remain 842.108093 × 600.168274 and are clipped by that frame. Pattern image
instances are reflected horizontally to match Figma’s pattern orientation. Original asset roots are unchanged.

Montserrat, Albert Sans and Inter fonts are static instances of Google Fonts'
official variable TTFs (weights 400/500/600 as named), with original OFL licenses.
Parkinsans reuses the existing application font.

Script fallbacks: Amiri Regular (Arabic), Noto Sans Ethiopic Regular
(static weight 400, width 100), and Noto Sans CJK SC Regular (static weight
400, BMP subset retaining required layout glyphs), from the official Google
Fonts/notofonts repositories. Original OFL licenses accompany each file.
The CJK font adds approximately 19 MB to the native assets; web PDF loading is
on demand. Characters outside the bundled coverage produce an explicit error
rather than an incomplete certificate.
