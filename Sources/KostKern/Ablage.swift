import Foundation

/// Liest und schreibt den Datenbestand als eine lesbare JSON-Datei.
public enum Ablage {
    public static var ordner: URL {
        // Für Tests: eigener Ordner, damit echte Daten unberührt bleiben.
        if let eigener = ProcessInfo.processInfo.environment["KOST_DATENORDNER"], !eigener.isEmpty {
            return URL(fileURLWithPath: eigener, isDirectory: true)
        }
        let basis = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return basis.appendingPathComponent("Kost", isDirectory: true)
    }

    public static var datei: URL { ordner.appendingPathComponent("daten.json") }

    public struct Ladeergebnis {
        public let daten: Datenbestand
        /// Gesetzt, wenn eine vorhandene Datei nicht lesbar war und beiseitegelegt wurde.
        public let hinweis: String?
    }

    public static func lade(_ datei: URL) -> Ladeergebnis {
        guard FileManager.default.fileExists(atPath: datei.path) else {
            return Ladeergebnis(daten: Datenbestand(), hinweis: nil)
        }
        do {
            let daten = try entschluessler.decode(Datenbestand.self, from: Data(contentsOf: datei))
            return Ladeergebnis(daten: daten, hinweis: nil)
        } catch {
            // Eine unlesbare Datei nie überschreiben: umbenennen, damit nichts verloren geht.
            let stempel = Int(Date().timeIntervalSince1970)
            let rettung = datei.deletingLastPathComponent().appendingPathComponent("daten-unlesbar-\(stempel).json")
            try? FileManager.default.moveItem(at: datei, to: rettung)
            return Ladeergebnis(
                daten: Datenbestand(),
                hinweis: "Die gespeicherten Daten waren nicht lesbar und liegen jetzt unter „\(rettung.lastPathComponent)“. Kost startet mit leerem Bestand."
            )
        }
    }

    /// Nur lesen, ohne bei Fehlern etwas beiseitezulegen.
    public static func lies(_ datei: URL) -> Datenbestand? {
        guard let daten = try? Data(contentsOf: datei) else { return nil }
        return try? entschluessler.decode(Datenbestand.self, from: daten)
    }

    public static func sichere(_ daten: Datenbestand, in datei: URL) throws {
        try FileManager.default.createDirectory(at: datei.deletingLastPathComponent(), withIntermediateDirectories: true)
        try verschluessler.encode(daten).write(to: datei, options: .atomic)
    }

    static var verschluessler: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static var entschluessler: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

public enum Export {
    /// Tagebuch als CSV mit Semikolon und Dezimalkomma – so öffnen es Numbers und Excel auf Deutsch ohne Nachfragen.
    public static func csv(_ eintraege: [Eintrag]) -> String {
        var zeilen = ["Datum;Mahlzeit;Lebensmittel;Menge;Einheit;" + Naehrstoff.allCases.map { "\($0.name) (\($0.einheit))" }.joined(separator: ";") + ";Quelle"]
        let sortiert = eintraege.sorted { ($0.tag, $0.erstellt) < ($1.tag, $1.erstellt) }
        for e in sortiert {
            var felder = [e.tag.schluessel, e.mahlzeit.name, feld(e.name), zahl(e.menge), feld(e.einheit)]
            felder += Naehrstoff.allCases.map { zahl(e.naehrwerte[$0]) }
            felder.append(e.quelle.name)
            zeilen.append(felder.joined(separator: ";"))
        }
        return zeilen.joined(separator: "\r\n") + "\r\n"
    }

    static func zahl(_ wert: Double) -> String {
        let gerundet = (wert * 10).rounded() / 10
        let text = gerundet == gerundet.rounded() ? String(Int(gerundet)) : String(gerundet)
        return text.replacingOccurrences(of: ".", with: ",")
    }

    static func feld(_ text: String) -> String {
        guard text.contains(where: { ";\"\n\r".contains($0) }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
