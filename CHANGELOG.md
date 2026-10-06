# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

First public release.

### Added

- **Userscript** (version 4.3): Copy, Cut, Paste and Delete bar next to the selection, on any web page, for Windows and macOS. Paste works across tabs through one relay slot (8 hours). Three appearances. No network access.
- **macOS app** CopieRapide: the same bar in every app, with file actions in the Finder (Move here, Trash), a 12-text history erased after 24 hours, and screenshots from the menu bar.
- MIT license, `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`.

### Changed

- `macos/construire.sh` signs ad hoc by default (`SIGN_IDENTITY` to use your own certificate), builds for the Mac's own architecture, and installs in `/Applications` only with `--installer`.
- The app's bundle identifier is now `io.github.yanmwisa.copierapide`.
- The userscript gets author, license and homepage headers.

### Removed

- The signing certificate and its restore script, which only made sense on the author's Mac.
- An exclusion for an internal corporate sign-in address in the userscript.
