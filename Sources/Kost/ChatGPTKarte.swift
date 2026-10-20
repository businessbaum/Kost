import AppKit
import SwiftUI

/// Anmeldung mit dem ChatGPT-Konto – danach schätzt Kost selbst, über das Abo des Nutzers.
struct ChatGPTKarte: View {
    @Environment(Sitzung.self) private var sitzung
    /// Überschrift und Erklärung – entfällt, wo die umgebende Seite das schon sagt.
    var zeigtKopf = true
    @State private var kopiert = false

    var body: some View {
        let konto = sitzung.chatgpt
        VStack(alignment: .leading, spacing: 14) {
            if zeigtKopf {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").font(.title2).foregroundStyle(.secondary)
                    Text("Mit ChatGPT schätzen").font(.headline)
                }
                Text("Melde dich einmal mit deinem ChatGPT-Konto an. Danach schätzt Kost Kalorien und Nährwerte direkt in der App – aus Text und Fotos, über dein Abo, ohne API-Schlüssel.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch konto.zustand {
            case .abgemeldet:
                HStack {
                    Text("Dafür brauchst du ChatGPT Plus oder Pro.").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Weiter mit ChatGPT") { konto.anmelden() }
                        .buttonStyle(.borderedProminent)
                }
            case .meldetAn:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Bitte im Browser anmelden und Kost erlauben …").foregroundStyle(.secondary)
                    Spacer()
                    Button("Abbrechen") { konto.brichAb() }
                }
            case .angemeldet(let email):
                HStack {
                    Label("Angemeldet als \(email)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Abmelden") { konto.abmelden() }
                }
            case .fehler(let text):
                VStack(alignment: .leading, spacing: 10) {
                    Label(text, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(kopiert ? "Diagnose kopiert" : "Diagnose kopieren") {
                            Task {
                                let text = await konto.zugang.diagnose()
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(text, forType: .string)
                                kopiert = true
                            }
                        }
                        .help("Kopiert ein Protokoll der Anmeldung ohne Zugangsdaten – zum Weiterschicken")
                        Spacer()
                        Button("Erneut versuchen") {
                            kopiert = false
                            konto.anmelden()
                        }
                    }
                }
            }
        }
    }
}
