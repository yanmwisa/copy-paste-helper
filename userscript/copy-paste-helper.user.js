// ==UserScript==
// @name         Copy Paste Helper — mouse copy and paste
// @namespace    https://github.com/yanmwisa/copy-paste-helper
// @version      4.3
// @author       Yannick (yanmwisa)
// @license      MIT
// @homepage     https://github.com/yanmwisa/copy-paste-helper
// @supportURL   https://github.com/yanmwisa/copy-paste-helper/issues
// @description  Copy / Cut / Paste from the mouse, on any page and across tabs. Buttons appear next to the cursor. Windows and macOS.
// @match        *://*/*
// @exclude      *://*/*signin*
// @exclude      *://*/*login*
// @exclude      *://*/*logon*
// @exclude      *://*/*sso*
// @exclude      *://*/*auth*
// @exclude      *://*/*password*
// @grant        GM_setValue
// @grant        GM_getValue
// @grant        GM_deleteValue
// @run-at       document-idle
// @noframes
// ==/UserScript==

/*
 * A small action bar that follows the text selection: Copy, Cut, Paste
 * and Delete, reachable with the mouse alone.
 *
 * PRIVACY
 *   No network request: no @connect, no fetch, no XHR.
 *   No history is kept. A single hidden slot holds the LAST copied
 *   text so Paste still works from one tab to the next — the system
 *   clipboard cannot be read reliably by a web script. That slot is
 *   overwritten on every copy and expires after DUREE_VIE_H hours.
 *   Set PARTAGE_ENTRE_ONGLETS to false and nothing is written to disk
 *   at all; Paste then no longer follows across tabs.
 *   Sign-in, SSO and password pages are excluded above.
 *
 * PERMISSIONS
 *   GM_getValue / GM_setValue / GM_deleteValue   the relay slot and
 *                                                the appearance setting.
 */

