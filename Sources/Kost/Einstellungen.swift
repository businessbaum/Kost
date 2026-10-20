import AppKit
import KostKern
import SwiftUI
import UniformTypeIdentifiers

struct EinstellungenAnsicht: View {
    @Environment(Speicher.self) private var speicher
    @Environment(Sitzung.self) private var sitzung

    @State private var fragtLoeschen = false

    var body: some View {
        let bindung = Binding(get: { speicher.einstellungen }, set: { speicher.aendere(einstellungen: $0) })
        Form {
            Section {
                ChatGPTKarte(zeigtKopf: false)
                if sitzung.chatgpt.istAngemeldet && !sitzung.chatgpt.modelle.isEmpty {
                    Picker("Modell", selection: bindung.chatgptModell) {
                        Text(sitzung.chatgpt.schnellstes.map { "Automatisch – das schnellste (\($0))" } ?? "Automatisch – das schnellste").tag("")
                        ForEach(sitzung.chatgpt.modelle, id: \.self) { Text($0).tag($0) }
                    }
                }
            } header: {
                Text("ChatGPT")
            } footer: {
                Text("Zum Schätzen gehen deine Beschreibung und Fotos an OpenAI, über dein ChatGPT-Abo. Die Anmeldung bleibt auf diesem Mac.")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Wasser") {
                Picker("Ein Glas", selection: bindung.glasMl) {
                    ForEach([150, 200, 250, 300, 330, 500], id: \.self) { Text("\($0) ml").tag($0) }
                }
            }

            Section("Daten") {
                LabeledContent("Tagebuch") {
                    Button("Als CSV exportieren …") { exportiere() }
                        .disabled(speicher.daten.eintraege.isEmpty)
                }
                LabeledContent("Speicherort") {
                    Button("Im Finder zeigen") {
                        speicher.sichereSofort()
                        NSWorkspace.shared.activateFileViewerSelecting([Ablage.datei])
                    }
                }
                LabeledContent("Zurücksetzen") {
                    Button("Alle Daten löschen …", role: .destructive) { fragtLoeschen = true }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("Alle Daten löschen?", isPresented: $fragtLoeschen) {
            Button("Alles löschen", role: .destructive) { speicher.loescheAlles() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Profil, Tagebuch, Lebensmittel und Wägungen werden entfernt. Das lässt sich nicht rückgängig machen.")
        }
    }

    private func exportiere() {
        let dialog = NSSavePanel()
        dialog.allowedContentTypes = [.commaSeparatedText]
        dialog.nameFieldStringValue = "Kost-Tagebuch-\(Tag.heute.schluessel).csv"
        guard dialog.runModal() == .OK, let ziel = dialog.url else { return }
        do {
            // Mit BOM, damit Excel die Umlaute richtig liest.
            try Data(("\u{FEFF}" + Export.csv(speicher.daten.eintraege)).utf8).write(to: ziel, options: .atomic)
        } catch {
            speicher.hinweis = "Export fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
