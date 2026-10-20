import KostKern
import SwiftUI

struct TagebuchAnsicht: View {
    @Environment(Speicher.self) private var speicher
    @Environment(Sitzung.self) private var sitzung

    @State private var eintragsziel: Eintragsziel?
    @State private var bearbeitet: Eintrag?
    @State private var zeigtKalender = false

    var body: some View {
        let tag = sitzung.tag
        Seite {
            kopf(tag)
            Tagesuebersicht(summe: speicher.daten.summe(am: tag), ziele: speicher.ziele)
            Wasserkarte(tag: tag)
            ForEach(Mahlzeit.allCases) { mahlzeit in
                Mahlzeitkarte(
                    tag: tag, mahlzeit: mahlzeit,
                    hinzufuegen: { eintragsziel = Eintragsziel(tag: tag, mahlzeit: mahlzeit) },
                    bearbeiten: { bearbeitet = $0 }
                )
            }
        }
        .sheet(item: $eintragsziel) { ziel in
            Eintragen(ziel: ziel)
        }
        .sheet(item: $bearbeitet) { eintrag in
            EintragBearbeiten(eintrag: eintrag)
        }
    }

    private func kopf(_ tag: Tag) -> some View {
        Seitenkopf(titel: tag.kurztitel, untertitel: tag.ausgeschrieben) {
            HStack(spacing: 8) {
                if tag != .heute {
                    Button("Heute") { sitzung.tag = .heute }
                }
                Button {
                    zeigtKalender = true
                } label: {
                    Image(systemName: "calendar")
                }
                .help("Tag auswählen")
                .popover(isPresented: $zeigtKalender, arrowEdge: .bottom) {
                    DatePicker(
                        "Tag",
                        selection: Binding(get: { tag.datum() }, set: { sitzung.tag = Tag($0); zeigtKalender = false }),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(12)
                }
                ControlGroup {
                    Button { sitzung.tag = tag.verschoben(um: -1) } label: { Image(systemName: "chevron.left") }
                        .help("Vorheriger Tag")
                    Button { sitzung.tag = tag.verschoben(um: 1) } label: { Image(systemName: "chevron.right") }
                        .help("Nächster Tag")
                }
                .fixedSize()
                Button {
                    eintragsziel = Eintragsziel(tag: tag, mahlzeit: tag == .heute ? .passend() : .fruehstueck)
                } label: {
                    Label("Essen eintragen", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// Der Tag auf einen Blick: Kalorien als Ring, Makros daneben, die übrigen Werte darunter.
struct Tagesuebersicht: View {
    let summe: Naehrwerte
    let ziele: Tagesziele

    var body: some View {
        Karte(innen: 24) {
            VStack(spacing: 22) {
                HStack(alignment: .center, spacing: 36) {
                    VStack(spacing: 10) {
                        Kalorienring(gegessen: summe, ziel: ziele[.kcal])
                        Text("\(Zahl.ganz(summe.kcal)) von \(Zahl.ganz(ziele[.kcal])) kcal gegessen")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    VStack(spacing: 20) {
                        ForEach(Naehrstoff.makros) { stoff in
                            Naehrstoffzeile(stoff: stoff, wert: summe[stoff], ziel: ziele[stoff])
                        }
                    }
                }
                Divider()
                HStack(alignment: .top, spacing: 28) {
                    ForEach(Naehrstoff.weitere) { stoff in
                        Naehrstoffzeile(stoff: stoff, wert: summe[stoff], ziel: ziele[stoff], gross: false)
                    }
                }
            }
        }
    }
}

struct Wasserkarte: View {
    @Environment(Speicher.self) private var speicher
    let tag: Tag

    var body: some View {
        let getrunken = speicher.daten.wasser(am: tag)
        let ziel = speicher.ziele.wasserMl
        let glas = speicher.einstellungen.glasMl
        Karte(innen: 16) {
            HStack(spacing: 14) {
                Image(systemName: "drop.fill")
                    .font(.title3)
                    .foregroundStyle(Farbe.wasser)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text("Wasser").font(.headline)
                        if getrunken >= ziel { Statuszeichen(status: .erreicht).font(.caption) }
                    }
                    Text("\(Zahl.liter(getrunken)) von \(Zahl.liter(ziel))")
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
                .frame(width: 150, alignment: .leading)
                Messbalken(anteil: ziel > 0 ? Double(getrunken) / Double(ziel) : 0, farbe: Farbe.wasser, hoehe: 8)
                HStack(spacing: 6) {
                    Button {
                        speicher.aendereWasser(um: -glas, am: tag)
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(getrunken == 0)
                    .help("Ein Glas abziehen")
                    Button {
                        speicher.aendereWasser(um: glas, am: tag)
                    } label: {
                        Label("\(glas) ml", systemImage: "plus")
                    }
                    .help("Ein Glas hinzufügen")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct Mahlzeitkarte: View {
    @Environment(Speicher.self) private var speicher
    let tag: Tag
    let mahlzeit: Mahlzeit
    let hinzufuegen: () -> Void
    let bearbeiten: (Eintrag) -> Void

    var body: some View {
        let eintraege = speicher.daten.eintraege(am: tag, mahlzeit: mahlzeit)
        let summe = eintraege.reduce(Naehrwerte.null) { $0 + $1.naehrwerte }
        Karte(innen: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: mahlzeit.symbol)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    Text(mahlzeit.name).font(.headline)
                    Spacer()
                    if !eintraege.isEmpty {
                        Makrokurzform(werte: summe)
                        Text("\(Zahl.ganz(summe.kcal)) kcal")
                            .fontWeight(.medium)
                            .monospacedDigit()
                            .frame(width: 84, alignment: .trailing)
                    }
                    Button(action: hinzufuegen) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Zu \(mahlzeit.name) hinzufügen")
                    .frame(width: 24)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                if eintraege.isEmpty {
                    leer
                } else {
                    ForEach(eintraege) { eintrag in
                        Divider().padding(.leading, 54)
                        Eintragszeile(eintrag: eintrag, bearbeiten: { bearbeiten(eintrag) })
                    }
                }
            }
        }
    }

    /// Bietet an, die gleiche Mahlzeit vom Vortag zu übernehmen – Frühstück ist oft jeden Tag dasselbe.
    @ViewBuilder private var leer: some View {
        let gestern = tag.verschoben(um: -1)
        let vorlage = speicher.daten.eintraege(am: gestern, mahlzeit: mahlzeit)
        if !vorlage.isEmpty {
            Divider().padding(.leading, 54)
            HStack {
                Button {
                    speicher.kopiere(mahlzeit, von: gestern, nach: tag)
                } label: {
                    Label("Wie am Vortag: \(vorlage.map(\.name).joined(separator: ", "))", systemImage: "arrow.uturn.forward")
                        .lineLimit(1)
                }
                .buttonStyle(.link)
                Spacer()
            }
            .padding(.leading, 54)
            .padding(.trailing, 20)
            .padding(.vertical, 10)
        }
    }
}

struct Eintragszeile: View {
    @Environment(Speicher.self) private var speicher
    let eintrag: Eintrag
    let bearbeiten: () -> Void
    @State private var beruehrt = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: bearbeiten) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(eintrag.name).lineLimit(1)
                        Text("\(Zahl.knapp(eintrag.menge)) \(eintrag.einheit)")
                            .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Spacer(minLength: 8)
                    Makrokurzform(werte: eintrag.naehrwerte)
                    Text("\(Zahl.ganz(eintrag.naehrwerte.kcal)) kcal")
                        .monospacedDigit()
                        .frame(width: 84, alignment: .trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Bearbeiten")

            Menu {
                aktionen
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 24)
            .opacity(beruehrt ? 1 : 0.25)
        }
        .padding(.leading, 54)
        .padding(.trailing, 20)
        .padding(.vertical, 9)
        .background(beruehrt ? Color.primary.opacity(0.04) : .clear)
        .onHover { beruehrt = $0 }
        .contextMenu { aktionen }
    }

    @ViewBuilder private var aktionen: some View {
        Button("Bearbeiten …", action: bearbeiten)
        Button("Duplizieren") { speicher.dupliziere(eintrag, nach: eintrag.tag, mahlzeit: eintrag.mahlzeit) }
        Menu("Verschieben nach") {
            ForEach(Mahlzeit.allCases.filter { $0 != eintrag.mahlzeit }) { ziel in
                Button(ziel.name) {
                    var neu = eintrag
                    neu.mahlzeit = ziel
                    speicher.aendere(eintrag: neu)
                }
            }
        }
        if eintrag.tag != .heute {
            Button("Heute noch einmal eintragen") { speicher.dupliziere(eintrag, nach: .heute, mahlzeit: eintrag.mahlzeit) }
        }
        Button("In meine Lebensmittel übernehmen") {
            speicher.merke(Lebensmittel(
                name: eintrag.name, menge: eintrag.menge, einheit: eintrag.einheit, naehrwerte: eintrag.naehrwerte,
                quelle: eintrag.quelle
            ))
        }
        .disabled(speicher.istGemerkt(name: eintrag.name, marke: ""))
        Divider()
        Button("Löschen", role: .destructive) { speicher.loesche(eintrag: eintrag.id) }
    }
}
