//
//  CopieRapide — Copy · Cut · Paste sous le curseur, dans toutes les apps.
//
//  ─────────────────────────────────────────────────────────────────
//  CE QUE FAIT CETTE APPLICATION, ET RIEN D'AUTRE
//  ─────────────────────────────────────────────────────────────────
//  · Elle observe la souris et les touches de sélection.
//  · Elle demande à macOS le texte sélectionné dans l'app active.
//  · Dans le Finder, elle demande les fichiers, dossiers et photos
//    sélectionnés — que l'Accessibilité ne voit pas, faute de texte.
//  · Elle affiche une barre près du curseur : Copy, Cut, Paste, Delete.
//  · Elle garde les derniers textes copiés, effacés après 24 heures.
//
//  AUCUNE connexion réseau : aucune bibliothèque réseau n'est liée au
//  binaire, ce qui se vérifie avec « otool -L ».
//
//  L'historique vit dans les préférences de l'app (UserDefaults), en
//  clair, et TOUTE entrée de plus de 24 h est supprimée au démarrage
//  et à chaque ouverture de la fenêtre. « Vider » efface tout, tout de
//  suite. Mets HISTORIQUE_ACTIF à false pour ne rien conserver.
//
//  Désinstallation : quitter par le menu, jeter CopieRapide.app, puis
//  retirer l'accès dans Réglages ▸ Confidentialité ▸ Accessibilité.
//

import Cocoa
import ApplicationServices

// ═════════════════════════════════════════════════════════════════
//  RÉGLAGES
// ═════════════════════════════════════════════════════════════════
let HISTORIQUE_ACTIF = true
let DUREE_VIE_HEURES: TimeInterval = 24
let HISTORIQUE_MAX = 12
let DISTANCE_CURSEUR: CGFloat = 10

/// Les trois expressions de la barre. « Sobre » est le défaut : elle se
/// fait oublier tant qu'on ne la survole pas.
enum Variante: String, CaseIterable {
    case sobre, couleur, compacte
    var titre: String {
        switch self {
        case .sobre:    return "Sobre"
        case .couleur:  return "Couleur pleine"
        case .compacte: return "Compacte"
        }
    }
}

enum Reglages {
    private static let cle = "variante"
    static var variante: Variante {
        get { Variante(rawValue: UserDefaults.standard.string(forKey: cle) ?? "") ?? .sobre }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: cle) }
    }
}

// ═════════════════════════════════════════════════════════════════
//  HISTORIQUE
// ═════════════════════════════════════════════════════════════════
struct Entree {
    let texte: String
    let quand: Date
}

enum Historique {
    private static let cle = "historique"

    static func lire() -> [Entree] {
        guard HISTORIQUE_ACTIF,
              let brut = UserDefaults.standard.array(forKey: cle) as? [[String: Any]]
        else { return [] }

        let limite = Date().addingTimeInterval(-DUREE_VIE_HEURES * 3600)
        let vivantes = brut.compactMap { d -> Entree? in
            guard let t = d["t"] as? String, let q = d["q"] as? TimeInterval else { return nil }
            let date = Date(timeIntervalSince1970: q)
            return date > limite ? Entree(texte: t, quand: date) : nil
        }
        // Les entrées périmées disparaissent dès la lecture : rien ne
        // subsiste sur le disque au-delà de la durée de vie.
        if vivantes.count != brut.count { ecrire(vivantes) }
        return vivantes
    }

    static func ajouter(_ texte: String) {
        guard HISTORIQUE_ACTIF else { return }
        guard !texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var liste = lire().filter { $0.texte != texte }
        liste.insert(Entree(texte: texte, quand: Date()), at: 0)
        ecrire(Array(liste.prefix(HISTORIQUE_MAX)))
    }

    static func vider() { UserDefaults.standard.removeObject(forKey: cle) }

    private static func ecrire(_ liste: [Entree]) {
        UserDefaults.standard.set(
            liste.map { ["t": $0.texte, "q": $0.quand.timeIntervalSince1970] as [String: Any] },
            forKey: cle)
    }

    static func age(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "à l'instant" }
        if s < 3600 { return "il y a \(s / 60) min" }
        return "il y a \(s / 3600) h"
    }
}

// ═════════════════════════════════════════════════════════════════
//  LECTURE DE LA SÉLECTION
// ═════════════════════════════════════════════════════════════════
enum Selection {

    enum Resultat {
        /// macOS nous a donné le texte : on le copiera nous-même.
        case texte(String)
        /// Les applications web n'exposent pas la sélection d'une page :
        /// on demandera alors à l'application de copier elle-même.
        case demanderALApplication
    }

    static func courante(gesteFranc: Bool) -> Resultat? {
        if let t = viaAccessibilite() { return .texte(t) }
        return gesteFranc ? .demanderALApplication : nil
    }

