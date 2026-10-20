import XCTest
@testable import KostKern

final class BedarfTests: XCTestCase {
    func profil(_ geschlecht: Geschlecht = .maennlich, kg: Double = 80, cm: Double = 180, ziel: Ziel = .halten, tempo: Double = 0, aktivitaet: Aktivitaet = .maessig) -> Profil {
        Profil(geschlecht: geschlecht, geburtsjahr: 1996, groesseCm: cm, gewichtKg: kg, aktivitaet: aktivitaet, ziel: ziel, tempoKgProWoche: tempo)
    }

    func testGrundumsatzNachMifflinStJeor() {
        // 10·80 + 6,25·180 − 5·30 + 5 = 1780
        XCTAssertEqual(Bedarfsrechner.grundumsatz(profil(), alter: 30), 1780)
        // gleiche Person weiblich: −161 statt +5
        XCTAssertEqual(Bedarfsrechner.grundumsatz(profil(.weiblich), alter: 30), 1614)
        XCTAssertEqual(Bedarfsrechner.grundumsatz(profil(.divers), alter: 30), 1697)
    }

    func testHaltenErgibtGesamtumsatzUndStimmigeMakros() {
        let bedarf = Bedarfsrechner.berechne(profil(), imJahr: 2026)
        XCTAssertEqual(bedarf.gesamtumsatz, 2759)          // 1780 · 1,55
        XCTAssertEqual(bedarf.ziele[.kcal], 2760)
        XCTAssertEqual(bedarf.ziele[.eiweiss], 112)        // 1,4 g/kg
        XCTAssertEqual(bedarf.ziele[.fett], 92)            // 30 % von 2760 / 9
        XCTAssertEqual(bedarf.ziele[.kohlenhydrate], 371)
        // Die Makros müssen zusammen wieder das Kalorienziel ergeben (Rundung ± ein paar kcal).
        let z = bedarf.ziele.naehrwerte
        XCTAssertEqual(z.eiweiss * 4 + z.kohlenhydrate * 4 + z.fett * 9, z.kcal, accuracy: 8)
        XCTAssertEqual(bedarf.ziele.wasserMl, 2500)        // 80 kg · 30 ml = 2400 → auf 250 gerundet
    }

    func testAbnehmenZiehtDefizitAb() {
        let bedarf = Bedarfsrechner.berechne(profil(ziel: .abnehmen, tempo: 0.5), imJahr: 2026)
        XCTAssertEqual(bedarf.anpassung, -550)             // 0,5 kg · 7700 / 7
        XCTAssertEqual(bedarf.ziele[.kcal], 2210)
        XCTAssertEqual(bedarf.ziele[.eiweiss], 144)        // 1,8 g/kg
        XCTAssertFalse(bedarf.untergrenzeGegriffen)
    }

    func testUntergrenzeSchuetztVorZuWenig() {
        let klein = profil(.weiblich, kg: 50, cm: 155, ziel: .abnehmen, tempo: 0.75, aktivitaet: .kaum)
        let bedarf = Bedarfsrechner.berechne(klein, imJahr: 2026)
        XCTAssertTrue(bedarf.untergrenzeGegriffen)
        XCTAssertEqual(bedarf.ziele[.kcal], 1200)
        XCTAssertGreaterThanOrEqual(bedarf.ziele[.kohlenhydrate], 0)
    }

    func testEiweissWaechstBeiHohemBMINichtUnbegrenzt() {
        let schwer = Bedarfsrechner.berechne(profil(kg: 130, ziel: .abnehmen, tempo: 0.5), imJahr: 2026)
        // Rechengewicht ist auf BMI 27,5 gedeckelt: 27,5 · 1,8² = 89,1 kg → 160 g statt 234 g
        XCTAssertEqual(schwer.ziele[.eiweiss], 160)
    }

    func testBMI() {
        XCTAssertEqual(Bedarfsrechner.bmi(gewichtKg: 81, groesseCm: 180), 25, accuracy: 0.001)
        XCTAssertEqual(Bedarfsrechner.bmiEinordnung(24.9), "Normalgewicht")
        XCTAssertEqual(Bedarfsrechner.bmiEinordnung(25), "Übergewicht")
    }
}

