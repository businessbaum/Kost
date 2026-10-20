import KostKern
import SwiftUI
import UniformTypeIdentifiers

/// Die Rechnerseite der Seitenleiste.
struct RechnerAnsicht: View {
    @Environment(Sitzung.self) private var sitzung
    @Environment(Speicher.self) private var speicher

    var body: some View {
        Seite {
            if sitzung.kannSchaetzen {
                Seitenkopf(titel: "Rechner", untertitel: "Schreib auf, was du gegessen hast – ChatGPT schätzt Kalorien und Nährwerte.")
                Schaetzblatt(modell: sitzung.rechner, fragtZiel: true)
            } else {
                Seitenkopf(titel: "Rechner", untertitel: "Beschreib oder fotografiere dein Essen – ChatGPT schätzt Kalorien und Nährwerte.")
                Karte { ChatGPTKarte() }
            }
        }
    }
}

/// Eingabe, Schätzung und Ergebnis. Steht als Seite in der Seitenleiste und als Reiter im Eintragen-Blatt.
struct Schaetzblatt: View {
    @Environment(Speicher.self) private var speicher
    @Environment(Sitzung.self) private var sitzung
    @Bindable var modell: Rechnermodell
    /// Mahlzeit und Tag hier wählen lassen (Seite) oder vom umgebenden Blatt vorgeben (Reiter).
    var fragtZiel: Bool
    var nachUebernahme: () -> Void = {}

    @State private var fotoSchwebt = false
    @FocusState private var textHatFokus: Bool

