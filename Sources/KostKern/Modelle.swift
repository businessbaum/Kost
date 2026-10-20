import Foundation

// MARK: - Kalendertag

/// Ein Kalendertag ohne Uhrzeit. Wird als "2026-10-12" gespeichert, damit Zeitzonenwechsel
/// und Sommerzeit keinen Eintrag auf den Nachbartag schieben.
public struct Tag: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let jahr: Int
    public let monat: Int
    public let tag: Int

    public init(jahr: Int, monat: Int, tag: Int) {
        self.jahr = jahr
        self.monat = monat
        self.tag = tag
    }

    public init(_ datum: Date, kalender: Calendar = .current) {
        let teile = kalender.dateComponents([.year, .month, .day], from: datum)
        self.init(jahr: teile.year ?? 2000, monat: teile.month ?? 1, tag: teile.day ?? 1)
    }

    public init?(schluessel: String) {
        let teile = schluessel.split(separator: "-").compactMap { Int($0) }
        guard teile.count == 3, (1...12).contains(teile[1]), (1...31).contains(teile[2]) else { return nil }
        self.init(jahr: teile[0], monat: teile[1], tag: teile[2])
    }

    public static var heute: Tag { Tag(Date()) }

    public var schluessel: String { String(format: "%04d-%02d-%02d", jahr, monat, tag) }
    public var description: String { schluessel }

    /// Mittag des Tages – weit genug von Mitternacht, dass Tagesrechnungen nicht kippen.
    public func datum(kalender: Calendar = .current) -> Date {
        kalender.date(from: DateComponents(year: jahr, month: monat, day: tag, hour: 12)) ?? Date()
    }

    public func verschoben(um tage: Int, kalender: Calendar = .current) -> Tag {
        let ziel = kalender.date(byAdding: .day, value: tage, to: datum(kalender: kalender)) ?? datum(kalender: kalender)
        return Tag(ziel, kalender: kalender)
    }

    /// Anzahl Tage von `self` bis `anderer` (positiv, wenn `anderer` später liegt).
    public func abstand(zu anderer: Tag, kalender: Calendar = .current) -> Int {
        kalender.dateComponents([.day], from: datum(kalender: kalender), to: anderer.datum(kalender: kalender)).day ?? 0
    }

    public static func < (a: Tag, b: Tag) -> Bool {
        (a.jahr, a.monat, a.tag) < (b.jahr, b.monat, b.tag)
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let tag = Tag(schluessel: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Kein Datum: \(text)"))
        }
        self = tag
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(schluessel)
    }
}

// MARK: - Tagebuch

public enum Mahlzeit: String, Codable, CaseIterable, Identifiable, Sendable {
    case fruehstueck, mittagessen, abendessen, snack

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .fruehstueck: "Frühstück"
        case .mittagessen: "Mittagessen"
        case .abendessen: "Abendessen"
        case .snack: "Snacks"
        }
    }

    /// Vorschlag für die Mahlzeit, die zur Uhrzeit passt.
    public static func passend(zu datum: Date = Date(), kalender: Calendar = .current) -> Mahlzeit {
        let teile = kalender.dateComponents([.hour, .minute], from: datum)
        let minuten = (teile.hour ?? 12) * 60 + (teile.minute ?? 0)
        switch minuten {
        case 300..<630: return .fruehstueck     // 05:00–10:30
        case 690..<870: return .mittagessen     // 11:30–14:30
        case 1050..<1290: return .abendessen    // 17:30–21:30
        default: return .snack
        }
    }
}

public enum Quelle: String, Codable, Sendable {
    /// `claude` bleibt, damit ältere Einträge lesbar sind.
    case claude, chatgpt, manuell, vorrat, produktdatenbank

    public var name: String {
        switch self {
        case .claude: "Von Claude geschätzt"
        case .chatgpt: "Von ChatGPT geschätzt"
        case .manuell: "Von Hand eingetragen"
        case .vorrat: "Aus meinen Lebensmitteln"
        case .produktdatenbank: "Open Food Facts"
        }
    }
}

public struct Eintrag: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var tag: Tag
    public var mahlzeit: Mahlzeit
    public var name: String
    public var menge: Double
    public var einheit: String
    /// Werte für die gesamte Menge, nicht je 100 g.
    public var naehrwerte: Naehrwerte
    public var quelle: Quelle
    public var erstellt: Date

    public init(
        id: UUID = UUID(), tag: Tag, mahlzeit: Mahlzeit, name: String, menge: Double, einheit: String,
        naehrwerte: Naehrwerte, quelle: Quelle, erstellt: Date = Date()
    ) {
        self.id = id
        self.tag = tag
        self.mahlzeit = mahlzeit
        self.name = name
        self.menge = menge
        self.einheit = einheit
        self.naehrwerte = naehrwerte
        self.quelle = quelle
        self.erstellt = erstellt
    }
}

