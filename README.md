# Copy Paste Helper

**Copy, cut, paste and delete with the mouse, from a small bar that follows your selection.**

Select a word, a sentence or a file: a bar appears next to the cursor with **Copy · Cut · Paste · Delete**. No keyboard shortcut to remember, no menu to open.

This repository has two parts, for different needs:

| | Where it works | Platforms | Folder |
| --- | --- | --- | --- |
| **Userscript** | Web pages, in your browser | **Windows and macOS** (Chrome, Edge, Firefox… any browser with a userscript manager) | [`userscript/`](userscript) |
| **CopieRapide** (native app) | Every app: text anywhere, and files in the Finder | **macOS 13+** | [`macos/`](macos) |

There is **no native Windows app**. On Windows, the userscript is the way to use it, and only inside the browser. A native Windows version would be a welcome contribution.

<!-- TODO before publishing: add a short GIF of the bar in action in docs/images/ and show it here. -->

## Userscript (Windows and macOS)

1. Install a userscript manager: [Tampermonkey](https://www.tampermonkey.net/) or [Violentmonkey](https://violentmonkey.github.io/).
2. Open [`copy-paste-helper.user.js`](https://raw.githubusercontent.com/yanmwisa/copy-paste-helper/main/userscript/copy-paste-helper.user.js). Your manager offers to install it.
3. Reload a page, select some text, and the bar appears.

It uses **⌘** on macOS and **Ctrl** on Windows for the underlying shortcuts.

- **Across tabs.** Paste works from one tab to the next. A web script cannot read the system clipboard reliably, so the script keeps **one** hidden slot: the last text you copied with the bar. It is overwritten on every copy and expires after 8 hours.
- **Nothing on disk, if you prefer.** Set `PARTAGE_ENTRE_ONGLETS` to `false` at the top of the script: nothing is stored, and Paste no longer follows across tabs.
- **Sign-in pages are left alone.** The script is excluded from addresses containing `signin`, `login`, `logon`, `sso`, `auth` or `password`, and password fields are never treated as editable fields (no Cut or Paste there).
- **No network.** The script makes no request: no `fetch`, no XHR, no `@connect`. Its only permissions are `GM_getValue`, `GM_setValue` and `GM_deleteValue`, for the relay slot and the appearance setting.
- Three appearances (plain by default, colour, compact), changed from the arrow next to Paste.

## CopieRapide (macOS)

A native, dependency-free app written in Swift. It lives in the menu bar and has no window.

- **On text**: select a word, a sentence or a spreadsheet cell, in any app. Copy, cut, delete, paste. In web apps where macOS does not expose the selection, it asks the app to copy by itself.
- **On files, folders and photos**: select them in the Finder or on the Desktop and the bar offers the same gestures. The Finder has no "cut", so **Cut** copies and **Move here** moves, which is the native gesture. **Delete** moves to the Trash, so ⌘Z still undoes it.
- **History**: the last 12 copied texts, erased automatically after 24 hours. Set `HISTORIQUE_ACTIF` to `false` in `main.swift` to keep none.
- **Screenshots**: area, full screen or window, from the menu bar. The image goes where your Mac's screenshots usually go, and to the clipboard.
- Three appearances: plain (default), full colour, compact.

### Build and run

You need macOS 13 or later and the Xcode Command Line Tools (`xcode-select --install`).

```bash
cd macos
./construire.sh
open CopieRapide.app
```

To also install it in `/Applications` and relaunch it: `./construire.sh --installer`.

There is no downloadable app: a downloadable macOS app needs an Apple Developer ID and notarisation, which this project does not have.

### Permissions

| Permission | Why |
| --- | --- |
| Accessibility | read the selection and send the shortcuts |
| Automation → Finder | know which files are selected |
| Screen Recording | the screenshots |

### Keep the permissions between builds

By default the app is signed **ad hoc**: macOS then recognises it by the fingerprint of its binary, so it asks for Accessibility and Screen Recording again after every rebuild. If you rebuild often, sign with a stable certificate of your own:

1. Open **Keychain Access → Certificate Assistant → Create a Certificate…**, choose *Self Signed Root* and *Code Signing*, and give it a name.
2. If `security find-identity -v -p codesigning` does not list it, set the certificate to *Always Trust* for Code Signing in Keychain Access.
3. Build with `SIGN_IDENTITY="Your Certificate Name" ./construire.sh`.

Keep the private key to yourself. A certificate like this only identifies the app on your own Mac; it does not let you give the app to someone else.

### Privacy

No network connection: no networking library is linked into the binary, which you can check yourself with `otool -L macos/CopieRapide.app/Contents/MacOS/CopieRapide`. Nothing is sent anywhere. The history lives in the app's local preferences.

## Contributing

Issues and pull requests are welcome, see [CONTRIBUTING.md](CONTRIBUTING.md). Please read the [Code of Conduct](CODE_OF_CONDUCT.md). Security problems: [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE), © 2026 Yannick (yanmwisa). No third-party code is included.

---

## En français

**Copier, couper, coller et supprimer à la souris**, grâce à une petite barre qui suit votre sélection.

- **Userscript** (`userscript/`) : dans le navigateur, sous **Windows et macOS**, avec Tampermonkey ou Violentmonkey. Aucune requête réseau ; un seul emplacement caché garde le dernier texte copié (8 h) pour coller d'un onglet à l'autre.
- **CopieRapide** (`macos/`) : application macOS native en Swift, dans toutes les applications (texte et fichiers du Finder). Compilation : `cd macos && ./construire.sh`.
- Il n'existe **pas d'application Windows native** : sous Windows, seul le userscript fonctionne, et seulement dans le navigateur.
- Licence MIT.