    private let beispiele = [
        "2 Scheiben Vollkornbrot mit Frischkäse und Gurke, dazu ein Glas Orangensaft",
        "Teller Spaghetti Bolognese mit Parmesan",
        "Proteinshake mit 300 ml Milch und einer Banane",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Mass.abstand) {
            eingabe
            if let bestaetigung = modell.bestaetigung {
                meldung(bestaetigung, symbol: "checkmark.circle.fill", farbe: Farbe.gut)
            }
            switch modell.zustand {
            case .laeuft:
                wartet
            case .fehler(let text):
                meldung(text, symbol: "exclamationmark.triangle.fill", farbe: Farbe.warnung)
            case .fertig:
                if !modell.zeilen.isEmpty { ergebnis }
            case .bereit:
                vorschlaege
            }
        }
    }

    // MARK: Eingabe

    private var eingabe: some View {
        Karte(innen: 0) {
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $modell.text)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .focused($textHatFokus)
                        .frame(minHeight: 76, maxHeight: 150)
                        .fixedSize(horizontal: false, vertical: true)
                    if modell.text.isEmpty {
                        Text("Was hast du gegessen?")
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 8)

                if !modell.fotos.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(modell.fotos) { foto in
                            Fotovorschau(bild: foto.vorschau) { modell.entferneFoto(foto.id) }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }

                Divider()
                HStack(spacing: 10) {
                    Button {
                        modell.waehleFotos()
                    } label: {
                        Label("Foto", systemImage: "camera")
                    }
                    .disabled(modell.fotos.count >= Rechnermodell.hoechstensFotos || modell.zustand == .laeuft)
                    .help("Foto der Mahlzeit hinzufügen – oder einfach hierher ziehen")
                    Text("Mengen machen die Schätzung genauer.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if modell.zustand == .laeuft {
                        Button("Abbrechen") { modell.brichAb() }
                    } else {
                        Button {
                            if let schaetzfunktion = sitzung.schaetzfunktion(speicher.einstellungen) {
                                modell.schaetze(mit: schaetzfunktion)
                            }
                        } label: {
                            Label(modell.zeilen.isEmpty ? "Schätzen" : "Neu schätzen", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!modell.kannSchaetzen)
                        .help("Nährwerte schätzen (⌘↩)")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .overlay {
            if fotoSchwebt {
                RoundedRectangle(cornerRadius: Mass.kartenradius, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $fotoSchwebt, perform: nimmFotosAn)
        .onAppear { textHatFokus = true }
    }

    private func nimmFotosAn(_ anbieter: [NSItemProvider]) -> Bool {
        var angenommen = false
        for einer in anbieter {
            if einer.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                angenommen = true
                _ = einer.loadObject(ofClass: URL.self) { datei, _ in
                    guard let datei else { return }
                    Task { @MainActor in modell.fuegeFotoHinzu(datei: datei) }
                }
            } else if einer.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                angenommen = true
                einer.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { daten, _ in
                    guard let daten else { return }
                    Task { @MainActor in modell.fuegeFotoHinzu(daten: daten) }
                }
            }
        }
        return angenommen
    }

    private var vorschlaege: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Zum Beispiel").font(.callout).foregroundStyle(.secondary)
            ForEach(beispiele, id: \.self) { beispiel in
                Button {
                    modell.text = beispiel
                    textHatFokus = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "text.quote").foregroundStyle(.tertiary)
                        Text(beispiel).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private var wartet: some View {
        Karte {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ChatGPT schätzt …")
                    Text("Das dauert meist fünf bis fünfzehn Sekunden.").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func meldung(_ text: String, symbol: String, farbe: Color) -> some View {
        Karte(innen: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: symbol).foregroundStyle(farbe)
                Text(text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
    }

    // MARK: Ergebnis

    private var ergebnis: some View {
        Karte(innen: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("Schätzung").font(.headline)
                    Text(modell.sicherheit.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Farbe.spur, in: Capsule())
                    Spacer()
                    Makrolegende()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                ForEach($modell.zeilen) { $zeile in
                    Divider().padding(.leading, 20)
                    HStack(spacing: 10) {
                        Toggle("Übernehmen", isOn: $zeile.gewaehlt)
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                        TextField("Name", text: $zeile.name)
                            .textFieldStyle(.plain)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Zahlenfeld(wert: $zeile.menge, einheit: zeile.einheit, stellen: 0, breite: 62)
                            .frame(width: 92, alignment: .leading)
                        Makrokurzform(werte: zeile.werte)
                        Text("\(Zahl.ganz(zeile.werte.kcal)) kcal")
                            .monospacedDigit()
                            .frame(width: 84, alignment: .trailing)
                    }
                    .opacity(zeile.gewaehlt ? 1 : 0.45)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }

                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Zusammen").font(.headline)
                        Spacer()
                        Text("\(Zahl.ganz(modell.summe.kcal)) kcal").font(.title3.weight(.semibold)).monospacedDigit()
                    }
                    Wertereihe(werte: modell.summe)
                    if !modell.annahmen.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "info.circle")
                            Text(modell.annahmen).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(20)

                Divider()
                HStack(spacing: 10) {
                    if fragtZiel {
                        Picker("Mahlzeit", selection: $modell.mahlzeit) {
                            ForEach(Mahlzeit.allCases) { Text($0.name).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Picker("Tag", selection: $modell.tag) {
                            ForEach(0..<7, id: \.self) { zurueck in
                                let tag = Tag.heute.verschoben(um: -zurueck)
                                Text(zurueck < 2 ? tag.kurztitel : tag.ausgeschrieben).tag(tag)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    Spacer()
                    Button("Verwerfen") { modell.leere() }
                    Button {
                        if modell.uebernimm(in: speicher) > 0 { nachUebernahme() }
                    } label: {
                        Text(modell.gewaehlte.count == 1 ? "1 Eintrag ins Tagebuch" : "\(modell.gewaehlte.count) Einträge ins Tagebuch")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(modell.gewaehlte.isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
    }
}

/// Alle Nährwerte außer den Kalorien nebeneinander, mit Beschriftung darüber.
struct Wertereihe: View {
    let werte: Naehrwerte

    private let stoffe: [Naehrstoff] = [.eiweiss, .kohlenhydrate, .zucker, .fett, .gesaettigt, .ballaststoffe, .salz]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(stoffe) { stoff in
                VStack(alignment: .leading, spacing: 2) {
                    Text(stoff.kurz).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text("\(Zahl.knapp(werte[stoff])) g").font(.callout.weight(.medium)).monospacedDigit().lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(stoff.name)
            }
        }
    }
}

struct Fotovorschau: View {
    let bild: NSImage
    let entfernen: () -> Void

    var body: some View {
        Image(nsImage: bild)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Farbe.linie))
            .overlay(alignment: .topTrailing) {
                Button(action: entfernen) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(3)
                .help("Foto entfernen")
            }
            .accessibilityLabel("Foto der Mahlzeit")
    }
}