/// Ein gemerktes Lebensmittel mit Werten für eine Bezugsmenge (meist 100 g oder eine Portion).
public struct Lebensmittel: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var marke: String
    public var menge: Double
    public var einheit: String
    public var naehrwerte: Naehrwerte
    public var favorit: Bool
    public var genutzt: Int
    public var zuletzt: Date?
    public var quelle: Quelle

    public init(
        id: UUID = UUID(), name: String, marke: String = "", menge: Double, einheit: String,
        naehrwerte: Naehrwerte, favorit: Bool = false, genutzt: Int = 0, zuletzt: Date? = nil,
        quelle: Quelle = .manuell
    ) {
        self.id = id
        self.name = name
        self.marke = marke
        self.menge = menge
        self.einheit = einheit
        self.naehrwerte = naehrwerte
        self.favorit = favorit
        self.genutzt = genutzt
        self.zuletzt = zuletzt
        self.quelle = quelle
    }

    public func werte(fuer verzehrt: Double) -> Naehrwerte {
        guard menge > 0 else { return naehrwerte }
        return naehrwerte.mal(verzehrt / menge)
    }

    public var anzeigename: String { marke.isEmpty ? name : "\(name) (\(marke))" }
}

public struct Gewichtseintrag: Codable, Identifiable, Equatable, Sendable {
    public var tag: Tag
    public var kg: Double
    public var id: Tag { tag }

    public init(tag: Tag, kg: Double) {
        self.tag = tag
        self.kg = kg
    }
}

// MARK: - Profil

public enum Geschlecht: String, Codable, CaseIterable, Identifiable, Sendable {
    case weiblich, maennlich, divers

    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .weiblich: "Weiblich"
        case .maennlich: "Männlich"
        case .divers: "Divers"
        }
    }
}

public enum Aktivitaet: String, Codable, CaseIterable, Identifiable, Sendable {
    case kaum, leicht, maessig, sehr, extrem

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .kaum: "Kaum aktiv"
        case .leicht: "Leicht aktiv"
        case .maessig: "Mäßig aktiv"
        case .sehr: "Sehr aktiv"
        case .extrem: "Extrem aktiv"
        }
    }

    public var beschreibung: String {
        switch self {
        case .kaum: "Sitzende Tätigkeit, kaum Sport"
        case .leicht: "Sitzend, dazu 1–3 Einheiten Sport pro Woche"
        case .maessig: "3–5 Einheiten Sport pro Woche oder viel auf den Beinen"
        case .sehr: "6–7 Einheiten Sport pro Woche"
        case .extrem: "Körperliche Arbeit und zusätzlich hartes Training"
        }
    }

    /// Faktor auf den Grundumsatz (PAL).
    public var faktor: Double {
        switch self {
        case .kaum: 1.2
        case .leicht: 1.375
        case .maessig: 1.55
        case .sehr: 1.725
        case .extrem: 1.9
        }
    }
}

public enum Ziel: String, Codable, CaseIterable, Identifiable, Sendable {
    case abnehmen, halten, zunehmen

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .abnehmen: "Abnehmen"
        case .halten: "Gewicht halten"
        case .zunehmen: "Zunehmen"
        }
    }

    public var beschreibung: String {
        switch self {
        case .abnehmen: "Weniger essen, als du verbrauchst"
        case .halten: "So viel essen, wie du verbrauchst"
        case .zunehmen: "Mehr essen, etwa für den Muskelaufbau"
        }
    }

    /// Wählbare Geschwindigkeit in kg pro Woche.
    public var tempostufen: [Double] {
        switch self {
        case .abnehmen: [0.25, 0.5, 0.75]
        case .halten: []
        case .zunehmen: [0.125, 0.25, 0.5]
        }
    }

    public var ueblichesTempo: Double {
        switch self {
        case .abnehmen: 0.5
        case .halten: 0
        case .zunehmen: 0.25
        }
    }
}

public struct Profil: Codable, Equatable, Sendable {
    public var name: String
    public var geschlecht: Geschlecht
    /// Geburtsjahr statt Alter, damit das Alter von selbst mitwächst.
    public var geburtsjahr: Int
    public var groesseCm: Double
    public var gewichtKg: Double
    public var aktivitaet: Aktivitaet
    public var ziel: Ziel
    public var tempoKgProWoche: Double
    public var zielgewichtKg: Double?

