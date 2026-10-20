import Foundation
import KostKern

/// Ein ausgedachter Datenbestand für die Bildprobe. Berührt nie die echten Daten.
enum Beispieldaten {
    private struct Speise {
        let name: String
        let menge: Double
        let einheit: String
        let werte: Naehrwerte

        init(_ name: String, _ menge: Double, _ einheit: String = "g", kcal: Double, e: Double, k: Double, z: Double, f: Double, g: Double, b: Double, s: Double) {
            self.name = name
            self.menge = menge
            self.einheit = einheit
            self.werte = Naehrwerte(kcal: kcal, eiweiss: e, kohlenhydrate: k, zucker: z, fett: f, gesaettigt: g, ballaststoffe: b, salz: s)
        }
    }

    private static let haferflocken = Speise("Haferflocken", 60, kcal: 222, e: 8, k: 35, z: 0.6, f: 4.2, g: 0.8, b: 6, s: 0)
    private static let milch = Speise("Milch 1,5 %", 200, "ml", kcal: 94, e: 6.8, k: 9.8, z: 9.8, f: 3, g: 2, b: 0, s: 0.26)
    private static let banane = Speise("Banane", 120, kcal: 107, e: 1.3, k: 24, z: 20, f: 0.4, g: 0.1, b: 2.4, s: 0)
    private static let brot = Speise("Vollkornbrot (2 Scheiben)", 100, kcal: 220, e: 7.5, k: 40, z: 3, f: 1.8, g: 0.3, b: 7.5, s: 1.1)
    private static let frischkaese = Speise("Frischkäse", 30, kcal: 75, e: 1.7, k: 0.9, z: 0.9, f: 7.2, g: 4.6, b: 0, s: 0.2)
    private static let ruehrei = Speise("Rührei (3 Eier)", 180, kcal: 290, e: 20, k: 1.5, z: 1.5, f: 23, g: 7, b: 0, s: 0.9)
    private static let cappuccino = Speise("Cappuccino", 200, "ml", kcal: 80, e: 4.5, k: 6.5, z: 6.5, f: 4, g: 2.5, b: 0, s: 0.1)
    private static let haehnchen = Speise("Hähnchenbrust, gebraten", 150, kcal: 248, e: 46, k: 0, z: 0, f: 6, g: 1.6, b: 0, s: 0.3)
    private static let reis = Speise("Reis, gekocht", 200, kcal: 260, e: 5.4, k: 56, z: 0.2, f: 0.6, g: 0.2, b: 0.8, s: 0)
    private static let brokkoli = Speise("Brokkoli", 150, kcal: 51, e: 4.2, k: 4, z: 2.5, f: 0.6, g: 0.1, b: 4.5, s: 0.05)
    private static let bolognese = Speise("Spaghetti Bolognese", 400, kcal: 620, e: 30, k: 78, z: 10, f: 20, g: 7.5, b: 6, s: 2.4)
    private static let lachs = Speise("Lachsfilet", 150, kcal: 310, e: 30, k: 0, z: 0, f: 21, g: 4, b: 0, s: 0.2)
    private static let kartoffeln = Speise("Kartoffeln", 250, kcal: 190, e: 5, k: 40, z: 2, f: 0.3, g: 0.1, b: 4, s: 0)
    private static let salat = Speise("Gemischter Salat mit Dressing", 200, kcal: 130, e: 2.5, k: 8, z: 5, f: 10, g: 1.2, b: 3, s: 0.8)
    private static let pizza = Speise("Pizza Margherita", 350, kcal: 830, e: 33, k: 105, z: 9, f: 29, g: 13, b: 6, s: 4.2)
    private static let skyr = Speise("Skyr natur", 200, kcal: 128, e: 22, k: 8, z: 8, f: 0.4, g: 0.2, b: 0, s: 0.16)
    private static let apfel = Speise("Apfel", 180, kcal: 95, e: 0.5, k: 21, z: 19, f: 0.3, g: 0.1, b: 3.6, s: 0)
    private static let mandeln = Speise("Mandeln", 30, kcal: 180, e: 6.3, k: 1.6, z: 1.3, f: 16, g: 1.3, b: 3.4, s: 0)
    private static let schokolade = Speise("Dunkle Schokolade", 25, kcal: 140, e: 2, k: 8, z: 6, f: 11, g: 6.5, b: 2.7, s: 0)
    private static let riegel = Speise("Proteinriegel", 55, kcal: 205, e: 20, k: 16, z: 2, f: 7, g: 4, b: 6, s: 0.4)

    private static let fruehstuecke: [[Speise]] = [[haferflocken, milch, banane], [brot, frischkaese, cappuccino], [ruehrei, brot]]
    private static let mittagessen: [[Speise]] = [[haehnchen, reis, brokkoli], [bolognese], [lachs, kartoffeln, salat]]
    private static let abendessen: [[Speise]] = [[brot, frischkaese, salat], [pizza], [haehnchen, salat, kartoffeln], [bolognese, salat]]
    private static let snacks: [[Speise]] = [[skyr, apfel], [mandeln, cappuccino], [riegel], [schokolade, apfel]]