    private static func elementFocalise() -> AXUIElement? {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(),
                                            kAXFocusedUIElementAttribute as CFString,
                                            &focused) == .success,
              let e = focused else { return nil }
        return (e as! AXUIElement)
    }

    private static func viaAccessibilite() -> String? {
        guard let cible = elementFocalise() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(cible, kAXSelectedTextAttribute as CFString,
                                            &value) == .success,
              let texte = value as? String,
              !texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return texte
    }

    /// Rôles où l'on n'écrit jamais. Tout le reste est considéré comme
    /// « peut-être un champ » : les applications web déclarent des rôles
    /// inattendus, et ne jamais proposer Paste serait pire.
    private static let nonEditables: Set<String> = [
        "AXStaticText", "AXButton", "AXImage", "AXLink", "AXMenuItem", "AXMenuBar",
        "AXMenuBarItem", "AXCheckBox", "AXRadioButton", "AXScrollBar", "AXSlider",
        "AXTable", "AXOutline", "AXToolbar", "AXTabGroup", "AXWindow", "AXApplication",
        "AXList", "AXCell", "AXGroup", "AXSplitGroup"
    ]

    static func zoneModifiable() -> Bool {
        guard let cible = elementFocalise() else { return true }
        var role: CFTypeRef?
        var nom = ""
        if AXUIElementCopyAttributeValue(cible, kAXRoleAttribute as CFString, &role) == .success,
           let r = role as? String { nom = r }

        let saisie: Set<String> = [kAXTextFieldRole as String, kAXTextAreaRole as String,
                                   kAXComboBoxRole as String, "AXSearchField"]
        if saisie.contains(nom) { return true }

        var modifiable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(cible, kAXValueAttribute as CFString,
                                          &modifiable) == .success, modifiable.boolValue {
            return true
        }
        return !nonEditables.contains(nom)
    }

    static func demanderCopie()   { envoyer(0x08, cmd: true) }   // Cmd+C
    static func demanderCoupe()   { envoyer(0x07, cmd: true) }   // Cmd+X
    static func demanderCollage() { envoyer(0x09, cmd: true) }   // Cmd+V
    /// Efface la sélection SANS toucher au presse-papier : c'est ce qui
    /// distingue Delete de Cut.
    static func demanderSuppression() { envoyer(0x33, cmd: false) }   // Backspace

    /// La barre ne prend jamais le focus : la frappe arrive donc bien à
    /// l'application d'origine.
    private static func envoyer(_ touche: CGKeyCode, cmd: Bool) {
        let src = CGEventSource(stateID: .combinedSessionState)
        guard let bas = CGEvent(keyboardEventSource: src, virtualKey: touche, keyDown: true),
              let haut = CGEvent(keyboardEventSource: src, virtualKey: touche, keyDown: false)
        else { return }
        if cmd { bas.flags = .maskCommand; haut.flags = .maskCommand }
        bas.post(tap: .cghidEventTap)
        haut.post(tap: .cghidEventTap)
    }
}

// ═════════════════════════════════════════════════════════════════
//  FICHIERS, DOSSIERS ET PHOTOS DU FINDER
//  Un fichier sélectionné n'est pas du texte : l'Accessibilité ne le
//  voit pas, et c'est pourquoi la barre restait muette sur le Bureau.
//  On demande donc au Finder lui-même ce qui est sélectionné, puis on
//  lui laisse faire le travail : il gère les conflits de noms, la
//  barre de progression et l'annulation par Cmd+Z bien mieux que nous.
//  Nécessite l'autorisation « Automatisation ▸ Finder ».
// ═════════════════════════════════════════════════════════════════
enum Fichiers {

    /// Le Bureau est une fenêtre du Finder : ce test le couvre aussi.
    static var finderDevant: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
    }

    /// Passe à vrai si le Finder nous refuse l'accès. Le menu le dit
    /// alors franchement, au lieu de laisser des boutons sans effet.
    private(set) static var accesRefuse = false

    private static func demanderAuFinder(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var erreur: NSDictionary?
        let res = script.executeAndReturnError(&erreur)
        if let e = erreur {
            // -1743 : autorisation refusée. -600 : le Finder ne répond pas.
            let code = (e[NSAppleScript.errorNumber] as? Int) ?? 0
            accesRefuse = (code == -1743 || code == -600)
            return nil
        }
        accesRefuse = false
        return res.stringValue
    }

    /// `nil` = le Finder ne nous a pas répondu. `[]` = il a répondu que
    /// rien n'est sélectionné. Confondre les deux, c'est laisser une
    /// panne d'autorisation ressembler à un dossier vide.
    static func selection() -> [URL]? {
        let source = """
        tell application "Finder"
          set sortie to ""
          repeat with element in (get selection)
            set sortie to sortie & (POSIX path of (element as alias)) & linefeed
          end repeat
          return sortie
        end tell
        """
        guard let brut = demanderAuFinder(source) else { return nil }
        return brut.split(separator: "\n")
                   .map { URL(fileURLWithPath: String($0)) }
    }

    /// Ne proposer Paste que lorsqu'il y a vraiment des fichiers à poser.
    static var pressePapierPorteDesFichiers: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSURL.self],
                                           options: [.urlReadingFileURLsOnly: true])
    }

    // ── Les gestes, confiés au Finder lui-même ──
    private static var marqueDeCoupe: Int?

    static func copier() { touche(0x08, [.maskCommand]) }              // Cmd+C

    /// Le Finder n'a pas de « couper ». Le geste natif est : copier,
    /// puis « Déplacer les éléments ici » (Cmd+Option+V). On copie donc,
    /// et on retient que le prochain collage devra déplacer.
    static func couper() {
        touche(0x08, [.maskCommand])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            marqueDeCoupe = NSPasteboard.general.changeCount
        }
    }

    /// Vrai tant que rien d'autre n'a été copié depuis le Cut : toute
    /// copie ultérieure change le compteur et annule le déplacement.
    static var enModeDeplacement: Bool {
        marqueDeCoupe == NSPasteboard.general.changeCount
    }

    static func coller() {
        if enModeDeplacement { touche(0x09, [.maskCommand, .maskAlternate]) }
        else                 { touche(0x09, [.maskCommand]) }
    }

    /// Cmd+Suppr : à la corbeille, pas de destruction. Cmd+Z annule.
    static func mettreALaCorbeille() { touche(0x33, [.maskCommand]) }

    private static func touche(_ code: CGKeyCode, _ drapeaux: CGEventFlags) {
        let src = CGEventSource(stateID: .combinedSessionState)
        guard let bas = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true),
              let haut = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
        else { return }
        bas.flags = drapeaux; haut.flags = drapeaux
        bas.post(tap: .cghidEventTap)
        haut.post(tap: .cghidEventTap)
    }
}

