import Charts
import KostKern
import SwiftUI

struct AuswertungAnsicht: View {
    @Environment(Speicher.self) private var speicher
    @Environment(Sitzung.self) private var sitzung
    @State private var spanne = 7

    var body: some View {
        let bis = Tag.heute
        let von = bis.verschoben(um: -(spanne - 1))
        let zeitraum = speicher.daten.zeitraum(von: von, bis: bis)
        let ziele = speicher.ziele

        Seite {
            Seitenkopf(titel: "Auswertung", untertitel: "\(von.kurzdatum) bis \(bis.kurzdatum)") {
                Picker("Zeitraum", selection: $spanne) {
                    Text("7 Tage").tag(7)
                    Text("30 Tage").tag(30)
                    Text("90 Tage").tag(90)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            if zeitraum.erfassteTage == 0 {
                Karte {
                    Leerzustand(symbol: "chart.bar", titel: "Noch keine Einträge in diesem Zeitraum", text: "Sobald du etwas ins Tagebuch einträgst, siehst du hier Durchschnitte und Verlauf.")
                }
            } else {
                let schnitt = zeitraum.schnitt
                HStack(spacing: Mass.abstand) {
                    Kennzahl(titel: "Kalorien im Schnitt", wert: Zahl.ganz(schnitt.kcal), einheit: "kcal", zusatz: "Ziel \(Zahl.ganz(ziele[.kcal])) kcal")
                    Kennzahl(titel: "Erfasste Tage", wert: "\(zeitraum.erfassteTage)", einheit: "von \(spanne)", zusatz: "")
                    Kennzahl(titel: "Serie", wert: "\(speicher.daten.serie(bis: bis))", einheit: speicher.daten.serie(bis: bis) == 1 ? "Tag" : "Tage", zusatz: "in Folge eingetragen")
                    Kennzahl(titel: "Wasser im Schnitt", wert: zeitraum.wasserSchnitt > 0 ? Zahl.liter(zeitraum.wasserSchnitt) : "–", zusatz: "Ziel \(Zahl.liter(ziele.wasserMl))")
                }

                Karte {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            Kartentitel(text: "Kalorien pro Tag")
                            Spacer()
                            Makrolegende()
                        }
                        Kalorienverlauf(tage: zeitraum.tage, ziel: ziele[.kcal]) { sitzung.zeige($0) }
                    }
                }

                Karte {
                    VStack(alignment: .leading, spacing: 14) {
                        Kartentitel(text: "Woher die Energie kommt")
                        Energieverteilung(schnitt: schnitt, ziele: ziele.naehrwerte)
                    }
                }

                Karte {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            Kartentitel(text: "Durchschnitt pro Tag")
                            Spacer()
                            Text("über \(zeitraum.erfassteTage) erfasste \(zeitraum.erfassteTage == 1 ? "Tag" : "Tage")")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        HStack(alignment: .top, spacing: 28) {
                            ForEach(Naehrstoff.makros) { stoff in
                                Naehrstoffzeile(stoff: stoff, wert: schnitt[stoff], ziel: ziele[stoff])
                            }
                        }
                        Divider()
                        HStack(alignment: .top, spacing: 28) {
                            ForEach(Naehrstoff.weitere) { stoff in
                                Naehrstoffzeile(stoff: stoff, wert: schnitt[stoff], ziel: ziele[stoff], gross: false)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Säule je Tag, gestapelt nach Makros – dieselbe Aufteilung wie der Ring im Tagebuch.
private struct Kalorienverlauf: View {
    let tage: [Tagesbilanz]
    let ziel: Double
    let oeffne: (Tag) -> Void

    @State private var gewaehlt: Date?

    private static let hoehe: CGFloat = 230

    private struct Stueck: Identifiable {
        let tag: Tag
        let farbe: Color
        let von: Double
        let bis: Double
        let istSpitze: Bool
        let id: String
    }

    private var obergrenze: Double { max(ziel, tage.map(\.summe.kcal).max() ?? 0) * 1.15 }

    /// Energie je Makro, so skaliert, dass die Säule genau die eingetragenen Kalorien hoch ist.
    /// Zwischen den Stücken bleiben 2 Punkt frei – Luft trennt sauberer als ein Rahmen.
    private var stuecke: [Stueck] {
        let luecke = 2 * obergrenze / Double(Self.hoehe - 24)
        return tage.flatMap { bilanz -> [Stueck] in
            let anteile = Zeitraum.energieanteile(bilanz.summe)
            var teile: [(String, Color, Double)] = [
                ("e", Farbe.eiweiss, anteile.eiweiss), ("k", Farbe.kohlenhydrate, anteile.kohlenhydrate), ("f", Farbe.fett, anteile.fett),
            ].filter { $0.2 > 0 }
            // Nur Kalorien eingetragen, keine Makros: eine neutrale Säule.
            if teile.isEmpty, bilanz.summe.kcal > 0 { teile = [("n", Farbe.neutral, 1)] }
            var boden = 0.0
            var ergebnis: [Stueck] = []
            for (stelle, teil) in teile.enumerated() {
                let spitze = stelle == teile.count - 1
                let decke = boden + teil.2 * bilanz.summe.kcal
                let bis = spitze ? decke : decke - luecke
                if bis > boden {
                    ergebnis.append(Stueck(tag: bilanz.tag, farbe: teil.1, von: boden, bis: bis, istSpitze: spitze, id: "\(bilanz.tag.schluessel)-\(teil.0)"))
                }
                boden = decke
            }
            return ergebnis
        }
    }

    private var breite: MarkDimension {
        if tage.count <= 7 { return .fixed(24) }
        if tage.count <= 31 { return .fixed(12) }
        return .ratio(0.7)
    }

    private var gewaehlterTag: Tagesbilanz? {
        guard let gewaehlt else { return nil }
        let tag = Tag(gewaehlt)
        return tage.first { $0.tag == tag && $0.erfasst }
    }

    var body: some View {
        Chart {
            ForEach(stuecke) { stueck in
                BarMark(
                    x: .value("Tag", stueck.tag.datum(), unit: .day),
                    yStart: .value("von", stueck.von),
                    yEnd: .value("bis", stueck.bis),
                    width: breite
                )
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: stueck.istSpitze ? 4 : 0, topTrailingRadius: stueck.istSpitze ? 4 : 0))
                .foregroundStyle(stueck.farbe)
                .opacity(gewaehlterTag == nil || gewaehlterTag?.tag == stueck.tag ? 1 : 0.4)
            }
            RuleMark(y: .value("Ziel", ziel))
                .foregroundStyle(Color.primary.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .annotation(position: .top, alignment: .trailing, spacing: 3) {
                    Text("Ziel \(Zahl.ganz(ziel))").font(.caption).foregroundStyle(.secondary)
                }
            if let tag = gewaehlterTag {
                RuleMark(x: .value("Tag", tag.tag.datum(), unit: .day))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tafel(tag)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: tage.count <= 7 ? 1 : (tage.count <= 31 ? 5 : 14))) { _ in
                AxisValueLabel(format: tage.count <= 7 ? .dateTime.weekday(.abbreviated) : .dateTime.day().month(.abbreviated), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Farbe.linie)
                AxisValueLabel()
            }
        }
        .chartYScale(domain: 0...obergrenze)
        .chartXSelection(value: $gewaehlt)
        .frame(height: Self.hoehe)
        .padding(.top, 34)   // Platz für die Tafel über den Säulen
        .onTapGesture {
            if let tag = gewaehlterTag { oeffne(tag.tag) }
        }
        .help("Klick auf einen Tag öffnet ihn im Tagebuch")
    }

    private func tafel(_ bilanz: Tagesbilanz) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(bilanz.tag.ausgeschrieben).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Text("\(Zahl.ganz(bilanz.summe.kcal)) kcal").font(.callout.weight(.semibold)).monospacedDigit()
                Makrokurzform(werte: bilanz.summe)
            }
        }
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Farbe.karte, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Farbe.linie))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}

/// Anteil der drei Makros an der Energie als ein Balken, darunter Ist und Ziel in Zahlen.
private struct Energieverteilung: View {
    let schnitt: Naehrwerte
    let ziele: Naehrwerte

