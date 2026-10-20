import AppKit
import KostKern
import Observation
import SwiftUI
import UniformTypeIdentifiers

enum Bereich: String, CaseIterable, Identifiable, Hashable {
    case tagebuch, rechner, lebensmittel, auswertung, gewicht, profil

    var id: String { rawValue }

    var name: String {
        switch self {
        case .tagebuch: "Tagebuch"
        case .rechner: "Rechner"
        case .lebensmittel: "Lebensmittel"
        case .auswertung: "Auswertung"
        case .gewicht: "Gewicht"
        case .profil: "Profil & Ziele"
        }
    }

    var symbol: String {
        switch self {
        case .tagebuch: "book.closed"
        case .rechner: "sparkles"
        case .lebensmittel: "basket"
        case .auswertung: "chart.bar"
        case .gewicht: "scalemass"
        case .profil: "person.crop.circle"
        }
    }
}

/// Wohin ein neuer Eintrag soll.
struct Eintragsziel: Equatable, Identifiable {
    var tag: Tag
    var mahlzeit: Mahlzeit
    var id: String { "\(tag.schluessel)-\(mahlzeit.rawValue)" }
}

/// Was gerade angezeigt wird – überlebt den Wechsel zwischen den Seiten, nicht aber den Neustart.
@MainActor @Observable
final class Sitzung {
    var bereich: Bereich = .tagebuch
    /// Der im Tagebuch aufgeschlagene Tag.
    var tag: Tag = .heute
    /// Das Rechnerblatt der Seitenleiste behält Eingabe und Ergebnis, wenn man zwischendurch woanders hinschaut.
    let rechner = Rechnermodell()
    let chatgpt = ChatGPTKonto()

    func zeige(_ tag: Tag) {
        self.tag = tag
        bereich = .tagebuch
    }

    /// Geschätzt wird mit dem ChatGPT-Abo – ohne Anmeldung geht es nicht.
    var kannSchaetzen: Bool { chatgpt.istAngemeldet }

    func schaetzfunktion(_ einstellungen: Einstellungen) -> Rechnermodell.Schaetzfunktion? {
        guard chatgpt.istAngemeldet else { return nil }
        let zugang = chatgpt.zugang
        let gewuenscht = einstellungen.chatgptModell
        let konto = chatgpt
        return { text, bilder in
            guard let modell = await konto.modell(gewuenscht: gewuenscht) else {
                throw ChatGPTFehler.antwortFehler("Für dein Konto ist kein Modell verfügbar.")
            }
            return try await ChatGPTSchaetzer(zugang: zugang, modell: modell).schaetze(text: text, bilder: bilder)
        }
    }
}

/// Die ChatGPT-Anmeldung, wie die Oberfläche sie sieht.
@MainActor @Observable
final class ChatGPTKonto {
    enum Zustand: Equatable {
        case abgemeldet, meldetAn
        case angemeldet(String)
        case fehler(String)
    }

    let zugang = ChatGPTZugang()
    var zustand: Zustand = .abgemeldet
    var modelle: [String] = []
    /// Ergebnis der Tempomessung – „Automatisch“ nimmt dieses Modell.
    var schnellstes: String?
    @ObservationIgnored private var anmeldung: Task<Void, Never>?
    @ObservationIgnored private var messung: Task<Void, Never>?

    init() {
        Task { await ladeStand() }
    }

    var istAngemeldet: Bool {
        if case .angemeldet = zustand { return true }
        return false
    }

    func ladeStand() async {
        if let email = await zugang.email {
            zustand = .angemeldet(email.isEmpty ? "ChatGPT" : email)
            await ladeModelle()
        }
    }

    func anmelden() {
        anmeldung?.cancel()
        zustand = .meldetAn
        anmeldung = Task {
            do {
                let sitzung = try await zugang.anmelden { adresse in
                    DispatchQueue.main.async { NSWorkspace.shared.open(adresse) }
                }
                zustand = .angemeldet(sitzung.email.isEmpty ? "ChatGPT" : sitzung.email)
                // Nach dem Browser wieder nach vorn
                NSApp.activate(ignoringOtherApps: true)
                await ladeModelle()
            } catch {
                if Task.isCancelled || (error as? ChatGPTFehler) == .abgebrochen {
                    zustand = .abgemeldet
                } else {
                    zustand = .fehler(error.localizedDescription)
                }
            }
        }
    }

    func brichAb() {
        anmeldung?.cancel()
        zustand = .abgemeldet
    }

    func abmelden() {
        Task {
            await zugang.abmelden()
            zustand = .abgemeldet
            modelle = []
        }
    }

    func ladeModelle() async {
        if let liste = try? await zugang.modelle(), !liste.isEmpty { modelle = liste }
        miss()
    }

    /// Misst im Hintergrund, welches Modell am schnellsten schätzt (gespeichert, also meist sofort fertig).
    func miss(neu: Bool = false) {
        guard !modelle.isEmpty, messung == nil || neu else { return }
        let liste = modelle
        messung = Task {
            schnellstes = await zugang.schnellstesModell(aus: liste, neuMessen: neu) ?? schnellstes
            messung = nil
        }
    }

    func modell(gewuenscht: String) async -> String? {
        if modelle.isEmpty { await ladeModelle() }
        if !gewuenscht.isEmpty, modelle.isEmpty || modelle.contains(gewuenscht) { return gewuenscht }
        return schnellstes ?? ChatGPTZugang.vorgabemodell(aus: modelle)
    }

}

