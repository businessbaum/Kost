import AppKit
import KostKern
import SwiftUI

// MARK: - Farben

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// Eigene Stufe je Erscheinungsbild – dieselbe Farbe wirkt auf Dunkel sonst zu grell oder zu matt.
    init(hell: UInt32, dunkel: UInt32) {
        self.init(nsColor: NSColor(name: nil) { erscheinung in
            let istDunkel = erscheinung.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(Color(hex: istDunkel ? dunkel : hell))
        })
    }
}

/// Farbe trägt hier nur zwei Bedeutungen: welches Makro gemeint ist und ob ein Ziel verfehlt wurde.
/// Alles andere bleibt in den Grautönen des Systems.
enum Farbe {
    // Drei Töne, die auch bei Rot-Grün-Schwäche unterscheidbar bleiben (auf beiden Hintergründen geprüft).
    static let eiweiss = Color(hell: 0x2A78D6, dunkel: 0x3987E5)
    static let kohlenhydrate = Color(hell: 0xEB6834, dunkel: 0xD95926)
    static let fett = Color(hell: 0x1BAF7A, dunkel: 0x199E70)

    static let gut = Color(hex: 0x0CA30C)
    static let warnung = Color(hex: 0xFAB219)
    static let kritisch = Color(hex: 0xD03B3B)

    static let wasser = Color(hell: 0x3987E5, dunkel: 0x5598E7)
    /// Füllung für Werte ohne eigene Farbe (Ballaststoffe, Zucker, Salz, Kalorienbalken).
    static let neutral = Color.primary.opacity(0.55)

    static let flaeche = Color(nsColor: .windowBackgroundColor)
    static let karte = Color(hell: 0xFFFFFF, dunkel: 0x1E1E1E)
    static let linie = Color.primary.opacity(0.08)
    static let spur = Color.primary.opacity(0.07)

    static func fuer(_ stoff: Naehrstoff) -> Color {
        switch stoff {
        case .eiweiss: eiweiss
        case .kohlenhydrate: kohlenhydrate
        case .fett: fett
        default: neutral
        }
    }
}

enum Mass {
    static let kartenradius: CGFloat = 14
    static let karteninnen: CGFloat = 20
    static let abstand: CGFloat = 16
    static let seitenrand: CGFloat = 32
    static let seitenbreite: CGFloat = 860
}

// MARK: - Zahlen und Daten

enum Zahl {
    static func ganz(_ wert: Double) -> String {
        wert.rounded().formatted(.number.precision(.fractionLength(0)))
    }

    /// Mengen und Gewichte: höchstens eine Nachkommastelle, keine überflüssige Null.
    static func knapp(_ wert: Double, stellen: Int = 1) -> String {
        wert.formatted(.number.precision(.fractionLength(0...stellen)))
    }

    static func wert(_ wert: Double, _ stoff: Naehrstoff) -> String {
        stoff.nachkommastellen == 0 ? ganz(wert) : knapp(wert, stellen: stoff.nachkommastellen)
    }

    /// Körpergewicht: immer eine Nachkommastelle, damit Spalten ruhig bleiben.
    static func kg(_ wert: Double) -> String {
        wert.formatted(.number.precision(.fractionLength(1)))
    }

    static func liter(_ ml: Int) -> String {
        (Double(ml) / 1000).formatted(.number.precision(.fractionLength(0...2))) + " l"
    }

    static func prozent(_ anteil: Double) -> String {
        (anteil * 100).rounded().formatted(.number.precision(.fractionLength(0))) + " %"
    }

    static func mitVorzeichen(_ wert: Double, stellen: Int = 1) -> String {
        let text = knapp(abs(wert), stellen: stellen)
        if wert > 0 { return "+" + text }
        if wert < 0 { return "−" + text }
        return text
    }

    /// Text für Eingabefelder: ohne Tausenderpunkt, damit das Wiedereinlesen eindeutig bleibt.
    static func eingabe(_ wert: Double, stellen: Int) -> String {
        wert.formatted(.number.precision(.fractionLength(0...stellen)).grouping(.never))
    }

    /// Liest "82,5" wie "82.5". Ein Punkt vor genau drei Schlussziffern gilt als Tausenderpunkt ("1.200").
    static func lies(_ text: String) -> Double? {
        var roh = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "")
        guard !roh.isEmpty else { return nil }
        if roh.contains(","), roh.contains(".") {
            roh = roh.replacingOccurrences(of: ".", with: "")
        } else if let punkt = roh.firstIndex(of: "."), roh.filter({ $0 == "." }).count == 1 {
            let davor = roh[..<punkt], danach = roh[roh.index(after: punkt)...]
            if danach.count == 3, !davor.isEmpty, davor != "0", Locale.current.decimalSeparator == "," {
                roh.remove(at: punkt)
            }
        }
        return Double(roh.replacingOccurrences(of: ",", with: "."))
    }
}