(function () {
    'use strict';

    // ─────────────────────────────────────────────────────────────
    //  SETTINGS
    // ─────────────────────────────────────────────────────────────
    const PARTAGE_ENTRE_ONGLETS = true;   // false = nothing is written to disk
    const DUREE_VIE_H = 8;                // relay slot expiry, in hours
    const DISTANCE_CURSEUR = 8;           // px between the cursor and the bar

    // Appearance: "sobre" (default), "couleur", "compacte". Changed from
    // the chevron next to Paste, and remembered.
    function apparence() { return GM_getValue('cp_apparence', 'sobre'); }

    // Light, warm card with a single accent ink. Pages underneath are
    // white; a dark bar fights them at every glance.
    // No font is downloaded — nothing leaves the machine. Georgia and
    // Segoe UI are already present on Windows and macOS alike.
    const P = {
        carte:  '#fffdf9',                  // surface background
        creux:  '#faf7f0',                  // menu footer, recessed areas
        ligne:  '#e0d8c9',                  // outer border
        trait:  '#f0ebe1',                  // inner separator, quieter
        survol: '#f7f2e8',                  // hover background
        txt:    '#211d17',
        dim:    '#5f574c',
        faint:  '#a39a8b',
        ocre:   '#9a5b12',
        ocreF:  '#f7edd9',
        rouge:  '#a8422a',
        ombreB: '0 12px 30px -10px rgba(60,48,32,.32)',
        ombreM: '0 16px 36px -12px rgba(60,48,32,.32)',
        sans:   '-apple-system,BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif',
        serif:  'Georgia,Cambria,"Times New Roman",serif'
    };

    const MAC = /Mac|iPhone|iPad/.test(navigator.platform) ||
                /Mac/.test(navigator.userAgent);
    const MOD = MAC ? 'metaKey' : 'ctrlKey';
    const RACCOURCI = MAC ? '⌘' : 'Ctrl';

    // ─────────────────────────────────────────────────────────────
    //  Copy relay — one slot, never displayed
    //  Not a history: a single text at a time, overwritten on every
    //  copy, with nowhere to browse it. It covers the one case where
    //  the browser refuses to read the clipboard, so Paste still works
    //  from one tab to the next.
    // ─────────────────────────────────────────────────────────────
    const CLE_RELAIS = 'cp_relais';
    let volatile = '';

    // Clears the history left by earlier versions, which no longer
    // has any reason to exist.
    try { GM_deleteValue('cp_historique'); } catch (e) { /* nothing to clear */ }

    function dernierCopie() {
        if (!PARTAGE_ENTRE_ONGLETS) return volatile;
        let e = null;
        try { e = JSON.parse(GM_getValue(CLE_RELAIS, 'null')); } catch (err) { e = null; }
        if (!e || typeof e.v !== 'string') return '';
        if (!(e.t > Date.now() - DUREE_VIE_H * 3600 * 1000)) {
            try { GM_deleteValue(CLE_RELAIS); } catch (err) { /* already gone */ }
            return '';
        }
        return e.v;
    }

    function memoriser(texte) {
        if (!texte) return;
        if (!PARTAGE_ENTRE_ONGLETS) { volatile = texte; return; }
        try { GM_setValue(CLE_RELAIS, JSON.stringify({ v: texte, t: Date.now() })); }
        catch (e) { /* storage full: carry on without the relay */ }
    }

    // ─────────────────────────────────────────────────────────────
    //  Clipboard
    // ─────────────────────────────────────────────────────────────
    function ecrirePressePapier(texte) {
        memoriser(texte);
        if (navigator.clipboard && navigator.clipboard.writeText) {
            return navigator.clipboard.writeText(texte).catch(() => secoursEcriture(texte));
        }
        secoursEcriture(texte);
        return Promise.resolve();
    }

    function secoursEcriture(texte) {
        const ta = document.createElement('textarea');
        ta.value = texte;
        ta.style.cssText = 'position:fixed;top:-1000px;opacity:0;';
        document.body.appendChild(ta);
        ta.select();
        try { document.execCommand('copy'); } catch (e) { /* no fallback left */ }
        ta.remove();
    }

    // Paste must work on the first click. Asking the system clipboard
    // without permission makes the browser show its own confirmation
    // chip — a second click for nothing. So the system is queried only
    // when permission is already granted (silent, and it also picks up
    // what other applications copied), or as a last resort when the
    // relay has nothing to offer.
    function permissionLecture() {
        try {
            if (navigator.permissions && navigator.permissions.query) {
                return navigator.permissions.query({ name: 'clipboard-read' })
                    .then(p => p.state === 'granted')
                    .catch(() => false);
            }
        } catch (e) { /* permission name unknown to this browser */ }
        return Promise.resolve(false);
    }

    function lireSysteme() {
        if (!navigator.clipboard || !navigator.clipboard.readText) return Promise.resolve('');
        return navigator.clipboard.readText().catch(() => '');
    }

    function lirePressePapier() {
        return permissionLecture().then(accordee => {
            if (accordee) return lireSysteme().then(t => t || dernierCopie());
            const relais = dernierCopie();
            if (relais) return relais;   // one click, no confirmation
            return lireSysteme();        // nothing in reserve: ask anyway
        });
    }

    // ─────────────────────────────────────────────────────────────
    //  Writing into a field
    //  Assigning .value is invisible to modern applications: they hold
    //  their own state and overwrite the value on submit.
    // ─────────────────────────────────────────────────────────────
    // `texte` may be empty: that is how Delete clears the selection.
    function insererDans(champ, texte) {
        if (!champ || typeof texte !== 'string') return false;
        if (champ.isContentEditable) {
            champ.focus();
            document.execCommand('insertText', false, texte);
            return true;
        }
        if (!('value' in champ)) return false;

        champ.focus();
        const debut = champ.selectionStart ?? champ.value.length;
        const fin   = champ.selectionEnd   ?? champ.value.length;
        const suite = champ.value.slice(0, debut) + texte + champ.value.slice(fin);

        const proto = champ instanceof HTMLTextAreaElement
            ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
        Object.getOwnPropertyDescriptor(proto, 'value').set.call(champ, suite);

        const pos = debut + texte.length;
        try { champ.setSelectionRange(pos, pos); } catch (e) { /* input type with no selection API */ }
        champ.dispatchEvent(new Event('input',  { bubbles: true }));
        champ.dispatchEvent(new Event('change', { bubbles: true }));
        return true;
    }

    function supprimerSelectionDe(champ) {
        if (!champ) return;
        if (champ.isContentEditable) { document.execCommand('delete'); return; }
        insererDans(champ, '');
    }

    // ─────────────────────────────────────────────────────────────
    //  The action bar
    // ─────────────────────────────────────────────────────────────
    // Copy and Cut take: warm family. Paste puts down: blue. Delete
    // destroys: red. All hold 4.5:1 on the light card, small sizes
    // included.
    const TEINTES = {
        Copy:   '#9a5b12',
        Cut:    '#7c4a1e',
        Delete: '#a8422a',
        Paste:  '#2c5d8a'
    };

    const ICONES = {
        Copy:  'M9 9h11v11H9zM5 15H4V4h11v1',
        Cut:   'M6 3l12 12M18 3L6 15M7 20a2.5 2.5 0 100-5 2.5 2.5 0 000 5zM17 20a2.5 2.5 0 100-5 2.5 2.5 0 000 5z',
        Paste: 'M16 4h2a2 2 0 012 2v14a2 2 0 01-2 2H6a2 2 0 01-2-2V6a2 2 0 012-2h2M8 2h8v4H8z',
        Delete: 'M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v6M14 11v6'
    };

    const barre = document.createElement('div');
    barre.id = 'cph-barre';
    barre.style.cssText = `
        position:absolute;z-index:2147482000;display:none;align-items:center;gap:3px;
        padding:4px;border-radius:999px;background:${P.carte};
        border:1px solid ${P.ligne};box-shadow:${P.ombreB};
        font:500 12.5px ${P.sans};user-select:none;
    `;
    barre.addEventListener('mousedown', e => e.preventDefault());  // keep the selection alive
    document.body.appendChild(barre);

    const menu = document.createElement('div');
    menu.id = 'cph-menu';
    menu.style.cssText = `
        position:absolute;z-index:2147482001;display:none;min-width:262px;max-width:430px;
        background:${P.carte};border:1px solid ${P.ligne};border-radius:12px;
        box-shadow:${P.ombreM};padding:0;overflow:hidden;
        font:12px ${P.sans};color:${P.txt};
    `;
    document.body.appendChild(menu);

    function icone(chemin) {
        const ns = 'http://www.w3.org/2000/svg';
        const svg = document.createElementNS(ns, 'svg');
        svg.setAttribute('width', '13'); svg.setAttribute('height', '13');
        svg.setAttribute('viewBox', '0 0 24 24'); svg.setAttribute('fill', 'none');
        svg.setAttribute('stroke', 'currentColor'); svg.setAttribute('stroke-width', '1.8');
        svg.setAttribute('stroke-linecap', 'round'); svg.setAttribute('stroke-linejoin', 'round');
        const p = document.createElementNS(ns, 'path');
        p.setAttribute('d', chemin);
        svg.appendChild(p);
        return svg;
    }

    function fabriquer(nom, action) {
        const teinte = TEINTES[nom];
        const mode = apparence();
        const b = document.createElement('button');
        b.type = 'button';
        b.title = `${nom}  (${RACCOURCI}+${nom === 'Delete' ? '⌫' : nom[0]})`;
        b.style.cssText = `
            display:inline-flex;align-items:center;gap:6px;border:none;border-radius:999px;
            cursor:pointer;font:inherit;font-weight:600;transition:all .15s;
            padding:${mode === 'compacte' ? '8px' : '7px 13px'};
        `;
        b.appendChild(icone(ICONES[nom]));
        if (mode !== 'compacte') {
            const s = document.createElement('span');
            s.textContent = nom;
            b.appendChild(s);
        }

        // Full colour: the hue is always on. Plain and compact: neutral
        // at rest, hue only on hover.
        const repos = () => {
            if (mode === 'couleur') { b.style.background = teinte; b.style.color = P.carte; }
            else { b.style.background = 'transparent'; b.style.color = P.txt; }
        };
        const survol = () => {
            if (mode === 'couleur') { b.style.filter = 'brightness(1.15)'; }
            else { b.style.background = P.ocreF; b.style.color = teinte; }
        };
        repos();
        b.addEventListener('mouseenter', survol);
        b.addEventListener('mouseleave', () => { b.style.filter = ''; repos(); });
        b.addEventListener('mousedown', e => e.preventDefault());
        b.addEventListener('click', (e) => { e.stopPropagation(); action(b, b.querySelector('span') || b); });
        return b;
    }

    function clignoter(cible, mot) {
        if (cible.tagName === 'BUTTON') {      // compact mode: no label
            cible.title = mot;
            cible.style.outline = '2px solid ' + (cible.style.color || '#fff');
            setTimeout(() => { cible.style.outline = ''; }, 700);
            return;
        }
        const avant = cible.textContent;
        cible.textContent = mot;
        setTimeout(() => { cible.textContent = avant; }, 900);
    }

    // The bar closes itself after an action. That timer must be
    // cancelled as soon as a new selection reopens it, otherwise a
    // select-all right after a Copy sees it vanish at once.
    let minuteurCacher = null;

    function cacher() {
        clearTimeout(minuteurCacher);
        minuteurCacher = null;
        barre.style.display = 'none';
        menu.style.display = 'none';
    }

    function cacherPlusTard(ms) {
        clearTimeout(minuteurCacher);
        minuteurCacher = setTimeout(cacher, ms);
    }

    // Places the bar next to the cursor, kept inside the viewport.
    function placer(x, y) {
        barre.style.display = 'inline-flex';
        const l = barre.offsetWidth, h = barre.offsetHeight;
        let px = x + DISTANCE_CURSEUR;
        let py = y - h - DISTANCE_CURSEUR;
        if (px + l > window.innerWidth - 6)  px = x - l - DISTANCE_CURSEUR;
        if (py < 4) py = y + DISTANCE_CURSEUR + 6;
        px = Math.max(4, Math.min(px, window.innerWidth  - l - 6));
        py = Math.max(4, Math.min(py, window.innerHeight - h - 6));
        barre.style.left = (px + window.scrollX) + 'px';
        barre.style.top  = (py + window.scrollY) + 'px';
    }

    function montrer(x, y, noms) {
        clearTimeout(minuteurCacher);
        minuteurCacher = null;
        barre.textContent = '';
        noms.forEach(n => barre.appendChild(fabriquer(n, ACTIONS[n])));
        if (noms.includes('Paste')) barre.appendChild(fabriquerFleche());
        placer(x, y);
    }

    function fabriquerFleche() {
        const b = document.createElement('button');
        b.type = 'button';
        b.appendChild(icone('M6 9l6 6 6-6'));   // drawn chevron, not a glyph
        b.title = 'Appearance';
        b.style.cssText = `border:none;background:${P.creux};color:${P.dim};
            border-radius:999px;cursor:pointer;padding:7px 9px;font:inherit;
            display:inline-flex;align-items:center;`;
        b.addEventListener('mousedown', e => e.preventDefault());
        b.addEventListener('click', (e) => { e.stopPropagation(); basculerMenu(); });
        return b;
    }

    // ─────────────────────────────────────────────────────────────
    //  Actions
    // ─────────────────────────────────────────────────────────────
    let champActif = null;

    const ACTIONS = {
        Copy: (b, span) => {
            const t = texteSelectionne(champActif);
            if (!t) { clignoter(span, 'Nothing'); return; }
            ecrirePressePapier(t).then(() => { clignoter(span, 'Copied'); cacherPlusTard(700); });
        },
        Cut: (b, span) => {
            const t = texteSelectionne(champActif);
            if (!t) { clignoter(span, 'Nothing'); return; }
            ecrirePressePapier(t).then(() => {
                const cible = champActif || document.activeElement;
                if (cible && (cible.isContentEditable || 'value' in cible)) supprimerSelectionDe(cible);
                else document.execCommand('delete');
                clignoter(span, 'Cut');
                cacherPlusTard(700);
            });
        },
        // Delete clears without touching the clipboard: what is removed
        // does not overwrite what was copied.
        Delete: (b, span) => {
            const t = texteSelectionne(champActif);
            if (!t) { clignoter(span, 'Nothing'); return; }
            const cible = champActif || document.activeElement;
            if (cible && (cible.isContentEditable || 'value' in cible)) supprimerSelectionDe(cible);
            else document.execCommand('delete');
            clignoter(span, 'Deleted');
            cacherPlusTard(600);
        },
        Paste: (b, span) => {
            const cible = champActif;
            if (!cible) { clignoter(span, 'No field'); return; }
            lirePressePapier().then(t => {
                if (!t) { clignoter(span, 'Empty'); return; }
                insererDans(cible, t);
                clignoter(span, 'Pasted');
                cacherPlusTard(700);
            });
        }
    };

    // The chevron opens a single setting: the bar's appearance.
    function basculerMenu() {
        if (menu.style.display === 'block') { menu.style.display = 'none'; return; }
        menu.textContent = '';

        const titre = document.createElement('div');
        titre.textContent = 'Appearance';
        titre.style.cssText = `font:500 14px ${P.serif};color:${P.txt};` +
                              'padding:11px 14px 8px;';
        menu.appendChild(titre);

        // Footer: appearance, chosen without leaving the page.
        const pied = document.createElement('div');
        pied.style.cssText = `border-top:1px solid ${P.trait};background:${P.creux};` +
                             'padding:8px 12px;display:flex;gap:5px;align-items:center;' +
                             `font:600 10px ${P.sans};text-transform:uppercase;letter-spacing:.1em;color:${P.faint};`;
        pied.appendChild(document.createTextNode('Look'));
        [['sobre', 'Plain'], ['couleur', 'Colour'], ['compacte', 'Compact']].forEach(([cle, lbl]) => {
            const c = document.createElement('span');
            c.textContent = lbl;
            const on = apparence() === cle;
            c.style.cssText = `padding:3px 10px;border-radius:999px;cursor:pointer;border:none;
                font:600 11px ${P.sans};text-transform:none;letter-spacing:0;
                color:${on ? P.ocre : P.dim};background:${on ? P.ocreF : 'transparent'};`;
            c.addEventListener('mousedown', ev => ev.preventDefault());
            c.addEventListener('click', (ev) => { ev.stopPropagation(); GM_setValue('cp_apparence', cle); cacher(); });
            pied.appendChild(c);
        });
        menu.appendChild(pied);

        menu.style.display = 'block';
        menu.style.top  = (parseFloat(barre.style.top) + barre.offsetHeight + 6) + 'px';
        menu.style.left = barre.style.left;
    }

    // ─────────────────────────────────────────────────────────────
    //  Triggers
    // ─────────────────────────────────────────────────────────────
    function champDe(cible) {
        return cible && cible.closest
            ? cible.closest('input:not([type=password]):not([readonly]),textarea:not([readonly]),[contenteditable="true"]')
            : null;
    }

    // window.getSelection() does NOT report what is selected inside an
    // <input> or a <textarea>: it returns an empty string there. Without
    // reading the field itself, neither select-all, nor a double-click
    // on a word, nor a mouse selection brings up Copy / Cut / Delete
    // while working in a field.
    function selectionDeChamp(champ) {
        if (!champ || champ.isContentEditable || !('value' in champ)) return '';
        let a, b;
        try { a = champ.selectionStart; b = champ.selectionEnd; }
        catch (e) { return ''; }   // some input types forbid selection
        if (typeof a !== 'number' || typeof b !== 'number' || b <= a) return '';
        return String(champ.value).slice(a, b);
    }

    // The exact text, untrimmed: this is what goes to the clipboard.
    function texteSelectionne(champ) {
        const t = selectionDeChamp(champ || document.activeElement);
        if (t) return t;
        const s = window.getSelection();
        return s ? s.toString() : '';
    }

    // Where to place the bar when the selection came from the keyboard.
    function repere(champ) {
        const s = window.getSelection();
        if (s && s.rangeCount && s.toString()) {
            const r = s.getRangeAt(0).getBoundingClientRect();
            if (r.width || r.height) return [r.right, r.bottom];
        }
        if (champ) {
            const r = champ.getBoundingClientRect();
            if (r.width || r.height) return [r.right, r.bottom];
        }
        return [window.innerWidth / 2, window.innerHeight / 2];
    }

    document.addEventListener('mouseup', (e) => {
        if (barre.contains(e.target) || menu.contains(e.target)) return;
        setTimeout(() => {
            const champ = champDe(e.target);
            champActif = champ;
            const texte = texteSelectionne(champ).trim();

            if (texte) {
                // Cut only makes sense in an editable field.
                montrer(e.clientX, e.clientY, champ ? ['Copy', 'Cut', 'Delete'] : ['Copy']);
            } else if (champ) {
                montrer(e.clientX, e.clientY, ['Paste']);
            } else {
                cacher();
            }
        }, 10);
    });

    // Keyboard selection: select-all, shift+arrows.
    let minuteur = null;
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') { cacher(); return; }
        const tout = e[MOD] && (e.key === 'a' || e.key === 'A');
        const etendu = e.shiftKey && /^(Arrow|Home|End|Page)/.test(e.key);
        if (!tout && !etendu) return;

        clearTimeout(minuteur);
        minuteur = setTimeout(() => {
            const champ = champDe(document.activeElement);
            champActif = champ;
            const texte = texteSelectionne(champ).trim();
            if (!texte) { cacher(); return; }
            // A select-all over a whole page runs off screen: the
            // anchor point is pulled back inside the window.
            const [rx, ry] = repere(champ);
            const x = Math.min(Math.max(rx, 8), window.innerWidth  - 8);
            const y = Math.min(Math.max(ry, 8), window.innerHeight - 8);
            montrer(x, y, champ ? ['Copy', 'Cut', 'Delete'] : ['Copy']);
        }, 300);
    });

    document.addEventListener('mousedown', (e) => {
        if (!barre.contains(e.target) && !menu.contains(e.target)) cacher();
    });
    document.addEventListener('scroll', cacher, true);
})();
