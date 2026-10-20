import KostKern
import SwiftUI

struct ProfilAnsicht: View {
    @Environment(Speicher.self) private var speicher

    private var jahr: Int { Calendar.current.component(.year, from: Date()) }

    var body: some View {
        Seite {
            Seitenkopf(titel: "Profil & Ziele", untertitel: "Aus diesen Angaben berechnet Kost, wie viel du am Tag brauchst.")
            if let profil = speicher.profil, let bedarf = speicher.bedarf {
                let bindung = Binding(get: { speicher.profil ?? profil }, set: { speicher.aendere(profil: $0) })
                HStack(alignment: .top, spacing: Mass.abstand) {
                    ueberDich(bindung)
                    alltag(bindung)
                }
                bedarfskarte(profil, bedarf)
                zielkarte(bedarf)
            }
        }
    }

    private func reihe<Feld: View>(_ name: String, @ViewBuilder feld: () -> Feld) -> some View {
        HStack {
            Text(name)
            Spacer(minLength: 12)
            feld()
        }
        .frame(minHeight: 28)
    }

    private func ueberDich(_ profil: Binding<Profil>) -> some View {
        Karte {
            VStack(alignment: .leading, spacing: 10) {
                Kartentitel(text: "Über dich").padding(.bottom, 2)
                reihe("Name") {
                    TextField("Freiwillig", text: profil.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                }
                reihe("Geschlecht") {
                    Picker("Geschlecht", selection: profil.geschlecht) {
                        ForEach(Geschlecht.allCases) { Text($0.name).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                reihe("Alter") {
                    Zahlenfeld(
                        wert: Binding(
                            get: { Double(profil.wrappedValue.alter(imJahr: jahr)) },
                            set: { profil.wrappedValue.geburtsjahr = jahr - Int($0) }
                        ),
                        einheit: "Jahre", stellen: 0, bereich: 14...100
                    )
                }
                reihe("Größe") {
                    Zahlenfeld(wert: profil.groesseCm, einheit: "cm", stellen: 0, bereich: 120...230)
                }
                reihe("Gewicht") {
                    Zahlenfeld(wert: profil.gewichtKg, einheit: "kg", bereich: 30...300)
                }
            }
        }
    }

    private func alltag(_ profil: Binding<Profil>) -> some View {
        Karte {
            VStack(alignment: .leading, spacing: 10) {
                Kartentitel(text: "Alltag und Ziel").padding(.bottom, 2)
                reihe("Aktivität") {
                    Picker("Aktivität", selection: profil.aktivitaet) {
                        ForEach(Aktivitaet.allCases) { Text($0.name).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Text(profil.wrappedValue.aktivitaet.beschreibung)
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                reihe("Ziel") {
                    Picker("Ziel", selection: Binding(
                        get: { profil.wrappedValue.ziel },
                        set: { neu in
                            // Ziel und Tempo zusammen ändern, sonst stünde kurz ein Tempo da, das zum Ziel nicht passt.
                            var p = profil.wrappedValue
                            p.ziel = neu
                            p.tempoKgProWoche = neu.ueblichesTempo
                            profil.wrappedValue = p
                        }
                    )) {
                        ForEach(Ziel.allCases) { Text($0.name).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if profil.wrappedValue.ziel != .halten {
                    reihe("Tempo") {
                        Picker("Tempo", selection: profil.tempoKgProWoche) {
                            ForEach(profil.wrappedValue.ziel.tempostufen, id: \.self) {
                                Text("\(Zahl.knapp($0, stellen: 3)) kg pro Woche").tag($0)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    reihe("Zielgewicht") {
                        WahlfreiesZahlenfeld(wert: profil.zielgewichtKg, einheit: "kg", platzhalter: "Freiwillig")
                    }
                }
            }
        }
    }

    private func bedarfskarte(_ profil: Profil, _ bedarf: Bedarf) -> some View {
        Karte {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Kartentitel(text: "Dein Bedarf")
                    Spacer()
                    Text("BMI \(Zahl.knapp(bedarf.bmi)) · \(Bedarfsrechner.bmiEinordnung(bedarf.bmi))")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Bedarfsherleitung(bedarf: bedarf, profil: profil)
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Text("Rechnerisches Tagesziel")
                    Spacer()
                    Text("\(Zahl.ganz(bedarf.ziele[.kcal])) kcal").font(.title3.weight(.semibold)).monospacedDigit()
                }
                if bedarf.untergrenzeGegriffen {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "info.circle")
                        Text("Mit diesem Tempo läge das Ziel noch tiefer. Unter \(Zahl.ganz(bedarf.ziele[.kcal])) kcal senkt Kost es nicht, weil so wenig auf Dauer nicht gesund ist.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                Text("Grundumsatz nach Mifflin-St Jeor. Die Rechnung ist eine Schätzung: Bewegt sich dein Gewicht über zwei, drei Wochen anders als geplant, pass Aktivität oder Ziel an.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func zielkarte(_ bedarf: Bedarf) -> some View {
        let folgt = speicher.zieleFolgenProfil
        let ziele = speicher.ziele
        let bindung = Binding(get: { speicher.ziele }, set: { speicher.setze(eigeneZiele: $0) })
        return Karte {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Kartentitel(text: "Tagesziele")
                    Spacer()
                    Toggle("Aus dem Profil berechnen", isOn: Binding(
                        get: { folgt },
                        // Beim Abschalten starten die eigenen Ziele mit den berechneten Werten.
                        set: { speicher.setze(eigeneZiele: $0 ? nil : bedarf.ziele) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 32), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                    ForEach(Naehrstoff.allCases) { stoff in
                        reihe(zielname(stoff)) {
                            if folgt {
                                Text("\(Zahl.wert(ziele[stoff], stoff)) \(stoff.einheit)").monospacedDigit()
                            } else {
                                Zahlenfeld(
                                    wert: Binding(get: { bindung.wrappedValue[stoff] }, set: { bindung.wrappedValue[stoff] = $0 }),
                                    einheit: stoff.einheit, stellen: stoff.nachkommastellen
                                )
                            }
                        }
                    }
                    reihe("Wasser") {
                        if folgt {
                            Text(Zahl.liter(ziele.wasserMl)).monospacedDigit()
                        } else {
                            Zahlenfeld(
                                wert: Binding(get: { Double(bindung.wrappedValue.wasserMl) }, set: { bindung.wrappedValue.wasserMl = Int($0) }),
                                einheit: "ml", stellen: 0
                            )
                        }
                    }
                }
                Text("Eiweiß: \(Zahl.knapp(bedarf.eiweissJeKg)) g je kg Körpergewicht · Fett: 30 % der Energie · Kohlenhydrate: der Rest · Zucker, gesättigte Fettsäuren, Ballaststoffe und Salz nach den Richtwerten von DGE und EU-Kennzeichnung.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func zielname(_ stoff: Naehrstoff) -> String {
        switch stoff.richtung {
        case .richtwert: stoff.name
        case .mindestens: "\(stoff.name), mindestens"
        case .hoechstens: "\(stoff.name), höchstens"
        }
    }
}