extension Tag {
    /// "Heute", "Gestern", "Morgen" oder der Wochentag.
    var kurztitel: String {
        switch Tag.heute.abstand(zu: self) {
        case 0: "Heute"
        case -1: "Gestern"
        case 1: "Morgen"
        default: datum().formatted(.dateTime.weekday(.wide))
        }
    }

    /// "Montag, 12. Oktober" – mit Jahr, wenn es nicht das laufende ist.
    var ausgeschrieben: String {
        let stil = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide)
        return datum().formatted(jahr == Tag.heute.jahr ? stil : stil.year())
    }

    var kurzdatum: String { datum().formatted(.dateTime.day().month(.abbreviated)) }

    /// "Heute", "Gestern" oder das kurze Datum – für Listen, in denen der Wochentag zu wenig sagt.
    var nah: String {
        switch Tag.heute.abstand(zu: self) {
        case 0: "Heute"
        case -1: "Gestern"
        case 1: "Morgen"
        default: kurzdatum
        }
    }
}

extension Mahlzeit {
    var symbol: String {
        switch self {
        case .fruehstueck: "cup.and.saucer"
        case .mittagessen: "fork.knife"
        case .abendessen: "moon.stars"
        case .snack: "carrot"
        }
    }
}

// MARK: - Bausteine

struct Karte<Inhalt: View>: View {
    var innen: CGFloat = Mass.karteninnen
    @ViewBuilder var inhalt: Inhalt

    var body: some View {
        inhalt
            .padding(innen)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Farbe.karte, in: RoundedRectangle(cornerRadius: Mass.kartenradius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Mass.kartenradius, style: .continuous).strokeBorder(Farbe.linie))
    }
}

/// Seitenrahmen: scrollbar, mittig, mit einer Lesebreite, die auch im großen Fenster nicht ausfranst.
struct Seite<Inhalt: View>: View {
    @ViewBuilder var inhalt: Inhalt

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Mass.abstand) { inhalt }
                .frame(maxWidth: Mass.seitenbreite, alignment: .leading)
                .padding(.horizontal, Mass.seitenrand)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
        }
        .background(Farbe.flaeche)
    }
}

struct Seitenkopf<Rechts: View>: View {
    let titel: String
    var untertitel: String = ""
    @ViewBuilder var rechts: Rechts

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titel).font(.system(size: 28, weight: .bold))
                if !untertitel.isEmpty {
                    Text(untertitel).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            rechts
        }
        .padding(.bottom, 4)
    }
}

extension Seitenkopf where Rechts == EmptyView {
    init(titel: String, untertitel: String = "") {
        self.init(titel: titel, untertitel: untertitel) { EmptyView() }
    }
}

struct Kartentitel: View {
    let text: String
    var body: some View {
        Text(text).font(.headline)
    }
}

/// Schmaler Fortschrittsbalken. Die Spur ist ein heller Ton derselben Farbe, damit Balken und Rest zusammengehören.
struct Messbalken: View {
    let anteil: Double
    var farbe: Color = Farbe.neutral
    var hoehe: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let breite = geo.size.width * min(max(anteil, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(farbe.opacity(0.16))
                if anteil > 0 {
                    Capsule().fill(farbe).frame(width: max(breite, hoehe))
                }
            }
        }
        .frame(height: hoehe)
        .accessibilityHidden(true)
    }
}

/// Zeichen für den Zielstatus – immer Symbol plus Farbe, nie Farbe allein.
struct Statuszeichen: View {
    let status: Zielstatus

    var body: some View {
        switch status {
        case .erreicht:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Farbe.gut).help("Ziel erreicht")
        case .ueberschritten:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Farbe.kritisch).help("Über dem Ziel")
        case .offen, .imRahmen:
            EmptyView()
        }
    }
}

/// Wert mit Ziel und Balken – die Grundform für jeden Nährstoff im Tagebuch.
struct Naehrstoffzeile: View {
    let stoff: Naehrstoff
    let wert: Double
    let ziel: Double
    var gross = true

    private var status: Zielstatus { .bestimme(wert: wert, ziel: ziel, richtung: stoff.richtung) }
    private var fuellung: Color { status == .ueberschritten ? Farbe.kritisch : Farbe.fuer(stoff) }

