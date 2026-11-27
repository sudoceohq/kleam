# Kleam

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

Kleam is a free, open-source menubar app for macOS that plays satisfying keyboard (and mouse) sounds as you type. A matching web preview lives in this repo so you can try the sound engine in the browser.

Switch packs are **descriptive sound profiles** made with original synthesis — not official switch products and not third-party recordings.

```bash
python3 macos/scripts/synthesize_switches.py
```

## License

Apache License 2.0. See [LICENSE](LICENSE).
`macos/scripts/import_mit_packs.py` is unused; Kleam does not ship those recordings.

## Disclaimer

Kleam is an independent project and is **not affiliated with, endorsed by, or associated with** Klack, Keychron, Cherry, Gateron, NovelKeys, Everglide, or Flurples.

## Website

The browser preview is published with GitHub Pages: https://sudoceohq.github.io/kleam/

## Releases

[Release Please](https://github.com/googleapis/release-please) opens a pull request on `main` when conventional commits land (`feat`, `fix`, and similar). Merging that pull request tags the version, updates `CHANGELOG.md`, and uploads `Kleam-vX.Y.Z-macos.zip` (arm64, macOS 14+) to the GitHub Release.

## Web preview

Requires Node.js 20+.

```bash
npm install
npm run dev
```

Open the URL Vite prints (usually `http://localhost:5173`). Press keys or use the on-screen keyboard to hear sounds.

```bash
npm run build    # production bundle in dist/
npm run preview  # serve the production build
```

## macOS app

Requires macOS 14+, Xcode Command Line Tools (`swiftc`, `xcrun`).

```bash
bash macos/build.sh
```

That produces `dist/Kleam.app`. Copy it somewhere convenient (for example `~/Applications`) and launch it.

### Accessibility

Kleam listens for key events in other apps via macOS **Accessibility**. On first launch (and after rebuilding/re-signing), grant access:

**System Settings → Privacy & Security → Accessibility → enable Kleam**

If sound only works inside Kleam’s own UI, Accessibility is not granted (or needs to be toggled off and on again after a new build).

## Project layout

| Path | Role |
|------|------|
| `src/` | Web UI + browser audio engine |
| `public/sounds/` | Web sound banks |
| `macos/Kleam/` | Menubar SwiftUI app |
| `macos/build.sh` | Ad-hoc signed app bundle |