// ═════════════════════════════════════════════════════════════════
//  CAPTURE D'ÉCRAN
//  On délègue à l'outil natif « screencapture » : c'est exactement ce
//  que fait Cmd+Maj+4, mais déclenché à la souris depuis le menu.
//  L'image est déposée LÀ OÙ VONT LES CAPTURES HABITUELLES DU MAC —
//  le Bureau, sauf réglage contraire — et aussi dans le presse-papier.
//  On peut donc la retrouver plus tard, ou la coller tout de suite.
//  Nécessite l'autorisation « Enregistrement de l'écran ».
// ═════════════════════════════════════════════════════════════════
enum Capture {
    enum Mode { case zone, ecran, fenetre }

    /// On lit le réglage du système : si l'utilisateur a déplacé son
    /// dossier de captures, les nôtres le suivent sans rien configurer.
    static var dossier: URL {
        if let brut = UserDefaults(suiteName: "com.apple.screencapture")?
                        .string(forKey: "location"), !brut.isEmpty {
            let u = URL(fileURLWithPath: (brut as NSString).expandingTildeInPath)
            var estDossier: ObjCBool = false
            if FileManager.default.fileExists(atPath: u.path, isDirectory: &estDossier),
               estDossier.boolValue { return u }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    private static var nomHorodate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_CA")
        f.dateFormat = "yyyy-MM-dd 'à' HH.mm.ss"
        return "Capture d'écran \(f.string(from: Date())).png"
    }

    static func lancer(_ mode: Mode, fini: @escaping (URL?) -> Void) {
        let cible = dossier.appendingPathComponent(nomHorodate)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        switch mode {
        case .zone:    p.arguments = ["-i", cible.path]
        case .ecran:   p.arguments = [cible.path]
        case .fenetre: p.arguments = ["-i", "-W", cible.path]
        }
        p.terminationHandler = { _ in
            DispatchQueue.main.async {
                // Annulée par Échap : aucun fichier n'est écrit, on se tait.
                guard FileManager.default.fileExists(atPath: cible.path) else {
                    fini(nil); return
                }
                deposerDansLePressePapier(cible)
                fini(cible)
            }
        }
        try? p.run()
    }

    /// Un seul élément portant les deux formes : le Finder y voit un
    /// fichier, les éditeurs d'image y voient une image.
    private static func deposerDansLePressePapier(_ url: URL) {
        let item = NSPasteboardItem()
        if let png = try? Data(contentsOf: url) { item.setData(png, forType: .png) }
        item.setString(url.absoluteString, forType: .fileURL)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
    }
}

// ═════════════════════════════════════════════════════════════════
//  ICÔNES
//  Dessinées ici, marquées « template » : macOS les reteinte tout seul
//  selon le thème clair ou sombre.
// ═════════════════════════════════════════════════════════════════
enum Icone {
    static func copy(_ t: CGFloat) -> NSImage { trace(t) { c, s in
        c.addRect(NSRect(x: s*0.36, y: s*0.12, width: s*0.50, height: s*0.50))
        c.move(to: CGPoint(x: s*0.20, y: s*0.40))
        c.addLine(to: CGPoint(x: s*0.14, y: s*0.40))
        c.addLine(to: CGPoint(x: s*0.14, y: s*0.88))
        c.addLine(to: CGPoint(x: s*0.62, y: s*0.88))
        c.addLine(to: CGPoint(x: s*0.62, y: s*0.82))
    }}

    static func cut(_ t: CGFloat) -> NSImage { trace(t) { c, s in
        c.move(to: CGPoint(x: s*0.22, y: s*0.90)); c.addLine(to: CGPoint(x: s*0.74, y: s*0.28))
        c.move(to: CGPoint(x: s*0.78, y: s*0.90)); c.addLine(to: CGPoint(x: s*0.26, y: s*0.28))
        c.addEllipse(in: NSRect(x: s*0.09, y: s*0.07, width: s*0.24, height: s*0.24))
        c.addEllipse(in: NSRect(x: s*0.67, y: s*0.07, width: s*0.24, height: s*0.24))
    }}

    static func paste(_ t: CGFloat) -> NSImage { trace(t) { c, s in
        c.addRect(NSRect(x: s*0.18, y: s*0.08, width: s*0.64, height: s*0.72))
        c.addRect(NSRect(x: s*0.34, y: s*0.76, width: s*0.32, height: s*0.16))
    }}

    static func trash(_ t: CGFloat) -> NSImage { trace(t) { c, s in
        c.move(to: CGPoint(x: s*0.14, y: s*0.76)); c.addLine(to: CGPoint(x: s*0.86, y: s*0.76))
        c.move(to: CGPoint(x: s*0.36, y: s*0.76)); c.addLine(to: CGPoint(x: s*0.36, y: s*0.88))
        c.addLine(to: CGPoint(x: s*0.64, y: s*0.88)); c.addLine(to: CGPoint(x: s*0.64, y: s*0.76))
        c.move(to: CGPoint(x: s*0.22, y: s*0.76)); c.addLine(to: CGPoint(x: s*0.28, y: s*0.12))
        c.addLine(to: CGPoint(x: s*0.72, y: s*0.12)); c.addLine(to: CGPoint(x: s*0.78, y: s*0.76))
        c.move(to: CGPoint(x: s*0.42, y: s*0.60)); c.addLine(to: CGPoint(x: s*0.42, y: s*0.28))
        c.move(to: CGPoint(x: s*0.58, y: s*0.60)); c.addLine(to: CGPoint(x: s*0.58, y: s*0.28))
    }}