    var body: some View {
        VStack(alignment: .leading, spacing: gross ? 7 : 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if gross {
                    Circle().fill(Farbe.fuer(stoff)).frame(width: 8, height: 8).offset(y: -1)
                }
                Text(gross ? stoff.name : stoff.kurz)
                    .font(gross ? .body : .callout)
                    .foregroundStyle(gross ? .primary : .secondary)
                    .lineLimit(1)
                Statuszeichen(status: status).font(.caption)
                Spacer(minLength: 4)
                (Text(Zahl.wert(wert, stoff)).fontWeight(.semibold).foregroundStyle(.primary)
                    + Text(" / \(Zahl.wert(ziel, stoff)) \(stoff.einheit)").foregroundStyle(.secondary))
                    .font(gross ? .body : .callout)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Messbalken(anteil: ziel > 0 ? wert / ziel : 0, farbe: fuellung, hoehe: gross ? 6 : 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stoff.name): \(Zahl.wert(wert, stoff)) von \(Zahl.wert(ziel, stoff)) \(stoff.einheit)")
    }
}

/// Kalorienring: Der Bogen wächst mit dem Gegessenen bis zum Tagesziel und zeigt in drei Farben,
/// aus welchen Makros die Energie stammt.
struct Kalorienring: View {
    let gegessen: Naehrwerte
    let ziel: Double
    var durchmesser: CGFloat = 176
    var staerke: CGFloat = 14

    private var rest: Double { ziel - gegessen.kcal }

    /// Bogenstücke als Anteil am vollen Kreis.
    private var stuecke: [(farbe: Color, von: Double, bis: Double)] {
        let anteile = Zeitraum.energieanteile(gegessen)
        let gefuellt = ziel > 0 ? min(gegessen.kcal / ziel, 1) : 0
        guard gefuellt > 0 else { return [] }
        // Lücke von 2 Punkt zwischen den Stücken, in Kreisanteilen
        let luecke = 2 / (Double.pi * Double(durchmesser - staerke))
        var start = 0.0
        var ergebnis: [(Color, Double, Double)] = []
        let teile: [(Color, Double)] = [(Farbe.eiweiss, anteile.eiweiss), (Farbe.kohlenhydrate, anteile.kohlenhydrate), (Farbe.fett, anteile.fett)]
        let sichtbar = teile.filter { $0.1 > 0 }
        // Ohne Makroangaben (nur Kalorien eingetragen) bleibt der Bogen neutral.
        guard !sichtbar.isEmpty else { return [(Farbe.neutral, 0, gefuellt)] }
        for (farbe, anteil) in sichtbar {
            let ende = start + anteil * gefuellt
            if ende - start > luecke { ergebnis.append((farbe, start, ende - luecke)) }
            start = ende
        }
        return ergebnis
    }

