import Charts
import KostKern
import SwiftUI

struct GewichtAnsicht: View {
    @Environment(Speicher.self) private var speicher
    @State private var eingabe: Double?
    @State private var tag: Tag = .heute

    var body: some View {
        let wiegen = speicher.daten.gewichte
        let profil = speicher.profil

        Seite {
            Seitenkopf(titel: "Gewicht", untertitel: "Am aussagekräftigsten morgens, nüchtern und immer zur gleichen Zeit.")

            Karte(innen: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "scalemass").font(.title3).foregroundStyle(.secondary).frame(width: 24)
                    Text("Gewogen").font(.headline)
                    WahlfreiesZahlenfeld(wert: $eingabe, einheit: "kg", platzhalter: letztesAlsText)
                    Picker("Tag", selection: $tag) {
                        ForEach(0..<7, id: \.self) { zurueck in
                            let wahl = Tag.heute.verschoben(um: -zurueck)
                            Text(zurueck < 2 ? wahl.kurztitel : wahl.ausgeschrieben).tag(wahl)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                    Button("Eintragen") {
                        if let eingabe, (30...300).contains(eingabe) {
                            speicher.setzeGewicht(eingabe, am: tag)
                            self.eingabe = nil
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!(eingabe.map { (30...300).contains($0) } ?? false))
                }
            }

            if let letztes = wiegen.last, let erstes = wiegen.first, let profil {
                let bmi = Bedarfsrechner.bmi(gewichtKg: letztes.kg, groesseCm: profil.groesseCm)
                let trend = Gewichtstrend.kgProWoche(wiegen, bis: .heute)
                HStack(spacing: Mass.abstand) {
                    Kennzahl(titel: "Aktuell", wert: Zahl.kg(letztes.kg), einheit: "kg", zusatz: letztes.tag.nah)
                    Kennzahl(
                        titel: "Seit Beginn", wert: Zahl.mitVorzeichen(letztes.kg - erstes.kg), einheit: "kg",
                        zusatz: "seit \(erstes.tag.kurzdatum)"
                    )
                    Kennzahl(
                        titel: "Trend", wert: trend.map { Zahl.mitVorzeichen($0, stellen: 2) } ?? "–", einheit: trend == nil ? "" : "kg/Woche",
                        zusatz: trend == nil ? "ab drei Wägungen über eine Woche" : "letzte vier Wochen"
                    )
                    Kennzahl(titel: "BMI", wert: Zahl.knapp(bmi), zusatz: Bedarfsrechner.bmiEinordnung(bmi))
                }

                Karte {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            Kartentitel(text: "Verlauf")
                            Spacer()
                            if let zielgewicht = profil.zielgewichtKg {
                                let rest = letztes.kg - zielgewicht
                                Text(abs(rest) < 0.05 ? "Zielgewicht erreicht" : "noch \(Zahl.knapp(abs(rest))) kg bis \(Zahl.knapp(zielgewicht)) kg")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        if wiegen.count >= 2 {
                            Gewichtsverlauf(wiegen: wiegen, zielgewicht: profil.zielgewichtKg)
                        } else {
                            Text("Mit der zweiten Wägung erscheint hier dein Verlauf.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 80)
                        }
                    }
                }

                Karte(innen: 0) {
                    VStack(spacing: 0) {
                        HStack {
                            Kartentitel(text: "Wägungen")
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        ForEach(Array(wiegen.reversed().prefix(12))) { eintrag in
                            Divider().padding(.leading, 20)
                            Waegungszeile(eintrag: eintrag, vorher: vorgaenger(von: eintrag, in: wiegen), loeschbar: wiegen.count > 1)
                        }
                    }
                }
            } else {
                Karte {
                    Leerzustand(symbol: "scalemass", titel: "Noch keine Wägung", text: "Trag oben dein Gewicht ein. Die Tagesziele rechnen immer mit der jüngsten Wägung.")
                }
            }
        }
    }

    private var letztesAlsText: String {
        speicher.daten.gewichte.last.map { Zahl.eingabe($0.kg, stellen: 1) } ?? "–"
    }

    private func vorgaenger(von eintrag: Gewichtseintrag, in wiegen: [Gewichtseintrag]) -> Gewichtseintrag? {
        guard let stelle = wiegen.firstIndex(of: eintrag), stelle > 0 else { return nil }
        return wiegen[stelle - 1]
    }
}

private struct Waegungszeile: View {
    @Environment(Speicher.self) private var speicher
    let eintrag: Gewichtseintrag
    let vorher: Gewichtseintrag?
    let loeschbar: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(eintrag.tag.ausgeschrieben)
            Spacer()
            if let vorher {
                Text("\(Zahl.mitVorzeichen(eintrag.kg - vorher.kg)) kg")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            Text("\(Zahl.kg(eintrag.kg)) kg")
                .monospacedDigit()
                .frame(width: 84, alignment: .trailing)
            Button {
                speicher.loescheGewicht(am: eintrag.tag)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(!loeschbar)
            .help(loeschbar ? "Wägung löschen" : "Die letzte Wägung bleibt, weil die Ziele damit rechnen")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
    }
}

private struct Gewichtsverlauf: View {
    let wiegen: [Gewichtseintrag]
    let zielgewicht: Double?

    @State private var gewaehlt: Date?

    private var bereich: ClosedRange<Double> {
        var werte = wiegen.map(\.kg)
        if let zielgewicht { werte.append(zielgewicht) }
        let unten = werte.min() ?? 0, oben = werte.max() ?? 1
        let rand = max(1, (oben - unten) * 0.15)
        return (unten - rand).rounded(.down)...(oben + rand).rounded(.up)
    }

    /// Die Wägung, die dem Mauszeiger am nächsten liegt.
    private var naechste: Gewichtseintrag? {
        guard let gewaehlt else { return nil }
        return wiegen.min { abs($0.tag.datum().timeIntervalSince(gewaehlt)) < abs($1.tag.datum().timeIntervalSince(gewaehlt)) }
    }

    var body: some View {
        Chart {
            if let zielgewicht {
                RuleMark(y: .value("Zielgewicht", zielgewicht))
                    .foregroundStyle(Color.primary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .trailing, spacing: 3) {
                        Text("Ziel \(Zahl.knapp(zielgewicht)) kg").font(.caption).foregroundStyle(.secondary)
                    }
            }
            ForEach(wiegen) { eintrag in
                LineMark(x: .value("Tag", eintrag.tag.datum(), unit: .day), y: .value("Gewicht", eintrag.kg))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Color.primary.opacity(0.75))
            }
            // Punkte nur, solange sie einzeln erkennbar bleiben
            if wiegen.count <= 40 {
                ForEach(wiegen) { eintrag in
                    PointMark(x: .value("Tag", eintrag.tag.datum(), unit: .day), y: .value("Gewicht", eintrag.kg))
                        .symbol {
                            Circle().fill(Color.primary.opacity(0.75)).frame(width: 8, height: 8)
                                .overlay(Circle().stroke(Farbe.karte, lineWidth: 2))
                        }
                }
            }
            if let eintrag = naechste {
                PointMark(x: .value("Tag", eintrag.tag.datum(), unit: .day), y: .value("Gewicht", eintrag.kg))
                    .symbol {
                        Circle().fill(Color.primary).frame(width: 11, height: 11)
                            .overlay(Circle().stroke(Farbe.karte, lineWidth: 2))
                    }
                    .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(eintrag.tag.ausgeschrieben).font(.caption).foregroundStyle(.secondary)
                            Text("\(Zahl.kg(eintrag.kg)) kg").font(.callout.weight(.semibold)).monospacedDigit()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Farbe.karte, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Farbe.linie))
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    }
            }
        }
        .chartYScale(domain: bereich)
        .chartXAxis {
            // "aligned" hält die Randbeschriftungen innerhalb der Zeichenfläche
            AxisMarks(preset: .aligned, values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Farbe.linie)
                AxisValueLabel()
            }
        }
        .chartXSelection(value: $gewaehlt)
        .frame(height: 230)
    }
}
