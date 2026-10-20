import AppKit
import Foundation
import KostKern
import Observation

/// Der Datenbestand der laufenden App. Jede Änderung geht durch eine der Methoden hier und wird danach gesichert.
@MainActor @Observable
final class Speicher {
    private(set) var daten: Datenbestand
    /// Meldung für den Nutzer, etwa wenn Laden oder Speichern scheiterte.
    var hinweis: String?

    @ObservationIgnored private let datei: URL?
    @ObservationIgnored private var sicherung: Task<Void, Never>?

    /// Arbeitet auf der Datei im Benutzerordner.
    init(datei: URL) {
        let geladen = Ablage.lade(datei)
        self.daten = geladen.daten
        self.hinweis = geladen.hinweis
        self.datei = datei
        // Änderungen werden kurz gesammelt; beim Beenden muss der letzte Stand trotzdem auf die Platte.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sichereSofort() }
        }
    }

    /// Nur im Arbeitsspeicher – für die Bildprobe mit Beispieldaten.
    init(nurImSpeicher daten: Datenbestand) {
        self.daten = daten
        self.datei = nil
    }

    // MARK: Abgeleitetes

    var profil: Profil? { daten.profil }
    var einstellungen: Einstellungen { daten.einstellungen }

    var bedarf: Bedarf? {
        daten.profil.map { Bedarfsrechner.berechne($0, imJahr: Calendar.current.component(.year, from: Date())) }
    }

    var ziele: Tagesziele { daten.eigeneZiele ?? bedarf?.ziele ?? .referenz }
    var zieleFolgenProfil: Bool { daten.eigeneZiele == nil }

    // MARK: Profil und Ziele

    func richteEin(_ profil: Profil) {
        daten.profil = profil
        setzeGewicht(profil.gewichtKg, am: .heute)
    }

    func aendere(profil: Profil) {
        let gewichtNeu = profil.gewichtKg != daten.profil?.gewichtKg
        daten.profil = profil
        // Ein im Profil geändertes Gewicht ist eine Wägung von heute.
        if gewichtNeu { setzeGewicht(profil.gewichtKg, am: .heute) } else { geaendert() }
    }

    func setze(eigeneZiele: Tagesziele?) {
        daten.eigeneZiele = eigeneZiele
        geaendert()
    }

    func aendere(einstellungen: Einstellungen) {
        daten.einstellungen = einstellungen
        geaendert()
    }

    // MARK: Tagebuch

    func fuegeHinzu(_ eintraege: [Eintrag]) {
        daten.eintraege.append(contentsOf: eintraege)
        geaendert()
    }

    func aendere(eintrag: Eintrag) {
        guard let stelle = daten.eintraege.firstIndex(where: { $0.id == eintrag.id }) else { return }
        daten.eintraege[stelle] = eintrag
        geaendert()
    }

    func loesche(eintrag id: UUID) {
        daten.eintraege.removeAll { $0.id == id }
        geaendert()
    }

    func dupliziere(_ eintrag: Eintrag, nach tag: Tag, mahlzeit: Mahlzeit) {
        var kopie = eintrag
        kopie.id = UUID()
        kopie.tag = tag
        kopie.mahlzeit = mahlzeit
        kopie.erstellt = Date()
        fuegeHinzu([kopie])
    }

    /// Übernimmt eine ganze Mahlzeit von einem anderen Tag. Gibt zurück, wie viele Einträge kopiert wurden.
    @discardableResult
    func kopiere(_ mahlzeit: Mahlzeit, von quelle: Tag, nach ziel: Tag) -> Int {
        let vorlage = daten.eintraege(am: quelle, mahlzeit: mahlzeit)
        let jetzt = Date()
        let kopien = vorlage.enumerated().map { stelle, eintrag in
            var kopie = eintrag
            kopie.id = UUID()
            kopie.tag = ziel
            // Reihenfolge der Vorlage erhalten
            kopie.erstellt = jetzt.addingTimeInterval(Double(stelle) * 0.001)
            return kopie
        }
        if !kopien.isEmpty { fuegeHinzu(kopien) }
        return kopien.count
    }

    // MARK: Lebensmittel

    func merke(_ lebensmittel: Lebensmittel) {
        if let stelle = daten.lebensmittel.firstIndex(where: { $0.id == lebensmittel.id }) {
            daten.lebensmittel[stelle] = lebensmittel
        } else {
            daten.lebensmittel.append(lebensmittel)
        }
        geaendert()
    }

    func loesche(lebensmittel id: UUID) {
        daten.lebensmittel.removeAll { $0.id == id }
        geaendert()
    }

    func schalteFavorit(_ id: UUID) {
        guard let stelle = daten.lebensmittel.firstIndex(where: { $0.id == id }) else { return }
        daten.lebensmittel[stelle].favorit.toggle()
        geaendert()
    }

    func istGemerkt(name: String, marke: String) -> Bool {
        daten.lebensmittel.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.marke.caseInsensitiveCompare(marke) == .orderedSame }
    }

    /// Trägt ein Lebensmittel mit der verzehrten Menge ins Tagebuch ein und merkt sich die Nutzung für die Sortierung.
    func trageEin(_ lebensmittel: Lebensmittel, menge: Double, tag: Tag, mahlzeit: Mahlzeit) {
        if let stelle = daten.lebensmittel.firstIndex(where: { $0.id == lebensmittel.id }) {
            daten.lebensmittel[stelle].genutzt += 1
            daten.lebensmittel[stelle].zuletzt = Date()
        }
        fuegeHinzu([Eintrag(
            tag: tag, mahlzeit: mahlzeit, name: lebensmittel.anzeigename, menge: menge, einheit: lebensmittel.einheit,
            naehrwerte: lebensmittel.werte(fuer: menge),
            quelle: lebensmittel.quelle == .produktdatenbank ? .produktdatenbank : .vorrat
        )])
    }

    /// Favoriten zuerst, danach die zuletzt benutzten, dann alphabetisch.
    func lebensmittelSortiert(suche: String = "") -> [Lebensmittel] {
        let begriff = suche.trimmingCharacters(in: .whitespaces)
        return daten.lebensmittel
            .filter { begriff.isEmpty || $0.anzeigename.localizedCaseInsensitiveContains(begriff) }
            .sorted { a, b in
                if a.favorit != b.favorit { return a.favorit }
                if a.zuletzt != b.zuletzt { return (a.zuletzt ?? .distantPast) > (b.zuletzt ?? .distantPast) }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }

    // MARK: Wasser und Gewicht

    func aendereWasser(um ml: Int, am tag: Tag) {
        let neu = max(0, daten.wasser(am: tag) + ml)
        daten.wasser[tag.schluessel] = neu == 0 ? nil : neu
        geaendert()
    }

    func setzeGewicht(_ kg: Double, am tag: Tag) {
        daten.gewichte.removeAll { $0.tag == tag }
        daten.gewichte.append(Gewichtseintrag(tag: tag, kg: kg))
        daten.gewichte.sort { $0.tag < $1.tag }
        uebernimmLetztesGewicht()
        geaendert()
    }

    func loescheGewicht(am tag: Tag) {
        daten.gewichte.removeAll { $0.tag == tag }
        uebernimmLetztesGewicht()
        geaendert()
    }

    /// Das Profil rechnet immer mit der jüngsten Wägung – so wandern die Ziele mit dem Gewicht mit.
    private func uebernimmLetztesGewicht() {
        if let letztes = daten.gewichte.last { daten.profil?.gewichtKg = letztes.kg }
    }

    // MARK: Alles

    func loescheAlles() {
        daten = Datenbestand()
        geaendert()
    }

    // MARK: Sichern

    private func geaendert() {
        guard datei != nil else { return }
        sicherung?.cancel()
        sicherung = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.sichereSofort()
        }
    }

    func sichereSofort() {
        guard let datei else { return }
        sicherung?.cancel()
        do {
            try Ablage.sichere(daten, in: datei)
        } catch {
            hinweis = "Speichern fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