final class NaehrwerteTests: XCTestCase {
    func testRechnenUndBereinigen() {
        let a = Naehrwerte(kcal: 100, eiweiss: 10, kohlenhydrate: 5, zucker: 2, fett: 3, gesaettigt: 1, ballaststoffe: 1, salz: 0.5)
        XCTAssertEqual((a + a).kcal, 200)
        XCTAssertEqual(a.mal(1.5).eiweiss, 15)
        let kaputt = Naehrwerte(kcal: -5, eiweiss: .nan, kohlenhydrate: 10, zucker: 30, fett: 5, gesaettigt: 9)
        let sauber = kaputt.bereinigt
        XCTAssertEqual(sauber.kcal, 0)
        XCTAssertEqual(sauber.eiweiss, 0)
        XCTAssertEqual(sauber.zucker, 10, "Zucker kann nicht über den Kohlenhydraten liegen")
        XCTAssertEqual(sauber.gesaettigt, 5)
    }

    func testZielstatus() {
        XCTAssertEqual(Zielstatus.bestimme(wert: 20, ziel: 30, richtung: .mindestens), .offen)
        XCTAssertEqual(Zielstatus.bestimme(wert: 31, ziel: 30, richtung: .mindestens), .erreicht)
        XCTAssertEqual(Zielstatus.bestimme(wert: 5, ziel: 6, richtung: .hoechstens), .imRahmen)
        XCTAssertEqual(Zielstatus.bestimme(wert: 7, ziel: 6, richtung: .hoechstens), .ueberschritten)
        XCTAssertEqual(Zielstatus.bestimme(wert: 2050, ziel: 2000, richtung: .richtwert), .erreicht)
        XCTAssertEqual(Zielstatus.bestimme(wert: 2200, ziel: 2000, richtung: .richtwert), .ueberschritten)
    }
}

final class TagUndAuswertungTests: XCTestCase {
    var kalender: Calendar = {
        var k = Calendar(identifier: .gregorian)
        k.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return k
    }()

    func testTagUeberMonatsUndZeitumstellung() {
        let silvester = Tag(jahr: 2026, monat: 12, tag: 31)
        XCTAssertEqual(silvester.verschoben(um: 1, kalender: kalender), Tag(jahr: 2027, monat: 1, tag: 1))
        // 25.10.2026 endet die Sommerzeit – der Tag hat 25 Stunden
        let vorher = Tag(jahr: 2026, monat: 10, tag: 24)
        XCTAssertEqual(vorher.verschoben(um: 2, kalender: kalender), Tag(jahr: 2026, monat: 10, tag: 26))
        XCTAssertEqual(vorher.abstand(zu: Tag(jahr: 2026, monat: 10, tag: 26), kalender: kalender), 2)
        XCTAssertEqual(Tag(schluessel: "2026-10-12")?.schluessel, "2026-10-12")
        XCTAssertNil(Tag(schluessel: "gestern"))
    }

    func eintrag(_ tag: Tag, _ kcal: Double, _ mahlzeit: Mahlzeit = .mittagessen, name: String = "Essen") -> Eintrag {
        Eintrag(tag: tag, mahlzeit: mahlzeit, name: name, menge: 100, einheit: "g", naehrwerte: Naehrwerte(kcal: kcal, eiweiss: 10), quelle: .manuell)
    }

    func testZeitraumMitteltNurErfassteTage() {
        let t = Tag(jahr: 2026, monat: 10, tag: 10)
        var daten = Datenbestand()
        daten.eintraege = [eintrag(t, 1000), eintrag(t, 500), eintrag(t.verschoben(um: 2, kalender: kalender), 2500)]
        daten.wasser[t.schluessel] = 1500
        let zeitraum = daten.zeitraum(von: t, bis: t.verschoben(um: 2, kalender: kalender), kalender: kalender)
        XCTAssertEqual(zeitraum.tage.count, 3)
        XCTAssertEqual(zeitraum.erfassteTage, 2)
        XCTAssertEqual(zeitraum.schnitt.kcal, 2000)     // (1500 + 2500) / 2, der leere Tag zählt nicht
        XCTAssertEqual(zeitraum.wasserSchnitt, 1500)
        XCTAssertEqual(daten.summe(am: t).kcal, 1500)
    }

    func testSerieZaehltBisGesternWennHeuteNochLeer() {
        let heute = Tag(jahr: 2026, monat: 10, tag: 12)
        var daten = Datenbestand()
        daten.eintraege = [-1, -2, -3, -5].map { eintrag(heute.verschoben(um: $0, kalender: kalender), 100) }
        XCTAssertEqual(daten.serie(bis: heute, kalender: kalender), 3)
        daten.eintraege.append(eintrag(heute, 100))
        XCTAssertEqual(daten.serie(bis: heute, kalender: kalender), 4)
    }

