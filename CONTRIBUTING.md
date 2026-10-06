# Contributing to Copy Paste Helper

Thanks for helping. Issues and pull requests are welcome, in English or French.

## Before you start

- For a bug, search the existing issues, then open one with the template.
- For a new feature, open an issue first. The project is small on purpose: a bar with Copy, Cut, Paste and Delete, no network, almost no state.
- A **native Windows app** would be a great contribution. Open an issue to agree on the approach (language, how to read the selection) before building it.
- By contributing, you agree that your contribution is released under the [MIT License](LICENSE).

## Userscript (`userscript/`)

One file, no build step.

```bash
node --check userscript/copy-paste-helper.user.js
```

Then install the file in a userscript manager and try it on a few pages (a text page, a form, a rich editor, a page with an iframe). Keep these rules: no network request, no new `@grant` without a strong reason (say why in the pull request), no change that makes it act on sign-in or password pages. If you change what is stored, update the README and `SECURITY.md`.

## macOS app (`macos/`)

You need macOS 13 or later and the Xcode Command Line Tools.

```bash
cd macos
./construire.sh
open CopieRapide.app
```

`construire.sh` signs ad hoc unless you set `SIGN_IDENTITY`, and installs in `/Applications` only with `--installer`. Do not link any networking library: the README says the binary has none, and `otool -L` shows it.

## Code style

- Keep it dependency-free.
- Small functions, early returns, names that say what they mean.
- Comments in French or English are both fine.

## Pull requests

- One subject per pull request.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/): `feat(userscript): …`, `fix(macos): …`. The body says why, not how.
- Fill in the pull request template, and say what you tested and what you could not (browser, OS).
