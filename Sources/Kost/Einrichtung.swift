import KostKern
import SwiftUI

/// Auswahlkarte für die Einrichtung und überall, wo eine von wenigen Möglichkeiten mit Erklärung zu wählen ist.
struct Wahlkarte: View {
    let titel: String
    var text: String = ""
    let gewaehlt: Bool
    let aktion: () -> Void

    var body: some View {
        Button(action: aktion) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(titel).font(.body.weight(.medium))
                    if !text.isEmpty {
                        Text(text).font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: gewaehlt ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(gewaehlt ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Farbe.karte, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(gewaehlt ? Color.accentColor : Farbe.linie, lineWidth: gewaehlt ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(gewaehlt ? .isSelected : [])
    }
}

/// Fragt beim ersten Start ab, was die Bedarfsrechnung braucht.
struct Einrichtung: View {
    @Environment(Speicher.self) private var speicher
    @Environment(Sitzung.self) private var sitzung

    @State private var schritt = 0
    @State private var name = ""
    @State private var geschlecht: Geschlecht?
    @State private var alter: Double?
    @State private var groesse: Double?
    @State private var gewicht: Double?
    @State private var aktivitaet: Aktivitaet?
    @State private var ziel: Ziel?
    @State private var tempo = 0.5
    @State private var zielgewicht: Double?

    private let schritte = 6

    /// `probeschritt` füllt die Antworten vor und springt zu einem Schritt – nur für die Bildprobe.
    init(probeschritt: Int? = nil) {
        guard let probeschritt else { return }
        _schritt = State(initialValue: probeschritt)
        _name = State(initialValue: "Alex")
        _geschlecht = State(initialValue: .maennlich)
        _alter = State(initialValue: 27)
        _groesse = State(initialValue: 180)
        _gewicht = State(initialValue: 82)
        _aktivitaet = State(initialValue: .maessig)
        _ziel = State(initialValue: .abnehmen)
        _zielgewicht = State(initialValue: 78)
    }

    private var jahr: Int { Calendar.current.component(.year, from: Date()) }

    private var profil: Profil? {
        guard let geschlecht, let alter, let groesse, let gewicht, let aktivitaet, let ziel else { return nil }
        return Profil(
            name: name.trimmingCharacters(in: .whitespaces), geschlecht: geschlecht, geburtsjahr: jahr - Int(alter),
            groesseCm: groesse, gewichtKg: gewicht, aktivitaet: aktivitaet, ziel: ziel,
            tempoKgProWoche: ziel == .halten ? 0 : tempo, zielgewichtKg: ziel == .halten ? nil : zielgewicht
        )
    }

    private var darfWeiter: Bool {
        switch schritt {
        case 0: geschlecht != nil && (alter.map { (14...100).contains($0) } ?? false)
        case 1: (groesse.map { (120...230).contains($0) } ?? false) && (gewicht.map { (30...300).contains($0) } ?? false)
        case 2: aktivitaet != nil
        case 3: ziel != nil
        case 4: profil != nil
        default: profil != nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            VStack(alignment: .leading, spacing: 24) {
                fortschritt
                Group {
                    switch schritt {
                    case 0: ueberDich
                    case 1: koerper
                    case 2: alltag
                    case 3: zielwahl
                    case 4: ergebnis
                    default: chatgptSchritt
                    }
                }
                .frame(minHeight: 330, alignment: .top)
                knoepfe
            }
            .frame(width: 480)
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Farbe.flaeche)
    }

    private var fortschritt: some View {
        HStack(spacing: 6) {
            ForEach(0..<schritte, id: \.self) { stelle in
                Capsule()
                    .fill(stelle <= schritt ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Farbe.spur))
                    .frame(height: 4)
            }
        }
        .accessibilityLabel("Schritt \(schritt + 1) von \(schritte)")
    }

    private func kopf(_ titel: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titel).font(.system(size: 28, weight: .bold))
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func zeile<Feld: View>(_ beschriftung: String, @ViewBuilder feld: () -> Feld) -> some View {
        HStack {
            Text(beschriftung)
            Spacer()
            feld()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Farbe.karte, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Farbe.linie))
    }

    // MARK: Schritte

    private var ueberDich: some View {
        VStack(alignment: .leading, spacing: 20) {
            kopf("Willkommen bei Kost", "Vier kurze Fragen, dann weiß die App, wie viel du am Tag brauchst. Deine Angaben bleiben auf diesem Mac.")
            VStack(spacing: 8) {
                zeile("Wie heißt du?") {
                    TextField("Freiwillig", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
                zeile("Geschlecht") {
                    Picker("Geschlecht", selection: $geschlecht) {
                        ForEach(Geschlecht.allCases) { Text($0.name).tag(Optional($0)) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                zeile("Alter") {
                    WahlfreiesZahlenfeld(wert: $alter, einheit: "Jahre", stellen: 0)
                }
            }
            if let alter, alter < 18, alter >= 14 {
                hinweis("Die Rechnung ist für Erwachsene gemacht. Wer noch wächst, braucht oft mehr – besprich ein Abnehmziel bitte mit einer Ärztin oder einem Arzt.")
            } else {
                Text("Das Geschlecht geht in die Formel für den Grundumsatz ein. Bei „Divers“ rechnet Kost mit dem Mittelwert.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var koerper: some View {
        VStack(alignment: .leading, spacing: 20) {
            kopf("Dein Körper", "Größe und Gewicht bestimmen, wie viel Energie du schon in Ruhe verbrauchst.")
            VStack(spacing: 8) {
                zeile("Größe") { WahlfreiesZahlenfeld(wert: $groesse, einheit: "cm", stellen: 0) }
                zeile("Gewicht") { WahlfreiesZahlenfeld(wert: $gewicht, einheit: "kg", stellen: 1) }
            }
            if let groesse, let gewicht, (120...230).contains(groesse), (30...300).contains(gewicht) {
                let bmi = Bedarfsrechner.bmi(gewichtKg: gewicht, groesseCm: groesse)
                Text("BMI \(Zahl.knapp(bmi)) – \(Bedarfsrechner.bmiEinordnung(bmi))")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var alltag: some View {
        VStack(alignment: .leading, spacing: 20) {
            kopf("Dein Alltag", "Wie viel bewegst du dich in einer normalen Woche?")
            VStack(spacing: 8) {
                ForEach(Aktivitaet.allCases) { stufe in
                    Wahlkarte(titel: stufe.name, text: stufe.beschreibung, gewaehlt: aktivitaet == stufe) { aktivitaet = stufe }
                }
            }
        }
    }

    private var zielwahl: some View {
        VStack(alignment: .leading, spacing: 20) {
            kopf("Dein Ziel", "Davon hängt ab, ob dein Tagesziel unter, auf oder über deinem Verbrauch liegt.")
            VStack(spacing: 8) {
                ForEach(Ziel.allCases) { moeglich in
                    Wahlkarte(titel: moeglich.name, text: moeglich.beschreibung, gewaehlt: ziel == moeglich) {
                        ziel = moeglich
                        tempo = moeglich.ueblichesTempo
                    }
                }
            }
            if let ziel, ziel != .halten {
                VStack(spacing: 8) {
                    zeile("Tempo") {
                        Picker("Tempo", selection: $tempo) {
                            ForEach(ziel.tempostufen, id: \.self) { Text("\(Zahl.knapp($0, stellen: 3)) kg/Woche").tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    zeile("Zielgewicht") { WahlfreiesZahlenfeld(wert: $zielgewicht, einheit: "kg", platzhalter: "Freiwillig") }
                }
            }
        }
    }

    private var ergebnis: some View {
        VStack(alignment: .leading, spacing: 20) {
            kopf(name.trimmingCharacters(in: .whitespaces).isEmpty ? "Dein Tagesbedarf" : "\(name.trimmingCharacters(in: .whitespaces)), dein Tagesbedarf",
                 "So setzt sich dein Ziel zusammen. Du kannst alles später unter „Profil & Ziele“ ändern.")
            if let profil {
                let bedarf = Bedarfsrechner.berechne(profil, imJahr: jahr)
                Karte {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(Zahl.ganz(bedarf.ziele[.kcal])).font(.system(size: 44, weight: .semibold, design: .rounded))
                            Text("kcal pro Tag").font(.title3).foregroundStyle(.secondary)
                        }
                        Bedarfsherleitung(bedarf: bedarf, profil: profil)
                        Divider()
                        HStack(spacing: 0) {
                            ForEach(Naehrstoff.makros) { stoff in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 5) {
                                        Circle().fill(Farbe.fuer(stoff)).frame(width: 8, height: 8)
                                        Text(stoff.name).font(.callout).foregroundStyle(.secondary)
                                    }
                                    Text("\(Zahl.ganz(bedarf.ziele[stoff])) g").font(.title3.weight(.semibold)).monospacedDigit()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                if bedarf.untergrenzeGegriffen {
                    hinweis("Mit diesem Tempo läge dein Ziel unter \(Zahl.ganz(bedarf.ziele[.kcal])) kcal. So wenig sollte man auf Dauer nicht essen, deshalb bleibt das Ziel dort stehen – du nimmst dann etwas langsamer ab.")
                }
            }
        }
    }

    /// Einmalig: mit ChatGPT anmelden, damit Kost schätzen kann.
    private var chatgptSchritt: some View {
        VStack(alignment: .leading, spacing: 20) {
            kopf("Schätzen lassen", "Beschreib oder fotografiere, was du gegessen hast – Kost schätzt Kalorien und Nährwerte. Dafür meldest du dich nur dieses eine Mal an.")
            Karte { ChatGPTKarte(zeigtKopf: false) }
            Text("Du kannst das auch überspringen und später unter Kost › Einstellungen nachholen.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func hinweis(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var knoepfe: some View {
        HStack {
            if schritt > 0 {
                Button("Zurück") { schritt -= 1 }
                    .controlSize(.large)
            }
            Spacer()
            Button(schritt == schritte - 1 ? "Los geht’s" : "Weiter") {
                if schritt == schritte - 1 {
                    if let profil { speicher.richteEin(profil) }
                } else {
                    schritt += 1
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!darfWeiter)
        }
    }
}

/// Der Rechenweg vom Grundumsatz zum Tagesziel, Zeile für Zeile.
struct Bedarfsherleitung: View {
    let bedarf: Bedarf
    let profil: Profil

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
            reihe("Grundumsatz", "Verbrauch in völliger Ruhe", Zahl.ganz(bedarf.grundumsatz))
            reihe("Gesamtumsatz", "mal \(Zahl.knapp(profil.aktivitaet.faktor, stellen: 3)) – \(profil.aktivitaet.name.lowercased())", Zahl.ganz(bedarf.gesamtumsatz))
            if profil.ziel != .halten {
                reihe(
                    profil.ziel == .abnehmen ? "Defizit" : "Überschuss",
                    "für \(Zahl.knapp(profil.tempoKgProWoche, stellen: 3)) kg pro Woche",
                    Zahl.mitVorzeichen(bedarf.anpassung, stellen: 0)
                )
            }
        }
        .font(.callout)
    }

    private func reihe(_ name: String, _ erklaerung: String, _ wert: String) -> some View {
        GridRow {
            Text(name)
            Text(erklaerung).foregroundStyle(.secondary)
            Text("\(wert) kcal").monospacedDigit().gridColumnAlignment(.trailing)
        }
    }
}