    var body: some View {
        ZStack {
            Circle().stroke(Farbe.spur, lineWidth: staerke)
            ForEach(Array(stuecke.enumerated()), id: \.offset) { _, stueck in
                Circle()
                    .trim(from: stueck.von, to: stueck.bis)
                    .stroke(stueck.farbe, style: StrokeStyle(lineWidth: staerke, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text(Zahl.ganz(abs(rest)))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text(rest >= 0 ? "kcal übrig" : "kcal drüber")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(staerke / 2)
        .frame(width: durchmesser, height: durchmesser)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rest >= 0 ? "\(Zahl.ganz(rest)) Kalorien übrig" : "\(Zahl.ganz(-rest)) Kalorien über dem Ziel")
    }
}

/// Kennzahl mit Beschriftung – für die Reihen oben in Auswertung und Gewicht.
struct Kennzahl: View {
    let titel: String
    let wert: String
    var einheit: String = ""
    var zusatz: String = ""

    var body: some View {
        Karte(innen: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(titel).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(wert).font(.system(size: 26, weight: .semibold, design: .rounded))
                    if !einheit.isEmpty { Text(einheit).font(.callout).foregroundStyle(.secondary) }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Text(zusatz.isEmpty ? " " : zusatz).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

/// Die drei Makros in einer Zeile mit Farbpunkt – kompakt für Listen.
struct Makrokurzform: View {
    let werte: Naehrwerte

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Naehrstoff.makros) { stoff in
                HStack(spacing: 4) {
                    Circle().fill(Farbe.fuer(stoff)).frame(width: 6, height: 6)
                    Text(Zahl.ganz(werte[stoff])).monospacedDigit().lineLimit(1)
                }
                // feste Spalten, damit die Punkte in Listen untereinander stehen
                .frame(width: 42, alignment: .leading)
                .help("\(stoff.name): \(Zahl.knapp(werte[stoff])) g")
            }
        }
        .fixedSize()
        .font(.callout)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Eiweiß \(Zahl.ganz(werte.eiweiss)), Kohlenhydrate \(Zahl.ganz(werte.kohlenhydrate)), Fett \(Zahl.ganz(werte.fett)) Gramm")
    }
}

/// Erklärt die Farbpunkte der Makrokurzform einmal je Liste.
struct Makrolegende: View {
    var body: some View {
        HStack(spacing: 12) {
            ForEach(Naehrstoff.makros) { stoff in
                HStack(spacing: 4) {
                    Circle().fill(Farbe.fuer(stoff)).frame(width: 6, height: 6)
                    Text(stoff.name)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct Leerzustand: View {
    let symbol: String
    let titel: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
            Text(titel).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

// MARK: - Zahleneingabe

/// Zahlenfeld, das bei jedem Tastendruck in die Bindung schreibt. Das eingebaute Zahlenfeld übernimmt
/// erst bei Return oder Fokuswechsel – ein Klick auf "Weiter" direkt nach dem Tippen ginge sonst verloren.
struct Zahlenfeld: View {
    @Binding var wert: Double
    var einheit: String = ""
    var stellen: Int = 1
    var breite: CGFloat = 76
    var bereich: ClosedRange<Double> = 0...99_999

    @State private var text = ""
    @FocusState private var hatFokus: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: breite)
                .focused($hatFokus)
                .onChange(of: text) { _, neu in
                    guard let zahl = Zahl.lies(neu) else { return }
                    let begrenzt = min(max(zahl, bereich.lowerBound), bereich.upperBound)
                    if begrenzt != wert { wert = begrenzt }
                }
                .onChange(of: wert) { _, neu in
                    // Von außen geändert (etwa beim Umrechnen): Text nachziehen, aber nicht mitten im Tippen.
                    if !hatFokus { text = Zahl.eingabe(neu, stellen: stellen) }
                }
                .onChange(of: hatFokus) { _, fokus in
                    if !fokus { text = Zahl.eingabe(wert, stellen: stellen) }
                }
                .onAppear { text = Zahl.eingabe(wert, stellen: stellen) }
            if !einheit.isEmpty {
                Text(einheit).foregroundStyle(.secondary)
            }
        }
    }
}

/// Wie `Zahlenfeld`, aber leer erlaubt (kein Wert).
struct WahlfreiesZahlenfeld: View {
    @Binding var wert: Double?
    var einheit: String = ""
    var stellen: Int = 1
    var breite: CGFloat = 76
    var platzhalter: String = "–"

    @State private var text = ""
    @FocusState private var hatFokus: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField(platzhalter, text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: breite)
                .focused($hatFokus)
                .onChange(of: text) { _, neu in
                    let zahl = Zahl.lies(neu).flatMap { $0 > 0 ? $0 : nil }
                    if zahl != wert { wert = zahl }
                }
                .onChange(of: hatFokus) { _, fokus in
                    if !fokus { text = wert.map { Zahl.eingabe($0, stellen: stellen) } ?? "" }
                }
                .onAppear { text = wert.map { Zahl.eingabe($0, stellen: stellen) } ?? "" }
            if !einheit.isEmpty {
                Text(einheit).foregroundStyle(.secondary)
            }
        }
    }
}

/// Die acht Nährwertfelder in zwei Spalten, wie auf einem Etikett gelesen.
struct Naehrwertfelder: View {
    @Binding var werte: Naehrwerte

    private let reihen: [(Naehrstoff, String, Naehrstoff, String)] = [
        (.kcal, "Kalorien", .eiweiss, "Eiweiß"),
        (.kohlenhydrate, "Kohlenhydrate", .zucker, "davon Zucker"),
        (.fett, "Fett", .gesaettigt, "davon gesättigt"),
        (.ballaststoffe, "Ballaststoffe", .salz, "Salz"),
    ]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            ForEach(reihen, id: \.0) { links, linksName, rechts, rechtsName in
                GridRow {
                    Text(linksName).gridColumnAlignment(.leading)
                    feld(links)
                    Text(rechtsName).padding(.leading, 16)
                    feld(rechts)
                }
            }
        }
    }

    private func feld(_ stoff: Naehrstoff) -> some View {
        Zahlenfeld(
            wert: Binding(get: { werte[stoff] }, set: { werte[stoff] = $0 }),
            einheit: stoff.einheit, stellen: stoff == .kcal ? 0 : 1
        )
    }
}
