import Foundation

public struct Tagesbilanz: Identifiable, Equatable, Sendable {
    public let tag: Tag
    public let summe: Naehrwerte
    public let wasserMl: Int
    public let anzahl: Int
    public var id: Tag { tag }
    /// Ein Tag zählt als erfasst, sobald etwas gegessen eingetragen wurde.
    public var erfasst: Bool { anzahl > 0 }
}

public struct Zeitraum: Equatable, Sendable {
    public let tage: [Tagesbilanz]
    public var erfassteTage: Int { tage.filter(\.erfasst).count }

    /// Durchschnitt über die erfassten Tage – leere Tage würden den Schnitt sonst nach unten ziehen.
    public var schnitt: Naehrwerte {
        let erfasst = tage.filter(\.erfasst)
        guard !erfasst.isEmpty else { return .null }
        return erfasst.reduce(Naehrwerte.null) { $0 + $1.summe }.mal(1 / Double(erfasst.count))
    }

    public var wasserSchnitt: Int {
        let mitWasser = tage.filter { $0.wasserMl > 0 }
        guard !mitWasser.isEmpty else { return 0 }
        return mitWasser.reduce(0) { $0 + $1.wasserMl } / mitWasser.count
    }

    /// Anteil der Makros an der Energie des Durchschnittstages (Summe 1, oder alle 0 ohne Daten).
    public var energieanteile: (eiweiss: Double, kohlenhydrate: Double, fett: Double) {
        Self.energieanteile(schnitt)
    }

    public static func energieanteile(_ w: Naehrwerte) -> (eiweiss: Double, kohlenhydrate: Double, fett: Double) {
        let e = w.eiweiss * 4, k = w.kohlenhydrate * 4, f = w.fett * 9
        let gesamt = e + k + f
        guard gesamt > 0 else { return (0, 0, 0) }
        return (e / gesamt, k / gesamt, f / gesamt)
    }
}

public extension Datenbestand {
    func eintraege(am tag: Tag) -> [Eintrag] {
        eintraege.filter { $0.tag == tag }.sorted { $0.erstellt < $1.erstellt }
    }

    func eintraege(am tag: Tag, mahlzeit: Mahlzeit) -> [Eintrag] {
        eintraege(am: tag).filter { $0.mahlzeit == mahlzeit }
    }

    func summe(am tag: Tag) -> Naehrwerte {
        eintraege.lazy.filter { $0.tag == tag }.reduce(Naehrwerte.null) { $0 + $1.naehrwerte }
    }

    func wasser(am tag: Tag) -> Int { wasser[tag.schluessel] ?? 0 }

    /// Bilanz für jeden Tag von `von` bis `bis` (einschließlich), auch für leere Tage.
    func zeitraum(von: Tag, bis: Tag, kalender: Calendar = .current) -> Zeitraum {
        guard von <= bis else { return Zeitraum(tage: []) }
        var summen: [Tag: (Naehrwerte, Int)] = [:]
        for eintrag in eintraege where eintrag.tag >= von && eintrag.tag <= bis {
            let bisher = summen[eintrag.tag] ?? (.null, 0)
            summen[eintrag.tag] = (bisher.0 + eintrag.naehrwerte, bisher.1 + 1)
        }
        var tage: [Tagesbilanz] = []
        var lauf = von
        while lauf <= bis {
            let (summe, anzahl) = summen[lauf] ?? (.null, 0)
            tage.append(Tagesbilanz(tag: lauf, summe: summe, wasserMl: wasser(am: lauf), anzahl: anzahl))
            lauf = lauf.verschoben(um: 1, kalender: kalender)
        }
        return Zeitraum(tage: tage)
    }

    /// Wie viele Tage in Folge bis `tag` etwas eingetragen wurde. Ein noch leerer heutiger Tag bricht die Serie nicht.
    func serie(bis tag: Tag, kalender: Calendar = .current) -> Int {
        let erfasst = Set(eintraege.map(\.tag))
        var lauf = erfasst.contains(tag) ? tag : tag.verschoben(um: -1, kalender: kalender)
        var laenge = 0
        while erfasst.contains(lauf) {
            laenge += 1
            lauf = lauf.verschoben(um: -1, kalender: kalender)
        }
        return laenge
    }

    /// Zuletzt gegessene Lebensmittel ohne Doppelte – für das schnelle Wiedereintragen.
    func zuletztGegessen(hoechstens: Int = 12) -> [Eintrag] {
        var gesehen = Set<String>()
        var ergebnis: [Eintrag] = []
        for eintrag in eintraege.sorted(by: { $0.erstellt > $1.erstellt }) {
            let schluessel = eintrag.name.lowercased()
            guard gesehen.insert(schluessel).inserted else { continue }
            ergebnis.append(eintrag)
            if ergebnis.count >= hoechstens { break }
        }
        return ergebnis
    }
}

public enum Gewichtstrend {
    /// Steigung einer Ausgleichsgeraden durch die Wägungen der letzten `tage` Tage, in kg pro Woche.
    /// Einzelne Wägungen schwanken durch Wasser um ein bis zwei Kilo; die Gerade glättet das.
    public static func kgProWoche(_ eintraege: [Gewichtseintrag], bis: Tag, tage: Int = 28, kalender: Calendar = .current) -> Double? {
        let start = bis.verschoben(um: -tage, kalender: kalender)
        let punkte = eintraege
            .filter { $0.tag >= start && $0.tag <= bis }
            .map { (x: Double(start.abstand(zu: $0.tag, kalender: kalender)), y: $0.kg) }
        guard punkte.count >= 3, let erster = punkte.map(\.x).min(), let letzter = punkte.map(\.x).max(),
              letzter - erster >= 7 else { return nil }
        let n = Double(punkte.count)
        let mx = punkte.reduce(0) { $0 + $1.x } / n
        let my = punkte.reduce(0) { $0 + $1.y } / n
        let zaehler = punkte.reduce(0) { $0 + ($1.x - mx) * ($1.y - my) }
        let nenner = punkte.reduce(0) { $0 + ($1.x - mx) * ($1.x - mx) }
        guard nenner > 0 else { return nil }
        return zaehler / nenner * 7
    }
}
