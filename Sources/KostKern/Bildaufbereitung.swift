import Foundation
import ImageIO

/// Verkleinert Fotos, bevor sie zur Schätzung gehen: Ein Handyfoto hat 12 Megapixel,
/// zum Erkennen einer Mahlzeit reichen gut anderthalb – das spart Zeit und Kontingent.
public enum Bildaufbereitung {
    public static let laengsteKante = 1568

    public static func jpeg(aus daten: Data, laengsteKante: Int = laengsteKante, qualitaet: Double = 0.8) -> Data? {
        guard let quelle = CGImageSourceCreateWithData(daten as CFData, nil) else { return nil }
        return jpeg(aus: quelle, laengsteKante: laengsteKante, qualitaet: qualitaet)
    }

    public static func jpeg(ausDatei datei: URL, laengsteKante: Int = laengsteKante, qualitaet: Double = 0.8) -> Data? {
        guard let quelle = CGImageSourceCreateWithURL(datei as CFURL, nil) else { return nil }
        return jpeg(aus: quelle, laengsteKante: laengsteKante, qualitaet: qualitaet)
    }

    static func jpeg(aus quelle: CGImageSource, laengsteKante: Int, qualitaet: Double) -> Data? {
        let optionen: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // Drehung aus den Fotodaten anwenden
            kCGImageSourceThumbnailMaxPixelSize: laengsteKante,
        ]
        guard let bild = CGImageSourceCreateThumbnailAtIndex(quelle, 0, optionen as CFDictionary) else { return nil }
        let ziel = NSMutableData()
        guard let schreiber = CGImageDestinationCreateWithData(ziel, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(schreiber, bild, [kCGImageDestinationLossyCompressionQuality: qualitaet] as CFDictionary)
        guard CGImageDestinationFinalize(schreiber) else { return nil }
        return ziel as Data
    }
}