    static func clock(_ t: CGFloat) -> NSImage { trace(t) { c, s in
        c.addEllipse(in: NSRect(x: s*0.10, y: s*0.10, width: s*0.80, height: s*0.80))
        c.move(to: CGPoint(x: s*0.50, y: s*0.74))
        c.addLine(to: CGPoint(x: s*0.50, y: s*0.50))
        c.addLine(to: CGPoint(x: s*0.70, y: s*0.36))
    }}

    static func loupe(_ t: CGFloat) -> NSImage { trace(t) { c, s in
        c.addEllipse(in: NSRect(x: s*0.12, y: s*0.32, width: s*0.54, height: s*0.54))
        c.move(to: CGPoint(x: s*0.63, y: s*0.37))
        c.addLine(to: CGPoint(x: s*0.88, y: s*0.12))
    }}

    private static func trace(_ taille: CGFloat,
                              _ chemin: @escaping (CGContext, CGFloat) -> Void) -> NSImage {
        let img = NSImage(size: NSSize(width: taille, height: taille), flipped: false) { _ in
            guard let c = NSGraphicsContext.current?.cgContext else { return true }
            c.setLineWidth(taille * 0.09)
            c.setLineCap(.round); c.setLineJoin(.round)
            c.setStrokeColor(NSColor.black.cgColor)
            chemin(c, taille)
            c.strokePath()
            return true
        }
        img.isTemplate = true
        return img
    }
}

// ═════════════════════════════════════════════════════════════════
//  LA BARRE FLOTTANTE
//  Fond translucide natif : il s'accorde au thème clair ou sombre du
//  système sans qu'on ait à entretenir deux palettes.
// ═════════════════════════════════════════════════════════════════
final class BoutonAction: NSButton {
    var teinte: NSColor = .controlAccentColor
    var variante: Variante = .sobre
    var libelle: String = ""
    private var zone: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let z = zone { removeTrackingArea(z) }
        let z = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways],
                               owner: self, userInfo: nil)
        addTrackingArea(z); zone = z
    }

    func peindre(survole: Bool) {
        switch variante {
        case .couleur:
            layer?.backgroundColor = survole
                ? teinte.blended(withFraction: 0.15, of: .white)?.cgColor : teinte.cgColor
            contentTintColor = .white
            appliquerTitre(.white)
        case .sobre, .compacte:
            // Au repos la barre ne cherche pas à attirer l'œil : la
            // couleur n'arrive qu'au survol.
            layer?.backgroundColor = survole
                ? teinte.withAlphaComponent(0.20).cgColor : NSColor.clear.cgColor
            let c: NSColor = survole ? teinte : .labelColor
            contentTintColor = c
            appliquerTitre(c)
        }
    }

    private func appliquerTitre(_ c: NSColor) {
        guard imagePosition != .imageOnly else { return }
        attributedTitle = NSAttributedString(string: libelle, attributes: [
            .foregroundColor: c,
            .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        ])
    }

    override func mouseEntered(with e: NSEvent) { peindre(survole: true) }
    override func mouseExited(with e: NSEvent)  { peindre(survole: false) }
}

final class Barre {

    struct Action {
        let titre: String
        let image: NSImage
        let teinte: NSColor
        let faire: () -> Void
    }

    private let panneau: NSPanel
    private let fond: NSVisualEffectView
    private let pile: NSStackView
    private var actions: [Action] = []

    private static let hauteur: CGFloat = 34
    private static let marge: CGFloat = 4
    private static let police = NSFont.systemFont(ofSize: 12.5, weight: .semibold)

    init() {
        panneau = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 120, height: Self.hauteur),
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        panneau.level = .floating
        panneau.isOpaque = false
        panneau.backgroundColor = .clear
        panneau.hasShadow = true
        panneau.becomesKeyOnlyIfNeeded = true
        panneau.hidesOnDeactivate = false
        panneau.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        fond = NSVisualEffectView()
        fond.material = .popover
        fond.blendingMode = .behindWindow
        fond.state = .active
        fond.wantsLayer = true
        fond.layer?.cornerRadius = 11
        fond.layer?.masksToBounds = true
        fond.layer?.borderWidth = 1

