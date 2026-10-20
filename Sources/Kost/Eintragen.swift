import KostKern
import SwiftUI

/// Blatt zum Eintragen: vier Wege zum selben Ziel, der schnellste zuerst.
struct Eintragen: View {
    enum Weg: String, CaseIterable, Identifiable {
        case schaetzen = "Schätzen lassen"
        case vorrat = "Meine Lebensmittel"
        case produkte = "Produktsuche"
        case hand = "Von Hand"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var schliessen
    @Environment(Sitzung.self) private var sitzung
    @Environment(Speicher.self) private var speicher
    let ziel: Eintragsziel

    @State private var weg: Weg = .schaetzen
    @State private var mahlzeit: Mahlzeit
    @State private var rechner = Rechnermodell()

    init(ziel: Eintragsziel) {
        self.ziel = ziel
        _mahlzeit = State(initialValue: ziel.mahlzeit)
    }

    private var aktuellesZiel: Eintragsziel { Eintragsziel(tag: ziel.tag, mahlzeit: mahlzeit) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Essen eintragen").font(.title2.bold())
                        Text(ziel.tag.ausgeschrieben).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Mahlzeit", selection: $mahlzeit) {
                        ForEach(Mahlzeit.allCases) { Text($0.name).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Picker("Weg", selection: $weg) {
                    ForEach(Weg.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                Group {
                    switch weg {
                    case .schaetzen:
                        if !sitzung.kannSchaetzen {
                            Karte { ChatGPTKarte() }
                        } else {
                            Schaetzblatt(modell: rechner, fragtZiel: false, nachUebernahme: { schliessen() })
                        }
                    case .vorrat:
                        Vorratsliste(ziel: aktuellesZiel)
                    case .produkte:
                        Produktliste(ziel: aktuellesZiel)
                    case .hand:
                        Handeintrag(ziel: aktuellesZiel, fertig: { schliessen() })
                    }
                }
                .padding(24)
            }
            .background(Farbe.flaeche)

            Divider()
            HStack {
                Spacer()
                Button("Fertig") { schliessen() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .frame(width: 780, height: 640)
        .onAppear {
            rechner.tag = ziel.tag
            rechner.mahlzeit = mahlzeit
        }
        .onChange(of: mahlzeit) { _, neu in rechner.mahlzeit = neu }
        .onDisappear { rechner.brichAb() }
    }
}

private let einheiten = ["g", "ml", "Stück", "Portion"]

/// Name, Menge und Einheit – der Kopf jedes Formulars.
private struct Stammfelder: View {
    @Binding var name: String
    var marke: Binding<String>?
    @Binding var menge: Double
    @Binding var einheit: String
    var mengenname = "Menge"

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("Name")
                TextField("z. B. Haferflocken", text: $name).textFieldStyle(.roundedBorder)
            }
            if let marke {
                GridRow {
                    Text("Marke")
                    TextField("Freiwillig", text: marke).textFieldStyle(.roundedBorder)
                }
            }
            GridRow {
                Text(mengenname)
                HStack(spacing: 8) {
                    Zahlenfeld(wert: $menge)
                    Picker("Einheit", selection: $einheit) {
                        ForEach(einheiten.contains(einheit) ? einheiten : einheiten + [einheit], id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                }
            }
        }
    }
}

private struct Formularabschnitt<Inhalt: View>: View {
    let titel: String
    var hinweis: String = ""
    @ViewBuilder var inhalt: Inhalt

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(titel).font(.headline)
                Spacer()
                if !hinweis.isEmpty { Text(hinweis).font(.callout).foregroundStyle(.secondary) }
            }
            inhalt
        }
    }
}

/// Reiter "Von Hand": Werte vom Etikett abtippen.
struct Handeintrag: View {
    @Environment(Speicher.self) private var speicher
    let ziel: Eintragsziel
    let fertig: () -> Void

    @State private var name = ""
    @State private var menge = 100.0
    @State private var einheit = "g"
    @State private var werte = Naehrwerte()
    @State private var merken = false

