# Security Policy

Copy Paste Helper handles the text you copy, so a security problem here matters. Reports are welcome.

## Supported versions

Only the latest version on the `main` branch is supported.

## Reporting a vulnerability

**Please do not open a public issue.** Use GitHub's private reporting: on the repository page, open **Security → Report a vulnerability**.

Include:

- which part is concerned (userscript or macOS app) and the file or function;
- how to reproduce it, with the macOS or Windows version and the browser;
- what an attacker could do with it.

This is a personal project maintained in spare time, so there is no guaranteed response time. You will get an answer, and credit in the changelog if you want it.

## What is in scope

- **Userscript**: anything that makes it send data out of the page, read a field it should not (password fields, sign-in pages), keep the copied text longer than the relay slot, or be triggered by a web page.
- **macOS app**: anything that makes it open a network connection, keep history beyond 24 hours, act on files you did not select, or ask for more permissions than the README lists.
- The build script `macos/construire.sh` and how it signs the app.

## Known design limits (not vulnerabilities)

- The userscript keeps the **last copied text** in the userscript manager's storage for up to 8 hours, so Paste works across tabs. `PARTAGE_ENTRE_ONGLETS = false` turns this off.
- The macOS app keeps the last 12 copied texts for up to 24 hours in its local preferences, unless `HISTORIQUE_ACTIF` is `false`.
- Builds are signed ad hoc and are not notarised.

## Out of scope

Problems in macOS, in your browser, or in a userscript manager (report those to their authors; tell me too if Copy Paste Helper is affected).