/// Zustand eines Rechnerblatts: Eingabe, laufende Schätzung, bearbeitbares Ergebnis.
@MainActor @Observable
final class Rechnermodell {
    struct Zeile: Identifiable, Equatable {
        let id: UUID
        var gewaehlt = true
        var name: String
        var menge: Double
        let einheit: String
        /// Die ursprünglich geschätzte Menge und ihre Werte – eine geänderte Menge rechnet von hier aus um.
        let basisMenge: Double
        let basisWerte: Naehrwerte

        var werte: Naehrwerte {
            basisMenge > 0 ? basisWerte.mal(menge / basisMenge) : basisWerte
        }
    }

    struct Foto: Identifiable {
        let id = UUID()
        let anhang: Bildanhang
        let vorschau: NSImage
    }

    enum Zustand: Equatable {
        case bereit, laeuft, fertig
        case fehler(String)
    }

    static let hoechstensFotos = 4

    var text = ""
    var fotos: [Foto] = []
    var zustand: Zustand = .bereit
    var zeilen: [Zeile] = []
    var annahmen = ""
    var sicherheit: Sicherheit = .mittel
    var mahlzeit: Mahlzeit = .passend()
    var tag: Tag = .heute
    /// Kurze Rückmeldung nach dem Übernehmen.
    var bestaetigung: String?

    @ObservationIgnored private var aufgabe: Task<Void, Never>?

    var kannSchaetzen: Bool {
        zustand != .laeuft && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !fotos.isEmpty)
    }

    var gewaehlte: [Zeile] { zeilen.filter(\.gewaehlt) }
    var summe: Naehrwerte { gewaehlte.reduce(.null) { $0 + $1.werte } }

    typealias Schaetzfunktion = (String, [Bildanhang]) async throws -> Schaetzung

    func schaetze(mit schaetzfunktion: @escaping Schaetzfunktion) {
        guard kannSchaetzen else { return }
        aufgabe?.cancel()
        zustand = .laeuft
        bestaetigung = nil
        let eingabe = text
        let bilder = fotos.map(\.anhang)
        aufgabe = Task { [weak self] in
            do {
                let ergebnis = try await schaetzfunktion(eingabe, bilder)
                guard !Task.isCancelled else { return }
                self?.zeige(ergebnis)
            } catch is CancellationError {
                // abgebrochen – der Zustand wurde schon in `brichAb` zurückgesetzt
            } catch {
                guard !Task.isCancelled else { return }
                self?.zustand = .fehler(error.localizedDescription)
            }
        }
    }

    func zeige(_ schaetzung: Schaetzung) {
        zeilen = schaetzung.posten.map {
            Zeile(id: $0.id, name: $0.name, menge: $0.menge, einheit: $0.einheit, basisMenge: $0.menge, basisWerte: $0.naehrwerte)
        }
        annahmen = schaetzung.annahmen
        sicherheit = schaetzung.sicherheit
        zustand = .fertig
    }

    func brichAb() {
        aufgabe?.cancel()
        aufgabe = nil
        if zustand == .laeuft { zustand = zeilen.isEmpty ? .bereit : .fertig }
    }

    /// Schreibt die angehakten Posten ins Tagebuch und räumt das Blatt für die nächste Eingabe.
    @discardableResult
    func uebernimm(in speicher: Speicher) -> Int {
        let jetzt = Date()
        let eintraege = gewaehlte.enumerated().map { stelle, zeile in
            Eintrag(
                tag: tag, mahlzeit: mahlzeit, name: zeile.name, menge: zeile.menge, einheit: zeile.einheit,
                naehrwerte: zeile.werte, quelle: .chatgpt, erstellt: jetzt.addingTimeInterval(Double(stelle) * 0.001)
            )
        }
        guard !eintraege.isEmpty else { return 0 }
        speicher.fuegeHinzu(eintraege)
        let anzahl = eintraege.count
        let wohin = "\(mahlzeit.name), \(tag.kurztitel)"
        leere()
        bestaetigung = anzahl == 1 ? "1 Eintrag hinzugefügt – \(wohin)" : "\(anzahl) Einträge hinzugefügt – \(wohin)"
        return anzahl
    }

    func leere() {
        aufgabe?.cancel()
        text = ""
        fotos = []
        zeilen = []
        annahmen = ""
        zustand = .bereit
        bestaetigung = nil
    }

    // MARK: Fotos

    @discardableResult
    func fuegeFotoHinzu(datei: URL) -> Bool {
        guard let jpeg = Bildaufbereitung.jpeg(ausDatei: datei) else { return false }
        return fuegeFotoHinzu(jpeg: jpeg)
    }

    @discardableResult
    func fuegeFotoHinzu(daten: Data) -> Bool {
        guard let jpeg = Bildaufbereitung.jpeg(aus: daten) else { return false }
        return fuegeFotoHinzu(jpeg: jpeg)
    }

    private func fuegeFotoHinzu(jpeg: Data) -> Bool {
        guard fotos.count < Self.hoechstensFotos, let vorschau = NSImage(data: jpeg) else { return false }
        fotos.append(Foto(anhang: Bildanhang(jpeg: jpeg), vorschau: vorschau))
        return true
    }

    func entferneFoto(_ id: UUID) {
        fotos.removeAll { $0.id == id }
    }

    func waehleFotos() {
        let dialog = NSOpenPanel()
        dialog.allowedContentTypes = [.image]
        dialog.allowsMultipleSelection = true
        dialog.message = "Fotos der Mahlzeit auswählen"
        dialog.prompt = "Hinzufügen"
        guard dialog.runModal() == .OK else { return }
        for datei in dialog.urls { fuegeFotoHinzu(datei: datei) }
    }
}