    var body: some View {
        Karte {
            VStack(alignment: .leading, spacing: 20) {
                Stammfelder(name: $name, menge: $menge, einheit: $einheit, mengenname: "Gegessen")
                Divider()
                Formularabschnitt(titel: "Nährwerte", hinweis: "für die gegessene Menge") {
                    Naehrwertfelder(werte: $werte)
                }
                Divider()
                HStack {
                    Toggle("Auch in meinen Lebensmitteln merken", isOn: $merken)
                    Spacer()
                    Button("Eintragen") {
                        let sauber = werte.bereinigt
                        let titel = name.trimmingCharacters(in: .whitespaces)
                        speicher.fuegeHinzu([Eintrag(tag: ziel.tag, mahlzeit: ziel.mahlzeit, name: titel, menge: menge, einheit: einheit, naehrwerte: sauber, quelle: .manuell)])
                        if merken {
                            speicher.merke(Lebensmittel(name: titel, menge: menge, einheit: einheit, naehrwerte: sauber))
                        }
                        fertig()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || menge <= 0)
                }
            }
        }
    }
}

/// Blatt zum Ändern eines Tagebucheintrags.
struct EintragBearbeiten: View {
    @Environment(Speicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen

    let ursprung: Eintrag
    @State private var name: String
    @State private var menge: Double
    @State private var einheit: String
    @State private var mahlzeit: Mahlzeit
    @State private var werte: Naehrwerte

    init(eintrag: Eintrag) {
        ursprung = eintrag
        _name = State(initialValue: eintrag.name)
        _menge = State(initialValue: eintrag.menge)
        _einheit = State(initialValue: eintrag.einheit)
        _mahlzeit = State(initialValue: eintrag.mahlzeit)
        _werte = State(initialValue: eintrag.naehrwerte)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Eintrag bearbeiten").font(.title2.bold())
                    Text("\(ursprung.tag.ausgeschrieben) · \(ursprung.quelle.name)").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Mahlzeit", selection: $mahlzeit) {
                    ForEach(Mahlzeit.allCases) { Text($0.name).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            Stammfelder(name: $name, menge: $menge, einheit: $einheit)
            Divider()
            Formularabschnitt(titel: "Nährwerte", hinweis: "rechnen sich mit der Menge um") {
                Naehrwertfelder(werte: $werte)
            }
            HStack {
                Button("Löschen", role: .destructive) {
                    speicher.loesche(eintrag: ursprung.id)
                    schliessen()
                }
                Spacer()
                Button("Abbrechen") { schliessen() }
                    .keyboardShortcut(.cancelAction)
                Button("Sichern") {
                    var neu = ursprung
                    neu.name = name.trimmingCharacters(in: .whitespaces)
                    neu.menge = menge
                    neu.einheit = einheit
                    neu.mahlzeit = mahlzeit
                    neu.naehrwerte = werte.bereinigt
                    speicher.aendere(eintrag: neu)
                    schliessen()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onChange(of: menge) { _, neu in
            // Immer vom gespeicherten Stand aus rechnen: Zwischenwerte beim Tippen (1, 15, 150) dürfen sich nicht aufschaukeln.
            if ursprung.menge > 0 { werte = ursprung.naehrwerte.mal(neu / ursprung.menge) }
        }
    }
}

/// Blatt zum Anlegen oder Ändern eines gemerkten Lebensmittels.
struct LebensmittelBearbeiten: View {
    @Environment(Speicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen

    let vorlage: Lebensmittel?
    @State private var name: String
    @State private var marke: String
    @State private var menge: Double
    @State private var einheit: String
    @State private var werte: Naehrwerte
    @State private var favorit: Bool

    init(vorlage: Lebensmittel?) {
        self.vorlage = vorlage
        _name = State(initialValue: vorlage?.name ?? "")
        _marke = State(initialValue: vorlage?.marke ?? "")
        _menge = State(initialValue: vorlage?.menge ?? 100)
        _einheit = State(initialValue: vorlage?.einheit ?? "g")
        _werte = State(initialValue: vorlage?.naehrwerte ?? Naehrwerte())
        _favorit = State(initialValue: vorlage?.favorit ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(vorlage == nil ? "Neues Lebensmittel" : "Lebensmittel bearbeiten").font(.title2.bold())
            Stammfelder(name: $name, marke: $marke, menge: $menge, einheit: $einheit, mengenname: "Bezugsmenge")
            Divider()
            Formularabschnitt(titel: "Nährwerte", hinweis: "für \(Zahl.knapp(menge)) \(einheit)") {
                Naehrwertfelder(werte: $werte)
            }
            HStack {
                Toggle("Favorit", isOn: $favorit)
                Spacer()
                Button("Abbrechen") { schliessen() }
                    .keyboardShortcut(.cancelAction)
                Button("Sichern") {
                    var neu = vorlage ?? Lebensmittel(name: "", menge: 100, einheit: "g", naehrwerte: .null)
                    neu.name = name.trimmingCharacters(in: .whitespaces)
                    neu.marke = marke.trimmingCharacters(in: .whitespaces)
                    neu.menge = menge
                    neu.einheit = einheit
                    neu.naehrwerte = werte.bereinigt
                    neu.favorit = favorit
                    speicher.merke(neu)
                    schliessen()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || menge <= 0)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
