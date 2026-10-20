import KostKern
import SwiftUI

/// Die Lebensmittelseite der Seitenleiste: eigene Sammlung pflegen und Produkte nachschlagen.
struct LebensmittelAnsicht: View {
    enum Reiter: String, CaseIterable, Identifiable {
        case meine = "Meine Lebensmittel"
        case produkte = "Produktsuche"
        var id: String { rawValue }
    }

    @State private var reiter: Reiter = .meine
    @State private var legtAn = false

    var body: some View {
        Seite {
            Seitenkopf(titel: "Lebensmittel", untertitel: "Was du öfter isst, trägst du von hier mit zwei Klicks ein.") {
                Button {
                    legtAn = true
                } label: {
                    Label("Neues Lebensmittel", systemImage: "plus")
                }
            }
            Picker("Ansicht", selection: $reiter) {
                ForEach(Reiter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            switch reiter {
            case .meine: Vorratsliste(ziel: nil)
            case .produkte: Produktliste(ziel: nil)
            }
        }
        .sheet(isPresented: $legtAn) {
            LebensmittelBearbeiten(vorlage: nil)
        }
    }
}

struct Suchfeld: View {
    let platzhalter: String
    @Binding var text: String
    var beimAbschicken: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(platzhalter, text: $text)
                .textFieldStyle(.plain)
                .onSubmit(beimAbschicken)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Suche leeren")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Farbe.karte, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Farbe.linie))
    }
}

// MARK: - Eigene Lebensmittel

/// Gemerkte Lebensmittel und zuletzt Gegessenes. Mit `ziel` trägt ein Klick dort ein, ohne `ziel` wird nachgefragt.
struct Vorratsliste: View {
    @Environment(Speicher.self) private var speicher
    let ziel: Eintragsziel?

    @State private var suche = ""
    @State private var bearbeitet: Lebensmittel?

    var body: some View {
        let gemerkt = speicher.lebensmittelSortiert(suche: suche)
        let zuletzt = speicher.daten.zuletztGegessen().filter {
            suche.trimmingCharacters(in: .whitespaces).isEmpty || $0.name.localizedCaseInsensitiveContains(suche)
        }
        VStack(alignment: .leading, spacing: Mass.abstand) {
            Suchfeld(platzhalter: "In meinen Lebensmitteln suchen", text: $suche)

            if gemerkt.isEmpty && zuletzt.isEmpty {
                Karte {
                    if suche.isEmpty {
                        Leerzustand(
                            symbol: "basket", titel: "Noch nichts gemerkt",
                            text: "Lege ein Lebensmittel an, übernimm einen Tagebucheintrag über sein Menü oder merke dir ein Produkt aus der Produktsuche."
                        )
                    } else {
                        Leerzustand(symbol: "magnifyingglass", titel: "Nichts gefunden", text: "Zu „\(suche)“ ist nichts gemerkt. In der Produktsuche findest du verpackte Lebensmittel.")
                    }
                }
            }

            if !gemerkt.isEmpty {
                Karte(innen: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(gemerkt.enumerated()), id: \.element.id) { stelle, lebensmittel in
                            if stelle > 0 { Divider().padding(.leading, 52) }
                            Lebensmittelzeile(lebensmittel: lebensmittel, ziel: ziel, bearbeiten: { bearbeitet = lebensmittel })
                        }
                    }
                }
            }

            if !zuletzt.isEmpty {
                Text("Zuletzt gegessen").font(.headline).padding(.top, 4)
                Karte(innen: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(zuletzt.enumerated()), id: \.element.id) { stelle, eintrag in
                            if stelle > 0 { Divider().padding(.leading, 20) }
                            Wiederholzeile(eintrag: eintrag, ziel: ziel)
                        }
                    }
                }
            }
        }
        .sheet(item: $bearbeitet) { lebensmittel in
            LebensmittelBearbeiten(vorlage: lebensmittel)
        }
    }
}

struct Lebensmittelzeile: View {
    @Environment(Speicher.self) private var speicher
    let lebensmittel: Lebensmittel
    let ziel: Eintragsziel?
    let bearbeiten: () -> Void