    func testGewichtstrend() {
        let heute = Tag(jahr: 2026, monat: 10, tag: 29)
        // genau 0,5 kg weniger pro Woche über vier Wochen
        let wiegen = (0...4).map { Gewichtseintrag(tag: heute.verschoben(um: -28 + $0 * 7, kalender: kalender), kg: 82 - Double($0) * 0.5) }
        XCTAssertEqual(Gewichtstrend.kgProWoche(wiegen, bis: heute, kalender: kalender) ?? 0, -0.5, accuracy: 0.001)
        XCTAssertNil(Gewichtstrend.kgProWoche(Array(wiegen.prefix(2)), bis: heute, kalender: kalender), "zwei Wägungen sind noch kein Trend")
    }

    func testSpeichernUndLadenErhaeltAlles() throws {
        let ordner = FileManager.default.temporaryDirectory.appendingPathComponent("kost-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: ordner) }
        let datei = ordner.appendingPathComponent("daten.json")
        let t = Tag(jahr: 2026, monat: 10, tag: 12)
        var daten = Datenbestand()
        daten.profil = Profil(name: "Test", geschlecht: .weiblich, geburtsjahr: 1990, groesseCm: 170, gewichtKg: 65, aktivitaet: .leicht, ziel: .abnehmen, tempoKgProWoche: 0.5, zielgewichtKg: 60)
        daten.eintraege = [eintrag(t, 432.5, .fruehstueck, name: "Müsli; mit \"Obst\"")]
        daten.lebensmittel = [Lebensmittel(name: "Skyr", menge: 100, einheit: "g", naehrwerte: Naehrwerte(kcal: 63, eiweiss: 11), favorit: true)]
        daten.gewichte = [Gewichtseintrag(tag: t, kg: 64.8)]
        daten.wasser[t.schluessel] = 750
        try Ablage.sichere(daten, in: datei)
        let geladen = Ablage.lade(datei)
        XCTAssertNil(geladen.hinweis)
        // Datumsangaben verlieren beim Speichern die Sekundenbruchteile, alles andere muss gleich sein.
        XCTAssertEqual(geladen.daten.profil, daten.profil)
        XCTAssertEqual(geladen.daten.eintraege.first?.name, "Müsli; mit \"Obst\"")
        XCTAssertEqual(geladen.daten.eintraege.first?.naehrwerte, daten.eintraege.first?.naehrwerte)
        XCTAssertEqual(geladen.daten.lebensmittel.first?.favorit, true)
        XCTAssertEqual(geladen.daten.gewichte, daten.gewichte)
        XCTAssertEqual(geladen.daten.wasser, daten.wasser)
    }

    func testUnlesbareDateiWirdBeiseitegelegtStattUeberschrieben() throws {
        let ordner = FileManager.default.temporaryDirectory.appendingPathComponent("kost-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ordner) }
        let datei = ordner.appendingPathComponent("daten.json")
        try Data("{ das ist kein JSON".utf8).write(to: datei)
        let geladen = Ablage.lade(datei)
        XCTAssertNotNil(geladen.hinweis)
        XCTAssertFalse(FileManager.default.fileExists(atPath: datei.path))
        let rest = try FileManager.default.contentsOfDirectory(atPath: ordner.path)
        XCTAssertEqual(rest.filter { $0.hasPrefix("daten-unlesbar-") }.count, 1)
    }

    func testCSV() {
        let t = Tag(jahr: 2026, monat: 10, tag: 12)
        let csv = Export.csv([eintrag(t, 432.5, .fruehstueck, name: "Müsli; mit \"Obst\"")])
        let zeilen = csv.components(separatedBy: "\r\n")
        XCTAssertTrue(zeilen[0].hasPrefix("Datum;Mahlzeit;Lebensmittel;Menge;Einheit;Kalorien (kcal);Eiweiß (g)"))
        XCTAssertTrue(zeilen[1].hasPrefix("2026-10-12;Frühstück;\"Müsli; mit \"\"Obst\"\"\";100;g;432,5;10;"))
    }
}

final class SchaetzauftragTests: XCTestCase {
    func testAntwortWirdGelesen() throws {
        let roh = try XCTUnwrap(Schaetzauftrag.jsonObjekt(aus: #"{"posten":[{"name":"Apfel","menge":180,"einheit":"g","kcal":95,"eiweiss":0.5,"kohlenhydrate":25,"zucker":19,"fett":0.3,"gesaettigt":0.1,"ballaststoffe":4.4,"salz":0},{"name":"Orangensaft","menge":200,"einheit":"ml","kcal":0,"eiweiss":1.4,"kohlenhydrate":18,"zucker":17,"fett":0.4,"gesaettigt":0,"ballaststoffe":0.4,"salz":0}],"annahmen":"Mittelgroßer Apfel.","sicherheit":"mittel"}"#))
        let schaetzung = try Schaetzauftrag.schaetzung(aus: roh)
        XCTAssertEqual(schaetzung.posten.count, 2)
        XCTAssertEqual(schaetzung.posten[0].naehrwerte.zucker, 19)
        XCTAssertEqual(schaetzung.posten[1].einheit, "ml")
        // fehlender Brennwert wird aus den Makros ergänzt: 1,4·4 + 18·4 + 0,4·9 + 0,4·2 = 82
        XCTAssertEqual(schaetzung.posten[1].naehrwerte.kcal, 82)
        XCTAssertEqual(schaetzung.summe.kcal, 177)
    }

    func testJSONAusCodeblockUndLeereAntwort() throws {
        let roh = try XCTUnwrap(Schaetzauftrag.jsonObjekt(aus: "```json\n{\"posten\":[{\"name\":\"Banane\",\"menge\":120,\"einheit\":\"g\",\"kcal\":107}],\"annahmen\":\"\",\"sicherheit\":\"hoch\"}\n```"))
        XCTAssertEqual(try Schaetzauftrag.schaetzung(aus: roh).posten.first?.name, "Banane")
        let leer: [String: Any] = ["posten": [], "annahmen": "Das ist keine Mahlzeit.", "sicherheit": "niedrig"]
        XCTAssertThrowsError(try Schaetzauftrag.schaetzung(aus: leer)) { XCTAssertEqual($0 as? Schaetzfehler, .keinEssenErkannt("Das ist keine Mahlzeit.")) }
    }

    func testSchemaIstStrengUndVollstaendig() throws {
        let schema = Schaetzauftrag.schema
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        let posten = try XCTUnwrap((schema["properties"] as? [String: Any])?["posten"] as? [String: Any])
        let eintrag = try XCTUnwrap(posten["items"] as? [String: Any])
        XCTAssertEqual(eintrag["additionalProperties"] as? Bool, false)
        XCTAssertEqual(Set(eintrag["required"] as? [String] ?? []), Set(Naehrstoff.allCases.map(\.rawValue) + ["name", "menge", "einheit"]))
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(Schaetzauftrag.schemaText.utf8)))
    }

    func testAnfragetext() {
        XCTAssertEqual(Schaetzauftrag.anfrage(text: " 2 Brötchen ", bilder: 1), "Das Foto zeigt, was ich gegessen habe.\n\nMeine Angaben dazu:\n2 Brötchen")
        XCTAssertEqual(Schaetzauftrag.anfrage(text: "Apfel", bilder: 0), "Das habe ich gegessen:\nApfel")
    }
}

final class ProduktsucheTests: XCTestCase {
    func testSuchantwort() {
        let antwort = Data(#"""
        {"hits":[
          {"code":"4337185761638","product_name":"Skyr natur","brands":["K-Classic"],"quantity":"500 g","serving_size":"150 g",
           "nutriments":{"energy-kcal_100g":64,"proteins_100g":11,"carbohydrates_100g":4,"sugars_100g":4,"fat_100g":0.2,"saturated-fat_100g":0.1,"salt_100g":0.08}},
          {"code":"111","product_name":"Ohne Werte","nutriments":{}},
          {"code":"5449000000996","product_name":"Cola","brands":"Coca-Cola, Coke","quantity":"1,5 l","serving_size":"0.25 l",
           "nutriments":{"energy-kcal_100g":"42","carbohydrates_100g":"10,6","sugars_100g":10.6}},
          {"code":"4337185761638","product_name":"Skyr natur (doppelt)","nutriments":{"energy-kcal_100g":64}}
        ]}
        """#.utf8)
        let produkte = Produktsuche.produkte(ausSuchantwort: antwort)
        XCTAssertEqual(produkte.map(\.name), ["Skyr natur", "Cola"], "Einträge ohne Brennwert und Doppelte fallen weg")
        XCTAssertEqual(produkte[0].marke, "K-Classic")
        XCTAssertEqual(produkte[0].einheit, "g")
        XCTAssertEqual(produkte[0].portion, 150)
        XCTAssertEqual(produkte[0].je100.eiweiss, 11)
        XCTAssertEqual(produkte[1].marke, "Coca-Cola")
        XCTAssertEqual(produkte[1].einheit, "ml")
        XCTAssertEqual(produkte[1].portion, 250)
        XCTAssertEqual(produkte[1].je100.kohlenhydrate, 10.6)
    }

    func testStrichcodeErkennung() {
        XCTAssertTrue(Produktsuche.istStrichcode("4337185761638"))
        XCTAssertFalse(Produktsuche.istStrichcode("skyr 500"))
        XCTAssertFalse(Produktsuche.istStrichcode("12345"))
    }
}