        pile = NSStackView()
        pile.orientation = .horizontal
        pile.spacing = 2
        pile.edgeInsets = NSEdgeInsets(top: Self.marge, left: Self.marge,
                                       bottom: Self.marge, right: Self.marge)
        pile.translatesAutoresizingMaskIntoConstraints = false
        fond.addSubview(pile)
        NSLayoutConstraint.activate([
            pile.leadingAnchor.constraint(equalTo: fond.leadingAnchor),
            pile.trailingAnchor.constraint(equalTo: fond.trailingAnchor),
            pile.topAnchor.constraint(equalTo: fond.topAnchor),
            pile.bottomAnchor.constraint(equalTo: fond.bottomAnchor)
        ])
        panneau.contentView = fond
    }

    private func bouton(_ a: Action, index: Int) -> BoutonAction {
        let v = Reglages.variante
        let b = BoutonAction()
        b.isBordered = false
        b.wantsLayer = true
        b.layer?.cornerRadius = 8
        b.image = a.image
        b.imageScaling = .scaleNone
        b.imagePosition = v == .compacte ? .imageOnly : .imageLeading
        b.teinte = a.teinte
        b.variante = v
        b.libelle = a.titre
        b.toolTip = a.titre
        b.tag = index
        b.target = self
        b.action = #selector(clic(_:))
        b.peindre(survole: false)

        let large: CGFloat = v == .compacte ? 32
            : max(78, a.titre.size(withAttributes: [.font: Self.police]).width + 44)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: large).isActive = true
        b.heightAnchor.constraint(equalToConstant: Self.hauteur - Self.marge * 2).isActive = true
        return b
    }

    @objc private func clic(_ envoyeur: NSButton) {
        guard actions.indices.contains(envoyeur.tag) else { return }
        actions[envoyeur.tag].faire()
    }

    func afficher(pres point: NSPoint, actions: [Action]) {
        guard !actions.isEmpty else { masquer(); return }
        self.actions = actions

        pile.arrangedSubviews.forEach { $0.removeFromSuperview() }
        actions.enumerated().forEach { pile.addArrangedSubview(bouton($1, index: $0)) }
        pile.layoutSubtreeIfNeeded()
        fond.layer?.borderColor = NSColor.separatorColor.cgColor

        let largeur = pile.fittingSize.width
        panneau.setContentSize(NSSize(width: largeur, height: Self.hauteur))

        var x = point.x + DISTANCE_CURSEUR
        var y = point.y - Self.hauteur - DISTANCE_CURSEUR
        if let ecran = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
                     ?? NSScreen.main {
            let c = ecran.visibleFrame
            if x + largeur > c.maxX - 6 { x = point.x - largeur - DISTANCE_CURSEUR }
            if y < c.minY + 6 { y = point.y + DISTANCE_CURSEUR }
            x = min(max(c.minX + 4, x), c.maxX - largeur - 4)
            y = min(max(c.minY + 4, y), c.maxY - Self.hauteur - 4)
        }
        panneau.setFrameOrigin(NSPoint(x: x, y: y))
        panneau.orderFrontRegardless()
    }

    func masquer() { panneau.orderOut(nil); actions = [] }
    var estVisible: Bool { panneau.isVisible }
    func contient(_ p: NSPoint) -> Bool { panneau.isVisible && panneau.frame.contains(p) }
    var cadre: NSRect { panneau.frame }
}

// ═════════════════════════════════════════════════════════════════
//  FENÊTRE D'HISTORIQUE
// ═════════════════════════════════════════════════════════════════
final class FenetreHistorique: NSObject, NSTableViewDataSource, NSTableViewDelegate {

    private var panneau: NSPanel?
    private var table: NSTableView?
    private var entrees: [Entree] = []
    private var surChoix: ((String) -> Void)?

    func afficher(pres point: NSPoint, choix: @escaping (String) -> Void) {
        surChoix = choix
        entrees = Historique.lire()
        fermer()

        let largeur: CGFloat = 350
        let lignes = max(entrees.count, 1)
        let hauteurListe = CGFloat(min(lignes, 7)) * 30
        let hauteur = hauteurListe + 76

        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: largeur, height: hauteur),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let fond = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: largeur, height: hauteur))
        fond.material = .popover
        fond.blendingMode = .behindWindow
        fond.state = .active
        fond.wantsLayer = true
        fond.layer?.cornerRadius = 12
        fond.layer?.masksToBounds = true
        fond.layer?.borderWidth = 1
        fond.layer?.borderColor = NSColor.separatorColor.cgColor

        let titre = NSTextField(labelWithString: "Historique")
        titre.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titre.frame = NSRect(x: 14, y: hauteur - 29, width: 160, height: 18)
        fond.addSubview(titre)

        let compte = NSTextField(labelWithString:
            entrees.isEmpty ? "vide" : "\(entrees.count) élément\(entrees.count > 1 ? "s" : "")")
        compte.font = .systemFont(ofSize: 10.5)
        compte.textColor = .secondaryLabelColor
        compte.alignment = .right
        compte.frame = NSRect(x: largeur - 114, y: hauteur - 28, width: 100, height: 16)
        fond.addSubview(compte)

        let defilement = NSScrollView(frame: NSRect(x: 6, y: 34, width: largeur - 12,
                                                    height: hauteurListe))
        defilement.hasVerticalScroller = true
        defilement.drawsBackground = false
        defilement.borderType = .noBorder

        let t = NSTableView()
        t.headerView = nil
        t.backgroundColor = .clear
        t.rowHeight = 30
        t.intercellSpacing = NSSize(width: 0, height: 0)
        t.dataSource = self
        t.delegate = self
        t.target = self
        t.action = #selector(choisir)
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        col.width = largeur - 26
        t.addTableColumn(col)
        defilement.documentView = t
        fond.addSubview(defilement)
        table = t

        let mention = NSTextField(labelWithString: "Effacé automatiquement après 24 h")
        mention.font = .systemFont(ofSize: 10)
        mention.textColor = .tertiaryLabelColor
        mention.frame = NSRect(x: 14, y: 11, width: 210, height: 15)
        fond.addSubview(mention)

        let vider = NSButton(title: "Vider", target: self, action: #selector(viderTout))
        vider.bezelStyle = .inline
        vider.controlSize = .small
        vider.frame = NSRect(x: largeur - 72, y: 8, width: 58, height: 20)
        fond.addSubview(vider)

        p.contentView = fond

        var x = point.x
        var y = point.y - hauteur - 6
        if let ecran = NSScreen.main {
            let c = ecran.visibleFrame
            x = min(max(c.minX + 4, x), c.maxX - largeur - 4)
            if y < c.minY + 4 { y = point.y + 6 }
        }
        p.setFrameOrigin(NSPoint(x: x, y: y))
        p.orderFrontRegardless()
        panneau = p
    }

    @objc private func choisir() {
        guard let t = table, t.clickedRow >= 0, t.clickedRow < entrees.count else { return }
        let texte = entrees[t.clickedRow].texte
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texte, forType: .string)
        fermer()
        surChoix?(texte)
    }

    @objc private func viderTout() {
        Historique.vider()
        entrees = []
        table?.reloadData()
        fermer()
    }

    func fermer() { panneau?.orderOut(nil); panneau = nil }
    var estVisible: Bool { panneau?.isVisible ?? false }
    func contient(_ p: NSPoint) -> Bool {
        guard let pa = panneau, pa.isVisible else { return false }
        return pa.frame.contains(p)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { entrees.isEmpty ? 1 : entrees.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let largeur = tableColumn?.width ?? 300
        let v = NSView(frame: NSRect(x: 0, y: 0, width: largeur, height: 30))

        if entrees.isEmpty {
            let l = NSTextField(labelWithString: "Rien de copié pour l'instant.")
            l.font = .systemFont(ofSize: 11.5)
            l.textColor = .secondaryLabelColor
            l.frame = NSRect(x: 10, y: 6, width: largeur - 20, height: 18)
            v.addSubview(l)
            return v
        }

        let e = entrees[row]
        let rang = NSTextField(labelWithString: "\(row + 1)")
        rang.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        rang.textColor = .tertiaryLabelColor
        rang.frame = NSRect(x: 9, y: 7, width: 18, height: 16)
        v.addSubview(rang)

        let apercu = e.texte.replacingOccurrences(of: "\n", with: " ")
                            .trimmingCharacters(in: .whitespaces)
        let texte = NSTextField(labelWithString: apercu)
        texte.font = .systemFont(ofSize: 11.5)
        texte.lineBreakMode = .byTruncatingTail
        texte.frame = NSRect(x: 29, y: 7, width: largeur - 112, height: 17)
        v.addSubview(texte)

        let age = NSTextField(labelWithString: Historique.age(e.quand))
        age.font = .systemFont(ofSize: 10)
        age.textColor = .tertiaryLabelColor
        age.alignment = .right
        age.frame = NSRect(x: largeur - 80, y: 7, width: 74, height: 16)
        v.addSubview(age)

        return v
    }
}