    public init(
        name: String = "", geschlecht: Geschlecht, geburtsjahr: Int, groesseCm: Double, gewichtKg: Double,
        aktivitaet: Aktivitaet, ziel: Ziel, tempoKgProWoche: Double, zielgewichtKg: Double? = nil
    ) {
        self.name = name
        self.geschlecht = geschlecht
        self.geburtsjahr = geburtsjahr
        self.groesseCm = groesseCm
        self.gewichtKg = gewichtKg
        self.aktivitaet = aktivitaet
        self.ziel = ziel
        self.tempoKgProWoche = tempoKgProWoche
        self.zielgewichtKg = zielgewichtKg
    }

    public func alter(imJahr jahr: Int) -> Int { max(0, jahr - geburtsjahr) }
}

/// Was pro Tag erreicht bzw. nicht überschritten werden soll.
public struct Tagesziele: Codable, Equatable, Sendable {
    public var naehrwerte: Naehrwerte
    public var wasserMl: Int

    public init(naehrwerte: Naehrwerte, wasserMl: Int) {
        self.naehrwerte = naehrwerte
        self.wasserMl = wasserMl
    }

    public subscript(_ stoff: Naehrstoff) -> Double {
        get { naehrwerte[stoff] }
        set { naehrwerte[stoff] = newValue }
    }

    /// Referenzmengen der EU-Kennzeichnung für einen Erwachsenen – nur als Ersatz, solange kein Profil besteht.
    public static let referenz = Tagesziele(
        naehrwerte: Naehrwerte(kcal: 2000, eiweiss: 50, kohlenhydrate: 260, zucker: 90, fett: 70, gesaettigt: 20, ballaststoffe: 30, salz: 6),
        wasserMl: 2000
    )
}

// MARK: - Einstellungen und Gesamtbestand

public struct Einstellungen: Codable, Equatable, Sendable {
    public var glasMl: Int
    /// Leer = automatisch ein kleines Modell aus der Liste des Kontos.
    public var chatgptModell: String

    public init(glasMl: Int = 250, chatgptModell: String = "") {
        self.glasMl = glasMl
        self.chatgptModell = chatgptModell
    }

    // Felder früherer Fassungen (etwa die Claude-Einstellungen) werden beim Lesen einfach übergangen.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        glasMl = try c.decodeIfPresent(Int.self, forKey: .glasMl) ?? 250
        chatgptModell = try c.decodeIfPresent(String.self, forKey: .chatgptModell) ?? ""
    }
}

public struct Datenbestand: Codable, Equatable, Sendable {
    public static let aktuelleVersion = 1

    public var version: Int
    public var profil: Profil?
    /// Gesetzt, sobald die Ziele von Hand festgelegt wurden; sonst folgen sie dem Profil.
    public var eigeneZiele: Tagesziele?
    public var eintraege: [Eintrag]
    public var lebensmittel: [Lebensmittel]
    public var gewichte: [Gewichtseintrag]
    /// Getrunkene Menge in ml je Tag-Schlüssel.
    public var wasser: [String: Int]
    public var einstellungen: Einstellungen

    public init(
        profil: Profil? = nil, eigeneZiele: Tagesziele? = nil, eintraege: [Eintrag] = [],
        lebensmittel: [Lebensmittel] = [], gewichte: [Gewichtseintrag] = [], wasser: [String: Int] = [:],
        einstellungen: Einstellungen = Einstellungen()
    ) {
        self.version = Self.aktuelleVersion
        self.profil = profil
        self.eigeneZiele = eigeneZiele
        self.eintraege = eintraege
        self.lebensmittel = lebensmittel
        self.gewichte = gewichte
        self.wasser = wasser
        self.einstellungen = einstellungen
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        profil = try c.decodeIfPresent(Profil.self, forKey: .profil)
        eigeneZiele = try c.decodeIfPresent(Tagesziele.self, forKey: .eigeneZiele)
        eintraege = try c.decodeIfPresent([Eintrag].self, forKey: .eintraege) ?? []
        lebensmittel = try c.decodeIfPresent([Lebensmittel].self, forKey: .lebensmittel) ?? []
        gewichte = try c.decodeIfPresent([Gewichtseintrag].self, forKey: .gewichte) ?? []
        wasser = try c.decodeIfPresent([String: Int].self, forKey: .wasser) ?? [:]
        einstellungen = try c.decodeIfPresent(Einstellungen.self, forKey: .einstellungen) ?? Einstellungen()
    }
}
