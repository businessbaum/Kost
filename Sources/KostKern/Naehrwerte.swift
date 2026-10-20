import Foundation

/// Die Werte der EU-Nährwerttabelle plus Ballaststoffe – genau das, was auf jeder Verpackung steht.
/// Zucker ist Teil der Kohlenhydrate, gesättigte Fettsäuren sind Teil des Fetts.
public struct Naehrwerte: Codable, Equatable, Hashable, Sendable {
    public var kcal: Double
    public var eiweiss: Double
    public var kohlenhydrate: Double
    public var zucker: Double
    public var fett: Double
    public var gesaettigt: Double
    public var ballaststoffe: Double
    public var salz: Double

    public init(
        kcal: Double = 0, eiweiss: Double = 0, kohlenhydrate: Double = 0, zucker: Double = 0,
        fett: Double = 0, gesaettigt: Double = 0, ballaststoffe: Double = 0, salz: Double = 0
    ) {
        self.kcal = kcal
        self.eiweiss = eiweiss
        self.kohlenhydrate = kohlenhydrate
        self.zucker = zucker
        self.fett = fett
        self.gesaettigt = gesaettigt
        self.ballaststoffe = ballaststoffe
        self.salz = salz
    }

    public static let null = Naehrwerte()

    // Fehlende Felder zählen als 0, damit ältere oder von Hand bearbeitete Dateien lesbar bleiben.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func wert(_ k: CodingKeys) throws -> Double { try c.decodeIfPresent(Double.self, forKey: k) ?? 0 }
        self.init(
            kcal: try wert(.kcal), eiweiss: try wert(.eiweiss), kohlenhydrate: try wert(.kohlenhydrate),
            zucker: try wert(.zucker), fett: try wert(.fett), gesaettigt: try wert(.gesaettigt),
            ballaststoffe: try wert(.ballaststoffe), salz: try wert(.salz)
        )
    }

    public subscript(_ stoff: Naehrstoff) -> Double {
        get {
            switch stoff {
            case .kcal: kcal
            case .eiweiss: eiweiss
            case .kohlenhydrate: kohlenhydrate
            case .zucker: zucker
            case .fett: fett
            case .gesaettigt: gesaettigt
            case .ballaststoffe: ballaststoffe
            case .salz: salz
            }
        }
        set {
            switch stoff {
            case .kcal: kcal = newValue
            case .eiweiss: eiweiss = newValue
            case .kohlenhydrate: kohlenhydrate = newValue
            case .zucker: zucker = newValue
            case .fett: fett = newValue
            case .gesaettigt: gesaettigt = newValue
            case .ballaststoffe: ballaststoffe = newValue
            case .salz: salz = newValue
            }
        }
    }

    public static func + (a: Naehrwerte, b: Naehrwerte) -> Naehrwerte {
        var summe = a
        for stoff in Naehrstoff.allCases { summe[stoff] += b[stoff] }
        return summe
    }

    public static func += (a: inout Naehrwerte, b: Naehrwerte) { a = a + b }

    public func mal(_ faktor: Double) -> Naehrwerte {
        var ergebnis = self
        for stoff in Naehrstoff.allCases { ergebnis[stoff] *= faktor }
        return ergebnis
    }

    /// Negative und unbrauchbare Zahlen auf 0; Teilmengen dürfen ihre Obermenge nicht übersteigen.
    public var bereinigt: Naehrwerte {
        var w = self
        for stoff in Naehrstoff.allCases where !w[stoff].isFinite || w[stoff] < 0 { w[stoff] = 0 }
        w.zucker = min(w.zucker, w.kohlenhydrate)
        w.gesaettigt = min(w.gesaettigt, w.fett)
        return w
    }

    /// Brennwert, der sich allein aus den Makros ergibt (4/4/9 kcal je Gramm, Ballaststoffe 2).
    public var kcalAusMakros: Double {
        eiweiss * 4 + kohlenhydrate * 4 + fett * 9 + ballaststoffe * 2
    }

    public var istLeer: Bool { self == .null }
}

public enum Zielrichtung: Sendable {
    /// Möglichst treffen (Kalorien, Kohlenhydrate, Fett).
    case richtwert
    /// Untergrenze (Eiweiß, Ballaststoffe).
    case mindestens
    /// Obergrenze (Zucker, gesättigte Fettsäuren, Salz).
    case hoechstens
}

public enum Naehrstoff: String, CaseIterable, Codable, Identifiable, Sendable {
    case kcal, eiweiss, kohlenhydrate, zucker, fett, gesaettigt, ballaststoffe, salz

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .kcal: "Kalorien"
        case .eiweiss: "Eiweiß"
        case .kohlenhydrate: "Kohlenhydrate"
        case .zucker: "Zucker"
        case .fett: "Fett"
        case .gesaettigt: "Gesättigte Fettsäuren"
        case .ballaststoffe: "Ballaststoffe"
        case .salz: "Salz"
        }
    }

    /// Für Tabellenköpfe und enge Stellen.
    public var kurz: String {
        switch self {
        case .kcal: "kcal"
        case .eiweiss: "Eiweiß"
        case .kohlenhydrate: "Kohlenh."
        case .zucker: "Zucker"
        case .fett: "Fett"
        case .gesaettigt: "ges. Fett"
        case .ballaststoffe: "Ballastst."
        case .salz: "Salz"
        }
    }

    public var einheit: String { self == .kcal ? "kcal" : "g" }

    public var richtung: Zielrichtung {
        switch self {
        case .kcal, .kohlenhydrate, .fett: .richtwert
        case .eiweiss, .ballaststoffe: .mindestens
        case .zucker, .gesaettigt, .salz: .hoechstens
        }
    }

    /// Salz bewegt sich im einstelligen Grammbereich, alles andere reicht ganzzahlig.
    public var nachkommastellen: Int { self == .salz ? 1 : 0 }

    public static let makros: [Naehrstoff] = [.eiweiss, .kohlenhydrate, .fett]
    public static let weitere: [Naehrstoff] = [.ballaststoffe, .zucker, .gesaettigt, .salz]
}

public enum Zielstatus: Equatable, Sendable {
    /// Noch unter dem Ziel.
    case offen
    /// Ziel getroffen bzw. Untergrenze erreicht.
    case erreicht
    /// Unter der Obergrenze.
    case imRahmen
    /// Über Richtwert oder Obergrenze.
    case ueberschritten

    public static func bestimme(wert: Double, ziel: Double, richtung: Zielrichtung) -> Zielstatus {
        guard ziel > 0 else { return .offen }
        switch richtung {
        case .mindestens:
            return wert >= ziel ? .erreicht : .offen
        case .hoechstens:
            return wert > ziel ? .ueberschritten : .imRahmen
        case .richtwert:
            // 5 % Spielraum: Schätzwerte sind nicht genauer.
            if wert > ziel * 1.05 { return .ueberschritten }
            if wert >= ziel * 0.95 { return .erreicht }
            return .offen
        }
    }
}
