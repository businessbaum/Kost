import AppKit
import KostKern
import SwiftUI

struct KostApp: App {
    @NSApplicationDelegateAdaptor(Appdelegierter.self) private var delegierter
    @State private var speicher = Speicher(datei: Ablage.datei)
    @State private var sitzung = Sitzung()

    var body: some Scene {
        Window("Kost", id: "haupt") {
            Wurzel()
                .environment(speicher)
                .environment(sitzung)
                .frame(minWidth: 940, minHeight: 640)
        }
        .defaultSize(width: 1120, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Essen eintragen") { sitzung.bereich = .rechner }
                    .keyboardShortcut("n")
                    .disabled(speicher.profil == nil)
            }
            CommandMenu("Tagebuch") {
                Button("Heute") { sitzung.zeige(.heute) }
                    .keyboardShortcut("t")
                Button("Vorheriger Tag") { sitzung.zeige(sitzung.tag.verschoben(um: -1)) }
                    .keyboardShortcut("[")
                Button("Nächster Tag") { sitzung.zeige(sitzung.tag.verschoben(um: 1)) }
                    .keyboardShortcut("]")
                Divider()
                ForEach(Array(Bereich.allCases.enumerated()), id: \.element) { stelle, bereich in
                    Button(bereich.name) { sitzung.bereich = bereich }
                        .keyboardShortcut(KeyEquivalent(Character("\(stelle + 1)")))
                }
            }
        }

        Settings {
            EinstellungenAnsicht()
                .environment(speicher)
                .environment(sitzung)
        }
    }
}

final class Appdelegierter: NSObject, NSApplicationDelegate {
    // Ein Fenster, eine App: Schließen beendet.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct Wurzel: View {
    @Environment(Speicher.self) private var speicher
    @Environment(Sitzung.self) private var sitzung

    var body: some View {
        @Bindable var speicher = speicher
        Group {
            if speicher.profil == nil {
                Einrichtung()
            } else {
                Hauptfenster()
            }
        }
        .alert("Hinweis", isPresented: Binding(get: { speicher.hinweis != nil }, set: { if !$0 { speicher.hinweis = nil } })) {
            Button("OK") { speicher.hinweis = nil }
        } message: {
            Text(speicher.hinweis ?? "")
        }
    }
}

struct Hauptfenster: View {
    @Environment(Sitzung.self) private var sitzung
    @Environment(Speicher.self) private var speicher

    var body: some View {
        @Bindable var sitzung = sitzung
        NavigationSplitView {
            // Auswahl bewusst ohne Optional: Mit `Bereich?` übernimmt die Liste unter macOS keinen Klick.
            List(Bereich.allCases, selection: $sitzung.bereich) { bereich in
                Label(bereich.name, systemImage: bereich.symbol)
                    .tag(bereich)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .safeAreaInset(edge: .bottom) {
                // Einstellungen auch ohne Menüleiste erreichbar
                SettingsLink {
                    Label("Einstellungen", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
        } detail: {
            Group {
                switch sitzung.bereich {
                case .tagebuch: TagebuchAnsicht()
                case .rechner: RechnerAnsicht()
                case .lebensmittel: LebensmittelAnsicht()
                case .auswertung: AuswertungAnsicht()
                case .gewicht: GewichtAnsicht()
                case .profil: ProfilAnsicht()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Farbe.flaeche)
        }

    }
}
