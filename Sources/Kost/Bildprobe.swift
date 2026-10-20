import AppKit
import KostKern
import SwiftUI

/// Zeichnet die Seiten der App mit Beispieldaten in PNG-Dateien.
/// Gedacht zum Prüfen der Gestaltung: `Kost --bildprobe <Ordner>`.
@MainActor
enum Bildprobe {
    static func starte(ordner: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let ziel = URL(fileURLWithPath: ordner, isDirectory: true)
        try? FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        Task { @MainActor in
            await zeichneAlles(in: ziel)
            exit(0)
        }
        app.run()
    }

    private static func zeichneAlles(in ordner: URL) async {
        for dunkel in [false, true] {
            let zusatz = dunkel ? "-dunkel" : ""
            let speicher = Speicher(nurImSpeicher: Beispieldaten.bestand())
            let sitzung = Sitzung()

            func seite<V: View>(_ name: String, breite: CGFloat = 960, hoehe: CGFloat, @ViewBuilder _ inhalt: () -> V) async {
                await zeichne(inhalt().environment(speicher).environment(sitzung), name: name + zusatz, breite: breite, hoehe: hoehe, dunkel: dunkel, in: ordner)
            }

            await seite("01-tagebuch", hoehe: 1180) { TagebuchAnsicht() }

            sitzung.rechner.text = "2 Scheiben Vollkornbrot mit Frischkäse und Gurke, dazu ein Glas Orangensaft"
            sitzung.rechner.zeige(Beispieldaten.schaetzung)
            await seite("02-rechner-ergebnis", hoehe: 760) { RechnerAnsicht() }
            sitzung.rechner.leere()
            await seite("03-rechner-leer", hoehe: 520) { RechnerAnsicht() }

            await seite("04-lebensmittel", hoehe: 900) { LebensmittelAnsicht() }
            await seite("05-auswertung", hoehe: 1120) { AuswertungAnsicht() }
            await seite("06-gewicht", hoehe: 1180) { GewichtAnsicht() }
            await seite("07-profil", hoehe: 1040) { ProfilAnsicht() }

            let ziel = Eintragsziel(tag: .heute, mahlzeit: .abendessen)
            await seite("08-eintragen", breite: 780, hoehe: 640) { Eintragen(ziel: ziel).background(Farbe.flaeche) }
            if let eintrag = speicher.daten.eintraege(am: .heute).first {
                await seite("09-eintrag-bearbeiten", breite: 520, hoehe: 470) { EintragBearbeiten(eintrag: eintrag).background(Farbe.flaeche) }
            }
            await seite("10-einstellungen", breite: 440, hoehe: 520) { EinstellungenAnsicht().background(Farbe.flaeche) }
            await seite("11-fenster", breite: 1120, hoehe: 800) { Hauptfenster() }

            for schritt in [0, 2, 3, 4, 5] {
                await seite("12-einrichtung-\(schritt + 1)", breite: 940, hoehe: 640) { Einrichtung(probeschritt: schritt) }
            }

            // Leerer Bestand: So sieht die App direkt nach der Einrichtung aus.
            let frisch = Speicher(nurImSpeicher: Datenbestand(profil: Beispieldaten.bestand().profil))
            await zeichne(TagebuchAnsicht().environment(frisch).environment(Sitzung()), name: "13-tagebuch-leer" + zusatz, breite: 960, hoehe: 760, dunkel: dunkel, in: ordner)
        }
    }

    private static func zeichne<V: View>(_ ansicht: V, name: String, breite: CGFloat, hoehe: CGFloat, dunkel: Bool, in ordner: URL) async {
        let rahmen = NSRect(x: 0, y: 0, width: breite, height: hoehe)
        let traeger = NSHostingView(rootView: ansicht.frame(width: breite, height: hoehe))
        traeger.frame = rahmen
        let fenster = NSWindow(contentRect: rahmen, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        fenster.titlebarAppearsTransparent = true
        fenster.titleVisibility = .hidden
        fenster.appearance = NSAppearance(named: dunkel ? .darkAqua : .aqua)
        fenster.contentView = traeger
        // Weit außerhalb jedes Bildschirms: SwiftUI zeichnet Diagramme und Listen erst in einem geöffneten Fenster.
        fenster.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        fenster.orderFrontRegardless()
        traeger.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(450))

        defer { fenster.orderOut(nil) }
        guard let bild = traeger.bitmapImageRepForCachingDisplay(in: traeger.bounds) else { return }
        traeger.cacheDisplay(in: traeger.bounds, to: bild)
        guard let png = bild.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: ordner.appendingPathComponent(name + ".png"))
    }
}