    @State private var fragtMenge = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                speicher.schalteFavorit(lebensmittel.id)
            } label: {
                Image(systemName: lebensmittel.favorit ? "star.fill" : "star")
                    .foregroundStyle(lebensmittel.favorit ? AnyShapeStyle(Farbe.warnung) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.plain)
            .frame(width: 22)
            .help(lebensmittel.favorit ? "Favorit entfernen" : "Als Favorit oben halten")

            VStack(alignment: .leading, spacing: 1) {
                Text(lebensmittel.name).lineLimit(1)
                Text(untertitel).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Makrokurzform(werte: lebensmittel.naehrwerte)
            Text("\(Zahl.ganz(lebensmittel.naehrwerte.kcal)) kcal")
                .monospacedDigit()
                .frame(width: 84, alignment: .trailing)
            Button("Eintragen") { fragtMenge = true }
                .popover(isPresented: $fragtMenge, arrowEdge: .trailing) {
                    Mengenabfrage(lebensmittel: lebensmittel, ziel: ziel) { menge, wohin in
                        speicher.trageEin(lebensmittel, menge: menge, tag: wohin.tag, mahlzeit: wohin.mahlzeit)
                        fragtMenge = false
                    }
                }
            Menu {
                Button("Bearbeiten …", action: bearbeiten)
                Divider()
                Button("Löschen", role: .destructive) { speicher.loesche(lebensmittel: lebensmittel.id) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 24)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
    }

    private var untertitel: String {
        let bezug = "je \(Zahl.knapp(lebensmittel.menge)) \(lebensmittel.einheit)"
        return lebensmittel.marke.isEmpty ? bezug : "\(lebensmittel.marke) · \(bezug)"
    }
}

/// Ein früherer Tagebucheintrag, der sich unverändert noch einmal eintragen lässt.
struct Wiederholzeile: View {
    @Environment(Speicher.self) private var speicher
    let eintrag: Eintrag
    let ziel: Eintragsziel?

    @State private var fragtZiel = false
    @State private var eingetragen = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(eintrag.name).lineLimit(1)
                Text("\(Zahl.knapp(eintrag.menge)) \(eintrag.einheit) · \(eintrag.tag.nah)")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Makrokurzform(werte: eintrag.naehrwerte)
            Text("\(Zahl.ganz(eintrag.naehrwerte.kcal)) kcal")
                .monospacedDigit()
                .frame(width: 84, alignment: .trailing)
            Button(eingetragen ? "Eingetragen" : "Nochmal") {
                if let ziel {
                    speicher.dupliziere(eintrag, nach: ziel.tag, mahlzeit: ziel.mahlzeit)
                    eingetragen = true
                } else {
                    fragtZiel = true
                }
            }
            .disabled(eingetragen)
            .popover(isPresented: $fragtZiel, arrowEdge: .trailing) {
                Zielabfrage(titel: eintrag.name) { wohin in
                    speicher.dupliziere(eintrag, nach: wohin.tag, mahlzeit: wohin.mahlzeit)
                    fragtZiel = false
                }
            }
            Color.clear.frame(width: 24, height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
    }
}

// MARK: - Abfragen im Popover

struct Zielwahl: View {
    @Binding var mahlzeit: Mahlzeit
    @Binding var tag: Tag

    var body: some View {
        HStack(spacing: 8) {
            Picker("Mahlzeit", selection: $mahlzeit) {
                ForEach(Mahlzeit.allCases) { Text($0.name).tag($0) }
            }
            .labelsHidden()
            Picker("Tag", selection: $tag) {
                ForEach(0..<7, id: \.self) { zurueck in
                    let wahl = Tag.heute.verschoben(um: -zurueck)
                    Text(zurueck < 2 ? wahl.kurztitel : wahl.ausgeschrieben).tag(wahl)
                }
            }
            .labelsHidden()
        }
    }
}

struct Zielabfrage: View {
    let titel: String
    let fertig: (Eintragsziel) -> Void
    @State private var mahlzeit: Mahlzeit = .passend()
    @State private var tag: Tag = .heute

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(titel).font(.headline).lineLimit(2)
            Zielwahl(mahlzeit: $mahlzeit, tag: $tag)
            HStack {
                Spacer()
                Button("Eintragen") { fertig(Eintragsziel(tag: tag, mahlzeit: mahlzeit)) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

/// Fragt die verzehrte Menge ab und zeigt sofort, was sie bedeutet.
struct Mengenabfrage: View {
    let lebensmittel: Lebensmittel
    let ziel: Eintragsziel?
    var portion: Double?
    let fertig: (Double, Eintragsziel) -> Void

    @State private var menge: Double
    @State private var mahlzeit: Mahlzeit
    @State private var tag: Tag

    init(lebensmittel: Lebensmittel, ziel: Eintragsziel?, portion: Double? = nil, fertig: @escaping (Double, Eintragsziel) -> Void) {
        self.lebensmittel = lebensmittel
        self.ziel = ziel
        self.portion = portion
        self.fertig = fertig
        _menge = State(initialValue: portion ?? lebensmittel.menge)
        _mahlzeit = State(initialValue: ziel?.mahlzeit ?? .passend())
        _tag = State(initialValue: ziel?.tag ?? .heute)
    }

    private var werte: Naehrwerte { lebensmittel.werte(fuer: menge) }

    /// Naheliegende Mengen zum Anklicken: die Herstellerportion und Vielfache der Bezugsmenge.
    private var schnellmengen: [Double] {
        var mengen: [Double] = []
        if let portion { mengen.append(portion) }
        for faktor in [0.5, 1, 2] { mengen.append(lebensmittel.menge * faktor) }
        var gesehen = Set<Double>()
        return mengen.filter { $0 > 0 && gesehen.insert($0).inserted }.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(lebensmittel.anzeigename).font(.headline).lineLimit(2)
            HStack(spacing: 8) {
                Zahlenfeld(wert: $menge, einheit: lebensmittel.einheit)
                Spacer(minLength: 4)
                ForEach(schnellmengen, id: \.self) { vorschlag in
                    Button(Zahl.knapp(vorschlag)) { menge = vorschlag }
                        .controlSize(.small)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("\(Zahl.ganz(werte.kcal)) kcal").font(.title3.weight(.semibold)).monospacedDigit()
                HStack(spacing: 14) {
                    ForEach(Naehrstoff.makros) { stoff in
                        HStack(spacing: 4) {
                            Circle().fill(Farbe.fuer(stoff)).frame(width: 6, height: 6)
                            Text("\(stoff.name) \(Zahl.knapp(werte[stoff])) g")
                        }
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            if ziel == nil {
                Zielwahl(mahlzeit: $mahlzeit, tag: $tag)
            }
            HStack {
                Spacer()
                Button("Eintragen") { fertig(menge, Eintragsziel(tag: tag, mahlzeit: mahlzeit)) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(menge <= 0)
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}

// MARK: - Produktsuche

/// Suche in Open Food Facts nach Name oder Strichcode-Nummer.
struct Produktliste: View {
    @Environment(Speicher.self) private var speicher
    let ziel: Eintragsziel?

    enum Zustand: Equatable {
        case leer, sucht
        case treffer([Produkt])
        case fehler(String)
    }

    @State private var suche = ""
    @State private var zustand: Zustand = .leer
    @State private var aufgabe: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: Mass.abstand) {
            Suchfeld(platzhalter: "Produktname oder Strichcode-Nummer, dann Return", text: $suche, beimAbschicken: starte)

            switch zustand {
            case .leer:
                Karte {
                    Leerzustand(
                        symbol: "barcode.viewfinder", titel: "Verpackte Produkte nachschlagen",
                        text: "Die Werte stammen von den Etiketten aus Open Food Facts, einer freien Datenbank, die Freiwillige pflegen. Ein kurzer Blick auf die Packung schadet nicht."
                    )
                }
            case .sucht:
                Karte {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Suche läuft …").foregroundStyle(.secondary)
                    }
                }
            case .fehler(let text):
                Karte(innen: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Farbe.warnung)
                        Text(text).fixedSize(horizontal: false, vertical: true)
                    }
                }
            case .treffer(let produkte):
                if produkte.isEmpty {
                    Karte {
                        Leerzustand(symbol: "magnifyingglass", titel: "Nichts gefunden", text: "Versuch es mit weniger Wörtern oder der Marke – oder lass das Essen im Rechner von ChatGPT schätzen.")
                    }
                } else {
                    Karte(innen: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(produkte.enumerated()), id: \.element.id) { stelle, produkt in
                                if stelle > 0 { Divider().padding(.leading, 20) }
                                Produktzeile(produkt: produkt, ziel: ziel)
                            }
                        }
                    }
                    Text("Angaben je 100 g oder 100 ml · Quelle: Open Food Facts (ODbL)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onDisappear { aufgabe?.cancel() }
    }

    private func starte() {
        let begriff = suche.trimmingCharacters(in: .whitespaces)
        guard !begriff.isEmpty else { return }
        aufgabe?.cancel()
        zustand = .sucht
        aufgabe = Task {
            do {
                let produkte = try await Produktsuche.suche(begriff)
                if !Task.isCancelled { zustand = .treffer(produkte) }
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled {
                    zustand = .fehler("Die Produktsuche ist gerade nicht erreichbar. Prüf deine Internetverbindung und versuch es noch einmal.")
                }
            }
        }
    }
}

struct Produktzeile: View {
    @Environment(Speicher.self) private var speicher
    let produkt: Produkt
    let ziel: Eintragsziel?

    @State private var fragtMenge = false

    private var gemerkt: Bool { speicher.istGemerkt(name: produkt.name, marke: produkt.marke) }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(produkt.name).lineLimit(1)
                Text([produkt.marke, produkt.packung].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Makrokurzform(werte: produkt.je100)
            Text("\(Zahl.ganz(produkt.je100.kcal)) kcal")
                .monospacedDigit()
                .frame(width: 84, alignment: .trailing)
            Button("Eintragen") { fragtMenge = true }
                .popover(isPresented: $fragtMenge, arrowEdge: .trailing) {
                    Mengenabfrage(lebensmittel: produkt.alsLebensmittel(), ziel: ziel, portion: produkt.portion) { menge, wohin in
                        speicher.trageEin(produkt.alsLebensmittel(), menge: menge, tag: wohin.tag, mahlzeit: wohin.mahlzeit)
                        fragtMenge = false
                    }
                }
            Button {
                speicher.merke(produkt.alsLebensmittel())
            } label: {
                Image(systemName: gemerkt ? "bookmark.fill" : "bookmark")
            }
            .buttonStyle(.borderless)
            .disabled(gemerkt)
            .frame(width: 24)
            .help(gemerkt ? "Schon in meinen Lebensmitteln" : "In meine Lebensmittel übernehmen")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
    }
}
