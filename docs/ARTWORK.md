# Ocean sunset

The bundled `OceanSunset` image is a static halftone render of **ocean sunset** by **bas3line**, from [ascii.rest](https://ascii.rest/ocean-sunset/).

- Upstream source: <https://github.com/bas3line/ascii/blob/main/src/pieces/ocean-sunset.ts>
- License: MIT, Copyright (c) 2026 bas3line. The complete notice is in `Shared/AsciiRest-LICENSE.txt` and is bundled with the main app and shield extension.
- The upstream source is retained in `scripts/vendor/ascii-rest/ocean-sunset.ts`.
- Regenerate the static image with `python3 scripts/make-ocean-art.py` (Node 22.13+ and Pillow). The script renders the scene at eight seconds using palette-colored dots, without browser or network access.

The native launch screen and initial loading view use the same bundled artwork. The dashboard layers a dark gradient beneath white text. The approved square crop (source coordinates 560,90–1060,590) is used for the Home Screen icon and the blocking screen's image slot. Regenerate both icon assets with `python3 scripts/make-icon.py`. The shield retains its system background: iOS does not expose a full-screen background-image API.