    static func bestand(heute: Tag = .heute) -> Datenbestand {
        var daten = Datenbestand()
        daten.profil = Profil(
            name: "Alex", geschlecht: .maennlich, geburtsjahr: heute.jahr - 27, groesseCm: 180, gewichtKg: 82.4,
            aktivitaet: .maessig, ziel: .abnehmen, tempoKgProWoche: 0.5, zielgewichtKg: 78
        )

        func eintraege(_ speisen: [Speise], _ tag: Tag, _ mahlzeit: Mahlzeit, stunde: Int) -> [Eintrag] {
            let basis = tag.datum().addingTimeInterval(Double(stunde - 12) * 3600)
            return speisen.enumerated().map { stelle, speise in
                Eintrag(tag: tag, mahlzeit: mahlzeit, name: speise.name, menge: speise.menge, einheit: speise.einheit,
                        naehrwerte: speise.werte, quelle: .chatgpt, erstellt: basis.addingTimeInterval(Double(stelle)))
            }
        }

        for zurueck in 0..<21 {
            let tag = heute.verschoben(um: -zurueck)
            // Zwei Lücken, wie sie im echten Leben vorkommen
            if zurueck == 9 || zurueck == 16 { continue }
            daten.eintraege += eintraege(fruehstuecke[zurueck % fruehstuecke.count], tag, .fruehstueck, stunde: 8)
            daten.eintraege += eintraege(mittagessen[zurueck % mittagessen.count], tag, .mittagessen, stunde: 13)
            // Heute ist erst Nachmittag: Abendessen fehlt noch.
            if zurueck > 0 {
                daten.eintraege += eintraege(abendessen[zurueck % abendessen.count], tag, .abendessen, stunde: 19)
                daten.eintraege += eintraege(snacks[zurueck % snacks.count], tag, .snack, stunde: 16)
            } else {
                daten.eintraege += eintraege([skyr], tag, .snack, stunde: 15)
            }
            daten.wasser[tag.schluessel] = zurueck == 0 ? 1250 : 1500 + (zurueck * 7 % 5) * 250
        }

        let schwankung = [0.0, 0.3, -0.2, 0.4, -0.1, 0.2, -0.3]
        for (stelle, zurueck) in stride(from: 42, through: 0, by: -3).enumerated() {
            let kg = 82.4 + Double(zurueck) * 0.07 + schwankung[stelle % schwankung.count]
            daten.gewichte.append(Gewichtseintrag(tag: heute.verschoben(um: -zurueck), kg: (kg * 10).rounded() / 10))
        }
        daten.gewichte[daten.gewichte.count - 1].kg = 82.4

        daten.lebensmittel = [
            Lebensmittel(name: "Skyr natur", marke: "Milbona", menge: 100, einheit: "g", naehrwerte: Naehrwerte(kcal: 62, eiweiss: 11, kohlenhydrate: 4, zucker: 4, fett: 0.2, gesaettigt: 0.1, salz: 0.13), favorit: true, genutzt: 14, zuletzt: Date(), quelle: .produktdatenbank),
            Lebensmittel(name: "Haferflocken", marke: "", menge: 100, einheit: "g", naehrwerte: Naehrwerte(kcal: 370, eiweiss: 13.5, kohlenhydrate: 58.7, zucker: 1, fett: 7, gesaettigt: 1.3, ballaststoffe: 10, salz: 0), favorit: true, genutzt: 9, zuletzt: Date().addingTimeInterval(-86_400)),
            Lebensmittel(name: "Proteinshake mit Milch", marke: "", menge: 1, einheit: "Portion", naehrwerte: Naehrwerte(kcal: 265, eiweiss: 34, kohlenhydrate: 17, zucker: 16, fett: 6.5, gesaettigt: 4, ballaststoffe: 0.5, salz: 0.5), genutzt: 5, zuletzt: Date().addingTimeInterval(-3 * 86_400)),
            Lebensmittel(name: "Vollkornbrot", marke: "Harry", menge: 100, einheit: "g", naehrwerte: Naehrwerte(kcal: 220, eiweiss: 7.5, kohlenhydrate: 40, zucker: 3, fett: 1.8, gesaettigt: 0.3, ballaststoffe: 7.5, salz: 1.1), genutzt: 3, zuletzt: Date().addingTimeInterval(-5 * 86_400), quelle: .produktdatenbank),
        ]
        return daten
    }

    static let schaetzung = Schaetzung(
        posten: [
            Schaetzposten(name: "Vollkornbrot (2 Scheiben)", menge: 100, einheit: "g", naehrwerte: Naehrwerte(kcal: 220, eiweiss: 7.5, kohlenhydrate: 40, zucker: 3, fett: 1.8, gesaettigt: 0.3, ballaststoffe: 7.5, salz: 1.1)),
            Schaetzposten(name: "Frischkäse", menge: 40, einheit: "g", naehrwerte: Naehrwerte(kcal: 100, eiweiss: 2.2, kohlenhydrate: 1.2, zucker: 1.2, fett: 9.6, gesaettigt: 6.1, ballaststoffe: 0, salz: 0.3)),
            Schaetzposten(name: "Gurke", menge: 60, einheit: "g", naehrwerte: Naehrwerte(kcal: 8, eiweiss: 0.4, kohlenhydrate: 1.1, zucker: 1, fett: 0.1, gesaettigt: 0, ballaststoffe: 0.5, salz: 0)),
            Schaetzposten(name: "Orangensaft", menge: 200, einheit: "ml", naehrwerte: Naehrwerte(kcal: 86, eiweiss: 1.4, kohlenhydrate: 18, zucker: 17, fett: 0.4, gesaettigt: 0, ballaststoffe: 0.4, salz: 0)),
        ],
        annahmen: "Zwei Scheiben Vollkornbrot zu je 50 g, dünn bestrichen mit Doppelrahm-Frischkäse. Ein Glas Saft mit 200 ml.",
        sicherheit: .mittel
    )
}
