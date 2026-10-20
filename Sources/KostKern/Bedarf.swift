import Foundation

/// Ergebnis der Bedarfsrechnung – alle Zwischenschritte bleiben sichtbar, damit die Oberfläche sie erklären kann.
public struct Bedarf: Equatable, Sendable {
    /// Verbrauch in völliger Ruhe (Mifflin-St Jeor).
    public let grundumsatz: Double
    /// Grundumsatz mal Aktivitätsfaktor.
    public let gesamtumsatz: Double
    /// Gewünschtes Plus oder Minus pro Tag aus Ziel und Tempo.
    public let anpassung: Double
    /// True, wenn das Kalorienziel auf die Untergrenze angehoben wurde.
    public let untergrenzeGegriffen: Bool
    public let bmi: Double
    public let eiweissJeKg: Double
    public let ziele: Tagesziele
}

public enum Bedarfsrechner {
    /// Energiegehalt von einem Kilogramm Körpergewicht – die übliche Faustzahl.
    public static let kcalJeKg = 7700.0
    public static let fettanteil = 0.30
    /// Zucker: EU-Referenzmenge (90 g bei 2000 kcal).
    public static let zuckeranteil = 0.18
    /// Gesättigte Fettsäuren: DGE-Richtwert, höchstens 10 % der Energie.
    public static let gesaettigtAnteil = 0.10
    public static let ballaststoffe = 30.0
    public static let salz = 6.0

    public static func grundumsatz(_ profil: Profil, alter: Int) -> Double {
        let sockel = 10 * profil.gewichtKg + 6.25 * profil.groesseCm - 5 * Double(alter)
        switch profil.geschlecht {
        case .maennlich: return sockel + 5
        case .weiblich: return sockel - 161
        case .divers: return sockel - 78   // Mittel aus beiden
        }
    }

    /// Unter diesen Wert senkt die App das Kalorienziel nicht, egal wie schnell abgenommen werden soll.
    public static func untergrenze(_ geschlecht: Geschlecht) -> Double {
        switch geschlecht {
        case .maennlich: 1500
        case .weiblich: 1200
        case .divers: 1350
        }
    }

    public static func eiweissJeKg(_ ziel: Ziel) -> Double {
        switch ziel {
        case .abnehmen: 1.8   // schützt im Defizit die Muskulatur
        case .halten: 1.4
        case .zunehmen: 1.8
        }
    }

    public static func bmi(gewichtKg: Double, groesseCm: Double) -> Double {
        let meter = groesseCm / 100
        guard meter > 0 else { return 0 }
        return gewichtKg / (meter * meter)
    }

    public static func bmiEinordnung(_ bmi: Double) -> String {
        switch bmi {
        case ..<18.5: "Untergewicht"
        case ..<25: "Normalgewicht"
        case ..<30: "Übergewicht"
        default: "Adipositas"
        }
    }

    public static func berechne(_ profil: Profil, imJahr jahr: Int) -> Bedarf {
        let grund = grundumsatz(profil, alter: profil.alter(imJahr: jahr))
        let gesamt = grund * profil.aktivitaet.faktor

        let anpassung: Double
        switch profil.ziel {
        case .abnehmen: anpassung = -profil.tempoKgProWoche * kcalJeKg / 7
        case .halten: anpassung = 0
        case .zunehmen: anpassung = profil.tempoKgProWoche * kcalJeKg / 7
        }

        let boden = untergrenze(profil.geschlecht)
        let wunsch = gesamt + anpassung
        let gegriffen = profil.ziel == .abnehmen && wunsch < boden
        let kcal = runde(gegriffen ? boden : wunsch, auf: 10)

        // Bei hohem BMI würde "Gramm je Kilo" das Eiweißziel aufblähen – dann zählt höchstens das Gewicht bei BMI 27,5.
        let meter = profil.groesseCm / 100
        let rechengewicht = min(profil.gewichtKg, 27.5 * meter * meter)
        let jeKg = eiweissJeKg(profil.ziel)
        let fett = (kcal * fettanteil / 9).rounded()
        var eiweiss = (rechengewicht * jeKg).rounded()
        // Eiweiß und Fett dürfen zusammen nie mehr Energie brauchen, als das Ziel hergibt.
        eiweiss = min(eiweiss, ((kcal - fett * 9) / 4).rounded(.down))
        let kohlenhydrate = max(0, ((kcal - eiweiss * 4 - fett * 9) / 4).rounded())

        let werte = Naehrwerte(
            kcal: kcal,
            eiweiss: eiweiss,
            kohlenhydrate: kohlenhydrate,
            zucker: (kcal * zuckeranteil / 4).rounded(),
            fett: fett,
            gesaettigt: (kcal * gesaettigtAnteil / 9).rounded(),
            ballaststoffe: ballaststoffe,
            salz: salz
        )
        let wasser = min(3500, max(1500, Int(runde(profil.gewichtKg * 30, auf: 250))))

        return Bedarf(
            grundumsatz: grund.rounded(),
            gesamtumsatz: gesamt.rounded(),
            anpassung: anpassung.rounded(),
            untergrenzeGegriffen: gegriffen,
            bmi: bmi(gewichtKg: profil.gewichtKg, groesseCm: profil.groesseCm),
            eiweissJeKg: jeKg,
            ziele: Tagesziele(naehrwerte: werte, wasserMl: wasser)
        )
    }

    static func runde(_ wert: Double, auf schritt: Double) -> Double {
        (wert / schritt).rounded() * schritt
    }
}