// ═════════════════════════════════════════════════════════════════
//  APPLICATION
// ═════════════════════════════════════════════════════════════════
final class Delegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let barre = Barre()
    private let histo = FenetreHistorique()
    private var statut: NSStatusItem?
    private var moniteurs: [Any] = []
    private var glisse = false
    private var depart: NSPoint?
    private var veille: Timer?
    private var attenteClavier: Timer?
    private var attenteFinder: Timer?
    private var noteCapture: String?

    private let ORANGE = NSColor(calibratedRed: 0.90, green: 0.60, blue: 0.13, alpha: 1)
    private let ROUGE  = NSColor(calibratedRed: 0.85, green: 0.38, blue: 0.18, alpha: 1)
    private let BLEU   = NSColor(calibratedRed: 0.20, green: 0.55, blue: 0.88, alpha: 1)
    private let ROSE   = NSColor(calibratedRed: 0.85, green: 0.34, blue: 0.42, alpha: 1)

    func applicationDidFinishLaunching(_ n: Notification) {
        installerMenu()
        _ = Historique.lire()        // purge les entrées de plus de 24 h

        if AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) {
            demarrer(); return
        }
        // On NE QUITTE PAS : macOS affiche sa demande de façon asynchrone,
        // et quitter la ferait disparaître avant qu'on ait pu répondre.
        majMenu(actif: false)
        veille = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] m in
            guard AXIsProcessTrusted() else { return }
            m.invalidate(); self?.veille = nil; self?.demarrer()
        }
    }

    private func demarrer() {
        guard moniteurs.isEmpty else { return }
        observer([.leftMouseDragged]) { [weak self] _ in
            guard let s = self else { return }
            if !s.glisse { s.depart = NSEvent.mouseLocation }
            s.glisse = true
        }
        observer([.leftMouseUp]) { [weak self] e in self?.relache(e) }
        observer([.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let s = self else { return }
            let p = NSEvent.mouseLocation
            if s.histo.estVisible && !s.histo.contient(p) { s.histo.fermer() }
            if s.barre.estVisible && !s.barre.contient(p) && !s.histo.contient(p) {
                s.barre.masquer()
            }
        }
        observer([.keyDown]) { [weak self] e in
            if e.keyCode == 53 { self?.barre.masquer(); self?.histo.fermer(); return }
            self?.toucheDeSelection(e)
        }
        majMenu(actif: true)
    }

    private func observer(_ masque: NSEvent.EventTypeMask, _ f: @escaping (NSEvent) -> Void) {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: masque, handler: f) {
            moniteurs.append(m)
        }
    }

    // ── Menu de la barre des menus ──
    private func installerMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Icone.copy(15)
        item.button?.toolTip = "CopieRapide"
        statut = item
        construireMenu()
    }

    private func construireMenu() {
        let menu = NSMenu()
        let etat = NSMenuItem(title: "…", action: nil, keyEquivalent: "")
        etat.isEnabled = false
        menu.addItem(etat)
        menu.addItem(.separator())

        for (titre, sel) in [("Capturer une zone", #selector(captureZone)),
                             ("Capturer tout l'écran", #selector(captureEcran)),
                             ("Capturer une fenêtre", #selector(captureFenetre))] {
            let i = NSMenuItem(title: titre, action: sel, keyEquivalent: "")
            i.target = self
            menu.addItem(i)
        }
        // On nomme la destination : sans ça, on entend le déclic sans
        // jamais savoir où l'image a atterri.
        let ouvrir = NSMenuItem(title: "Ouvrir le dossier des captures  (\(Capture.dossier.lastPathComponent))",
                                action: #selector(ouvrirDossierCaptures), keyEquivalent: "")
        ouvrir.target = self
        menu.addItem(ouvrir)
        menu.addItem(.separator())

        let apparence = NSMenuItem(title: "Apparence", action: nil, keyEquivalent: "")
        let sous = NSMenu()
        for v in Variante.allCases {
            let i = NSMenuItem(title: v.titre, action: #selector(changerVariante(_:)),
                               keyEquivalent: "")
            i.target = self
            i.representedObject = v.rawValue
            i.state = Reglages.variante == v ? .on : .off
            sous.addItem(i)
        }
        apparence.submenu = sous
        menu.addItem(apparence)
        menu.delegate = self

        let vider = NSMenuItem(title: "Vider l'historique", action: #selector(viderHisto),
                               keyEquivalent: "")
        vider.target = self
        menu.addItem(vider)

        let regl = NSMenuItem(title: "Réglages Accessibilité…", action: #selector(ouvrirReglages),
                              keyEquivalent: "")
        regl.target = self
        menu.addItem(regl)

        let auto = NSMenuItem(title: "Réglages Automatisation…",
                              action: #selector(ouvrirAutomatisation), keyEquivalent: "")
        auto.target = self
        menu.addItem(auto)
        menu.addItem(.separator())

        let q = NSMenuItem(title: "Quitter", action: #selector(quitter), keyEquivalent: "q")
        q.target = self
        menu.addItem(q)
        statut?.menu = menu
    }

    private func majMenu(actif: Bool) {
        statut?.button?.appearsDisabled = !actif
        statut?.button?.toolTip = actif
            ? "CopieRapide — actif"
            : "CopieRapide — en attente de l'autorisation Accessibilité"

        let ligne: String
        if !actif                    { ligne = "En attente de l'autorisation Accessibilité" }
        else if Fichiers.accesRefuse { ligne = "Finder refusé — voir Réglages Automatisation" }
        else if let n = noteCapture  { ligne = "Dernière capture : \(n)" }
        else                         { ligne = "Actif — texte, fichiers et dossiers" }
        statut?.menu?.items.first?.title = ligne
    }

    /// Le menu se remet à jour à l'ouverture : l'autorisation du Finder
    /// peut avoir changé, et la dernière capture aussi.
    func menuWillOpen(_ menu: NSMenu) { majMenu(actif: !moniteurs.isEmpty) }

    @objc private func changerVariante(_ item: NSMenuItem) {
        guard let brut = item.representedObject as? String,
              let v = Variante(rawValue: brut) else { return }
        Reglages.variante = v
        construireMenu()
        majMenu(actif: !moniteurs.isEmpty)
        barre.masquer()
    }

    @objc private func viderHisto() { Historique.vider() }

    @objc private func captureZone()    { capturer(.zone) }
    @objc private func captureEcran()   { capturer(.ecran) }
    @objc private func captureFenetre() { capturer(.fenetre) }

    // Un court délai laisse le menu se refermer avant que l'écran ne se
    // voile : sinon le menu apparaîtrait sur la capture.
    private func capturer(_ mode: Capture.Mode) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            Capture.lancer(mode) { [weak self] url in self?.apresCapture(url) }
        }
    }

    /// Sans ce retour, on entend le déclic et rien d'autre. La barre dit
    /// où le fichier est allé et propose de l'ouvrir ou de le coller.
    private func apresCapture(_ url: URL?) {
        guard let u = url else { return }
        noteCapture = u.lastPathComponent
        barre.afficher(pres: NSEvent.mouseLocation, actions: [
            .init(titre: "Voir", image: Icone.loupe(14), teinte: BLEU) { [weak self] in
                NSWorkspace.shared.activateFileViewerSelecting([u])
                self?.barre.masquer()
            },
            .init(titre: "Paste", image: Icone.paste(14), teinte: BLEU) { [weak self] in
                Selection.demanderCollage()
                self?.barre.masquer()
            }
        ])
    }

    @objc private func ouvrirDossierCaptures() {
        NSWorkspace.shared.open(Capture.dossier)
    }

    @objc func ouvrirAutomatisation() {
        if let u = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(u)
        }
    }

    @objc private func ouvrirReglages() {
        if let u = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(u)
        }
    }

    @objc private func quitter() { NSApp.terminate(nil) }

    // ── Gestes ──
    private static let flechesEtBornes: Set<UInt16> = [123, 124, 125, 126, 115, 119, 116, 121]

    private func toucheDeSelection(_ e: NSEvent) {
        // On écoute l'appui et non le relâchement : avec Cmd enfoncée,
        // macOS ne délivre pas systématiquement le relâchement.
        let tout = e.modifierFlags.contains(.command) && e.keyCode == 0x00
        let etendu = e.modifierFlags.contains(.shift) && Self.flechesEtBornes.contains(e.keyCode)
        guard tout || etendu else { return }

        attenteClavier?.invalidate()

        // Cmd+A dans le Finder sélectionne des fichiers, pas du texte.
        if Fichiers.finderDevant {
            attenteClavier = Timer.scheduledTimer(withTimeInterval: 0.30, repeats: false) { [weak self] _ in
                self?.proposerFichiers(NSEvent.mouseLocation)
            }
            return
        }

        attenteClavier = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            guard let s = self, let r = Selection.courante(gesteFranc: true) else {
                self?.barre.masquer(); return
            }
            s.barre.afficher(pres: NSEvent.mouseLocation, actions: s.actionsSelection(r))
        }
    }

    private func relache(_ e: NSEvent) {
        let position = NSEvent.mouseLocation
        let doubleClic = e.clickCount >= 2
        var franc = false
        if glisse, let d = depart {
            // Sélectionner un mot court ou un lien ne déplace la souris
            // que de quelques pixels.
            franc = hypot(position.x - d.x, position.y - d.y) > 4
        }
        glisse = false; depart = nil

        // Le Finder d'abord : un simple clic y sélectionne un fichier, et
        // aucune lecture de texte ne verra jamais ça.
        if Fichiers.finderDevant {
            attenteFinder?.invalidate()
            // Un double-clic ouvre le fichier : il ne demande pas la barre.
            // On attend donc de savoir si un second clic arrive.
            guard !doubleClic else { barre.masquer(); return }
            attenteFinder = Timer.scheduledTimer(withTimeInterval: 0.28, repeats: false) {
                [weak self] _ in self?.proposerFichiers(position)
            }
            return
        }

        guard franc || doubleClic else { proposerCollage(position); return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let s = self, let r = Selection.courante(gesteFranc: true) else {
                self?.barre.masquer(); return
            }
            s.barre.afficher(pres: position, actions: s.actionsSelection(r))
        }
    }

    /// Le presse-papier après un Cmd+C simulé : on le relit pour garder
    /// l'historique à jour même quand macOS ne nous donne pas le texte.
    private func memoriserApresCoup() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            if let t = NSPasteboard.general.string(forType: .string) { Historique.ajouter(t) }
        }
    }

    private func actionsSelection(_ r: Selection.Resultat) -> [Barre.Action] {
        var liste: [Barre.Action] = [
            .init(titre: "Copy", image: Icone.copy(14), teinte: ORANGE) { [weak self] in
                switch r {
                case .texte(let t):
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(t, forType: .string)
                    Historique.ajouter(t)
                case .demanderALApplication:
                    Selection.demanderCopie()
                    self?.memoriserApresCoup()
                }
                self?.barre.masquer()
            }
        ]

        // Couper et supprimer n'ont de sens que là où le texte est modifiable.
        if Selection.zoneModifiable() {
            liste.append(.init(titre: "Cut", image: Icone.cut(14), teinte: ROUGE) { [weak self] in
                Selection.demanderCoupe()
                self?.memoriserApresCoup()
                self?.barre.masquer()
            })
            liste.append(.init(titre: "Delete", image: Icone.trash(14), teinte: ROSE) { [weak self] in
                Selection.demanderSuppression()
                self?.barre.masquer()
            })
        }
        return liste
    }

    // ── Fichiers, dossiers et photos du Finder ──
    private func proposerFichiers(_ position: NSPoint) {
        guard let choisis = Fichiers.selection() else {
            // Le Finder ne répond pas. On le dit et on offre le réglage,
            // au lieu de faire semblant que rien n'est sélectionné.
            barre.afficher(pres: position, actions: [
                .init(titre: "Autoriser le Finder", image: Icone.loupe(14),
                      teinte: ROUGE) { [weak self] in
                    self?.ouvrirAutomatisation()
                    self?.barre.masquer()
                }
            ])
            return
        }

        guard !choisis.isEmpty else {
            // Rien de sélectionné : la barre reste utile s'il y a des
            // fichiers en attente dans le presse-papier.
            guard Fichiers.pressePapierPorteDesFichiers else { barre.masquer(); return }
            barre.afficher(pres: position, actions: [collageFichiers()])
            return
        }

        var liste: [Barre.Action] = [
            .init(titre: "Copy", image: Icone.copy(14), teinte: ORANGE) { [weak self] in
                Fichiers.copier(); self?.barre.masquer()
            },
            .init(titre: "Cut", image: Icone.cut(14), teinte: ROUGE) { [weak self] in
                Fichiers.couper(); self?.barre.masquer()
            }
        ]
        if Fichiers.pressePapierPorteDesFichiers { liste.append(collageFichiers()) }
        liste.append(.init(titre: "Delete", image: Icone.trash(14), teinte: ROSE) { [weak self] in
            Fichiers.mettreALaCorbeille(); self?.barre.masquer()
        })
        barre.afficher(pres: position, actions: liste)
    }

    /// Après un Cut, le collage déplace au lieu de dupliquer : le libellé
    /// le dit, sinon on ne saurait pas ce que le bouton va faire.
    private func collageFichiers() -> Barre.Action {
        let deplace = Fichiers.enModeDeplacement
        return .init(titre: deplace ? "Move here" : "Paste",
                     image: Icone.paste(14), teinte: BLEU) { [weak self] in
            Fichiers.coller(); self?.barre.masquer()
        }
    }

    private func proposerCollage(_ position: NSPoint) {
        let riche = NSPasteboard.general.string(forType: .string) != nil
        guard riche || !Historique.lire().isEmpty else { barre.masquer(); return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
            guard let s = self, Selection.zoneModifiable() else { self?.barre.masquer(); return }

            var actions: [Barre.Action] = [
                .init(titre: "Paste", image: Icone.paste(14), teinte: s.BLEU) { [weak s] in
                    Selection.demanderCollage()
                    s?.barre.masquer()
                }
            ]
            if HISTORIQUE_ACTIF && !Historique.lire().isEmpty {
                actions.append(.init(titre: "Historique", image: Icone.clock(14),
                                     teinte: s.BLEU) { [weak s] in
                    guard let s = s else { return }
                    let sous = NSPoint(x: s.barre.cadre.minX, y: s.barre.cadre.minY)
                    s.barre.masquer()
                    s.histo.afficher(pres: sous) { _ in
                        // Le texte choisi est déjà dans le presse-papier :
                        // il ne reste qu'à demander le collage.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            Selection.demanderCollage()
                        }
                    }
                })
            }
            s.barre.afficher(pres: position, actions: actions)
        }
    }

    func applicationWillTerminate(_ n: Notification) {
        moniteurs.forEach { NSEvent.removeMonitor($0) }
        moniteurs.removeAll()
        veille?.invalidate()
        attenteClavier?.invalidate()
        attenteFinder?.invalidate()
    }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
