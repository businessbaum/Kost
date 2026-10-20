import AppKit
import KostKern
import SwiftUI

// `--bildprobe <Ordner>` zeichnet alle Seiten mit Beispieldaten als PNG, statt die App zu öffnen.
// `--modelle` und `--schaetze "<Text>"` prüfen die ChatGPT-Anbindung mit der gespeicherten Anmeldung.
let argumente = CommandLine.arguments

func pruefeOhneOberflaeche(_ arbeit: @escaping @Sendable () async -> Void) {
    let warten = DispatchSemaphore(value: 0)
    Task.detached {
        await arbeit()
        warten.signal()
    }
    warten.wait()
}

if let stelle = argumente.firstIndex(of: "--bildprobe") {
    let ordner = argumente.dropFirst(stelle + 1).first ?? "bildprobe"
    MainActor.assumeIsolated { Bildprobe.starte(ordner: ordner) }
} else if argumente.contains("--modelle") {
    pruefeOhneOberflaeche {
        do {
            let modelle = try await ChatGPTZugang().modelle()
            print(modelle.isEmpty ? "Keine Modelle gemeldet." : modelle.joined(separator: "\n"))
            let zugang = ChatGPTZugang()
            let schnellstes = await zugang.schnellstesModell(aus: modelle, neuMessen: argumente.contains("--messen"))
            print("Schnellstes (gemessen): \(schnellstes ?? "–")")
        } catch {
            print("Fehler: \(error.localizedDescription)")
        }
    }
} else if let stelle = argumente.firstIndex(of: "--schaetze") {
    let text = argumente.dropFirst(stelle + 1).first ?? ""
    let gewuenscht = argumente.firstIndex(of: "--modell").flatMap { argumente.dropFirst($0 + 1).first }
    let bild = argumente.firstIndex(of: "--foto").flatMap { argumente.dropFirst($0 + 1).first }
        .flatMap { Bildaufbereitung.jpeg(ausDatei: URL(fileURLWithPath: $0)) }.map { [Bildanhang(jpeg: $0)] } ?? []
    pruefeOhneOberflaeche {
        let start = Date()
        do {
            let zugang = ChatGPTZugang()
            let liste = gewuenscht == nil ? try await zugang.modelle() : []
            guard let modell = gewuenscht ?? ChatGPTZugang.vorgabemodell(aus: liste) else {
                print("Kein Modell verfügbar.")
                return
            }
            print("Modell: \(modell)")
            let schaetzung = try await ChatGPTSchaetzer(zugang: zugang, modell: modell).schaetze(text: text, bilder: bild)
            for posten in schaetzung.posten {
                let w = posten.naehrwerte
                print("\(posten.name) | \(posten.menge) \(posten.einheit) | \(w.kcal) kcal | E \(w.eiweiss) K \(w.kohlenhydrate) (Zucker \(w.zucker)) F \(w.fett) (ges. \(w.gesaettigt)) Ballast \(w.ballaststoffe) Salz \(w.salz)")
            }
            print("Summe: \(schaetzung.summe.kcal) kcal · Sicherheit: \(schaetzung.sicherheit.rawValue)")
            print("Annahmen: \(schaetzung.annahmen)")
        } catch {
            print("Fehler: \(error.localizedDescription)")
        }
        print(String(format: "Dauer: %.1f s", Date().timeIntervalSince(start)))
    }
} else {
    KostApp.main()
}
