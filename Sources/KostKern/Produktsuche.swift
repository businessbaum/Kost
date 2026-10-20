import Foundation

/// Ein verpacktes Produkt aus Open Food Facts mit den Werten vom Etikett.
public struct Produkt: Identifiable, Equatable, Sendable {
    public let code: String
    public let name: String
    public let marke: String
    /// Packungsangabe wie "500 g", nur zur Anzeige.
    public let packung: String
    /// "g" oder "ml" – bei Getränken beziehen sich die Etikettwerte auf 100 ml.
    public let einheit: String
    public let je100: Naehrwerte
    /// Portionsgröße laut Hersteller, falls angegeben.
    public let portion: Double?

    public var id: String { code }

    public func alsLebensmittel() -> Lebensmittel {
        Lebensmittel(name: name, marke: marke, menge: 100, einheit: einheit, naehrwerte: je100, quelle: .produktdatenbank)
    }
}

/// Suche in Open Food Facts – einer freien, von Freiwilligen gepflegten Produktdatenbank.
/// Die Werte stammen von den Etiketten, sind aber nicht redaktionell geprüft.
public enum Produktsuche {
    static let felder = "code,product_name,product_name_de,brands,quantity,serving_size,nutriments"

    public static func suche(_ begriff: String, sitzung: URLSession = .shared) async throws -> [Produkt] {
        let frage = begriff.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !frage.isEmpty else { return [] }

        if istStrichcode(frage) {
            guard let adresse = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(frage).json?fields=\(felder)") else { return [] }
            let daten = try await hole(adresse, sitzung: sitzung)
            return produkt(ausEinzelantwort: daten).map { [$0] } ?? []
        }

        var teile = URLComponents(string: "https://search.openfoodfacts.org/search")!
        teile.queryItems = [
            URLQueryItem(name: "q", value: frage),
            URLQueryItem(name: "langs", value: "de"),
            URLQueryItem(name: "page_size", value: "30"),
            URLQueryItem(name: "fields", value: felder),
        ]
        guard let adresse = teile.url else { return [] }
        return produkte(ausSuchantwort: try await hole(adresse, sitzung: sitzung))
    }

    /// EAN-8 bis GTIN-14: nur Ziffern.
    public static func istStrichcode(_ text: String) -> Bool {
        (8...14).contains(text.count) && text.allSatisfy(\.isNumber)
    }

    static func hole(_ adresse: URL, sitzung: URLSession) async throws -> Data {
        var anfrage = URLRequest(url: adresse, timeoutInterval: 20)
        // Open Food Facts bittet um eine erkennbare Kennung statt des Standard-Agenten.
        anfrage.setValue("Kost/1.0 (macOS; private Nutzung)", forHTTPHeaderField: "User-Agent")
        let (daten, antwort) = try await sitzung.data(for: anfrage)
        if let http = antwort as? HTTPURLResponse, http.statusCode == 404 { return Data() }
        return daten
    }

    static func produkte(ausSuchantwort daten: Data) -> [Produkt] {
        guard let wurzel = try? JSONSerialization.jsonObject(with: daten) as? [String: Any],
              let treffer = wurzel["hits"] as? [[String: Any]] else { return [] }
        var gesehen = Set<String>()
        return treffer.compactMap(produkt(aus:)).filter { gesehen.insert($0.code).inserted }
    }

    static func produkt(ausEinzelantwort daten: Data) -> Produkt? {
        guard let wurzel = try? JSONSerialization.jsonObject(with: daten) as? [String: Any],
              let roh = wurzel["product"] as? [String: Any] else { return nil }
        return produkt(aus: roh)
    }

    static func produkt(aus roh: [String: Any]) -> Produkt? {
        guard let werte = roh["nutriments"] as? [String: Any],
              let kcal = zahl(werte["energy-kcal_100g"]) ?? zahl(werte["energy_100g"]).map({ $0 / 4.184 }) else { return nil }
        let name = text(roh["product_name_de"]).isEmpty ? text(roh["product_name"]) : text(roh["product_name_de"])
        guard !name.isEmpty else { return nil }

        let packung = text(roh["quantity"])
        let portionstext = text(roh["serving_size"])
        let fluessig = istVolumen(packung) || istVolumen(portionstext)

        let je100 = Naehrwerte(
            kcal: kcal,
            eiweiss: zahl(werte["proteins_100g"]) ?? 0,
            kohlenhydrate: zahl(werte["carbohydrates_100g"]) ?? 0,
            zucker: zahl(werte["sugars_100g"]) ?? 0,
            fett: zahl(werte["fat_100g"]) ?? 0,
            gesaettigt: zahl(werte["saturated-fat_100g"]) ?? 0,
            ballaststoffe: zahl(werte["fiber_100g"]) ?? 0,
            salz: zahl(werte["salt_100g"]) ?? 0
        ).bereinigt

        return Produkt(
            code: text(roh["code"]),
            name: name,
            marke: marke(roh["brands"]),
            packung: packung,
            einheit: fluessig ? "ml" : "g",
            je100: je100,
            portion: fuehrendeZahl(portionstext)
        )
    }

    // Die Datenbank liefert Zahlen mal als Zahl, mal als Text, Marken mal als Liste, mal kommagetrennt.

    static func zahl(_ wert: Any?) -> Double? {
        if let n = wert as? NSNumber { return n.doubleValue }
        if let s = wert as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    static func text(_ wert: Any?) -> String {
        (wert as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func marke(_ wert: Any?) -> String {
        if let liste = wert as? [String] { return text(liste.first) }
        return text(text(wert).split(separator: ",").first.map(String.init))
    }

    static func istVolumen(_ angabe: String) -> Bool {
        angabe.range(of: #"\d\s*(ml|cl|l)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// "150 g (1 Becher)" → 150. Angaben in Litern oder Zentilitern werden in ml umgerechnet.
    static func fuehrendeZahl(_ angabe: String) -> Double? {
        guard let treffer = angabe.range(of: #"\d+([.,]\d+)?\s*[a-zA-Z]*"#, options: .regularExpression) else { return nil }
        let stueck = angabe[treffer]
        let ziffern = stueck.prefix { $0.isNumber || $0 == "." || $0 == "," }
        guard let wert = Double(ziffern.replacingOccurrences(of: ",", with: ".")), wert > 0 else { return nil }
        switch stueck.dropFirst(ziffern.count).trimmingCharacters(in: .whitespaces).lowercased() {
        case "l": return wert * 1000
        case "cl": return wert * 10
        case "kg": return wert * 1000
        default: return wert
        }
    }
}