    var body: some View {
        let ist = Zeitraum.energieanteile(schnitt)
        let soll = Zeitraum.energieanteile(ziele)
        let teile: [(Naehrstoff, Double, Double)] = [
            (.eiweiss, ist.eiweiss, soll.eiweiss), (.kohlenhydrate, ist.kohlenhydrate, soll.kohlenhydrate), (.fett, ist.fett, soll.fett),
        ]
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { geo in
                // 2 Punkt Luft zwischen den Stücken statt eines Rahmens
                let nutzbar = geo.size.width - 4
                HStack(spacing: 2) {
                    ForEach(teile, id: \.0) { stoff, anteil, _ in
                        Rectangle().fill(Farbe.fuer(stoff)).frame(width: max(0, nutzbar * anteil))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)
            .accessibilityHidden(true)

            HStack(alignment: .top, spacing: 0) {
                ForEach(teile, id: \.0) { stoff, anteil, sollAnteil in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Circle().fill(Farbe.fuer(stoff)).frame(width: 8, height: 8)
                            Text(stoff.name).foregroundStyle(.secondary)
                        }
                        .font(.callout)
                        Text(Zahl.prozent(anteil)).font(.system(size: 22, weight: .semibold, design: .rounded))
                        Text("Ziel \(Zahl.prozent(sollAnteil)) · \(Zahl.ganz(schnitt[stoff])) g am Tag")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
