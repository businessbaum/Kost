import CryptoKit
import Foundation
import Network
import Security

// "Sign in with ChatGPT" mit Abo-Nutzung, wie OpenAI es für lokal laufende Apps vorsieht:
// https://developers.openai.com/siwc/token-sharing-open-source
// OAuth mit PKCE über den Browser, Rückruf an 127.0.0.1, Client-ID per dynamischer Registrierung.

// MARK: - Gespeicherte Daten

/// Die Anmeldung. Liegt als Datei mit Rechten 0600 im Kost-Ordner – nie in Protokollen.
public struct ChatGPTSitzung: Codable, Equatable, Sendable {
    public var email: String
    public var subject: String
    public var clientId: String
    public var idToken: String
    public var accessToken: String
    public var refreshToken: String
    public var ablauf: Date
    public var scopes: [String]
}

/// Bleibt auch nach dem Abmelden: die Geräte-Kennung und die einmal vergebene Client-ID.
struct ChatGPTRegistrierung: Codable, Equatable {
    var hostId: String
    var clientId: String?
    var idTokenHinweis: String?
}

public enum ChatGPTFehler: LocalizedError, Equatable {
    case nichtAngemeldet
    case abgebrochen
    case zeitueberschreitung
    case anmeldungFehlgeschlagen(String)
    case keineAbonutzung
    case kontingentErschoepft
    case aboNichtVerfuegbar
    case antwortFehler(String)

    public var errorDescription: String? {
        switch self {
        case .nichtAngemeldet:
            "Du bist nicht mit ChatGPT angemeldet."
        case .abgebrochen:
            "Die Anmeldung wurde abgebrochen."
        case .zeitueberschreitung:
            "Die Anmeldung im Browser hat zu lange gedauert. Versuch es noch einmal."
        case .anmeldungFehlgeschlagen(let text):
            "Die Anmeldung bei ChatGPT hat nicht geklappt: \(text)"
        case .keineAbonutzung:
            "Die Anmeldung hat geklappt, aber Kost darf dein ChatGPT-Abo nicht nutzen. Melde dich noch einmal an und erlaube die Nutzung."
        case .kontingentErschoepft:
            "Dein ChatGPT-Kontingent für andere Apps ist gerade aufgebraucht. In ChatGPT unter Einstellungen › Nutzung siehst du, wann es weitergeht."
        case .aboNichtVerfuegbar:
            "Dein ChatGPT-Abo lässt sich in anderen Apps gerade nicht nutzen – das geht nur mit Plus oder Pro. In ChatGPT unter Einstellungen › Nutzung kannst du es prüfen."
        case .antwortFehler(let text):
            "ChatGPT meldet: \(text)"
        }
    }
}

// MARK: - Zugang

/// Hält die Anmeldung, frischt sie auf und meldet ab. Ein Actor, damit nie zwei Auffrischungen gleichzeitig laufen.
public actor ChatGPTZugang {
    static let aussteller = "https://auth.openai.com"
    static let autorisierung = URL(string: "https://auth.openai.com/api/accounts/authorize")!
    static let tokenadresse = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    static let konfiguration = URL(string: "https://auth.openai.com/.well-known/openid-configuration")!
    static let ressource = "https://api.openai.com/v1"
    static let scopes = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    static let rueckrufpfad = "/auth/callback"

    let ordner: URL
    let sitzung_url: URL
    let registrierung_url: URL
    let netz: URLSession
    private(set) public var sitzung: ChatGPTSitzung?

    public init(ordner: URL = Ablage.ordner, netz: URLSession = .shared) {
        self.ordner = ordner
        self.sitzung_url = ordner.appendingPathComponent("chatgpt-sitzung.json")
        self.registrierung_url = ordner.appendingPathComponent("chatgpt-geraet.json")
        self.netz = netz
        self.sitzung = Self.lies(ChatGPTSitzung.self, aus: ordner.appendingPathComponent("chatgpt-sitzung.json"))
    }

    public var email: String? { sitzung?.email }

    // MARK: Protokoll

    var protokoll_url: URL { ordner.appendingPathComponent("chatgpt-diagnose.txt") }

    /// Schreibt einen Schritt der Anmeldung mit – nie Codes, Tokens oder Verifier, nur Namen, Status und Fehlertexte.
    func protokolliere(_ text: String) {
        let zeile = "\(ISO8601DateFormatter().string(from: Date()))  \(text)\n"
        if let griff = try? FileHandle(forWritingTo: protokoll_url) {
            griff.seekToEndOfFile()
            griff.write(Data(zeile.utf8))
            try? griff.close()
        } else {
            try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
            try? Data(zeile.utf8).write(to: protokoll_url)
        }
    }

    /// Das Protokoll zum Weitergeben – mit Systemangaben, ohne Geheimnisse.
    public func diagnose() -> String {
        let system = ProcessInfo.processInfo.operatingSystemVersionString
        let pfad = Bundle.main.bundlePath
        let kopf = "Kost-Diagnose · macOS \(system) · \(pfad.contains("/AppTranslocation/") ? "aus Downloads gestartet" : pfad)\n"
        let text = (try? String(contentsOf: protokoll_url, encoding: .utf8)) ?? "(noch keine Einträge)\n"
        return kopf + String(text.suffix(6000))
    }

    // MARK: Anmelden

    /// Öffnet über `oeffne` die Anmeldeseite im Browser und wartet auf den Rückruf.
    @discardableResult
    public func anmelden(oeffne: @Sendable (URL) -> Void) async throws -> ChatGPTSitzung {
        var registrierung = Self.lies(ChatGPTRegistrierung.self, aus: registrierung_url)
            ?? ChatGPTRegistrierung(hostId: "urn:uuid:" + UUID().uuidString.lowercased())
        try Self.schreibe(registrierung, nach: registrierung_url)

        let empfaenger = try await Rueckrufempfaenger.starte(pfad: Self.rueckrufpfad)
        defer { empfaenger.beende() }
        let rueckruf = "http://127.0.0.1:\(empfaenger.port)\(Self.rueckrufpfad)"
        let versuch = Anmeldeversuch()
        protokolliere("Start: \(registrierung.clientId == nil ? "erste Registrierung" : "erneute Anmeldung mit gespeicherter Client-ID"), Port \(empfaenger.port)")
        oeffne(Self.anmeldeadresse(versuch: versuch, rueckruf: rueckruf, registrierung: registrierung))

        let antwort: [String: String]
        do {
            antwort = try await empfaenger.warte(hoechstens: 300)
        } catch {
            protokolliere("Kein Rückruf: \(error.localizedDescription)")
            throw error
        }
        protokolliere("Rückruf mit \(antwort.keys.sorted().joined(separator: ", "))"
            + (antwort["scope"].map { " · scope: \($0)" } ?? "")
            + (antwort["error"].map { " · error: \($0) \(antwort["error_description"] ?? "")" } ?? "")
            + (antwort["client_id"].map { " · client_id: \($0.prefix(10))…" } ?? ""))
        guard antwort["state"] == versuch.state else { throw ChatGPTFehler.anmeldungFehlgeschlagen("Die Antwort passt nicht zur Anfrage.") }
        if let fehler = antwort["error"] {
            throw fehler == "access_denied" ? ChatGPTFehler.abgebrochen : ChatGPTFehler.anmeldungFehlgeschlagen(antwort["error_description"] ?? fehler)
        }
        guard let code = antwort["code"] else { throw ChatGPTFehler.anmeldungFehlgeschlagen("Kein Code im Rückruf.") }

        // Beim ersten Mal vergibt OpenAI die Client-ID im Rückruf; danach muss sie gleich bleiben.
        let clientId: String
        if let gespeichert = registrierung.clientId {
            if let geliefert = antwort["client_id"], geliefert != gespeichert {
                throw ChatGPTFehler.anmeldungFehlgeschlagen("Unerwartete Client-ID.")
            }
            clientId = gespeichert
        } else {
            guard let geliefert = antwort["client_id"], geliefert != "dynamic_agent_client" else {
                throw ChatGPTFehler.anmeldungFehlgeschlagen("Die Registrierung bei OpenAI ist unvollständig.")
            }
            clientId = geliefert
        }

        let token: Tokenantwort
        do {
            token = try await tausche([
                "grant_type": "authorization_code", "client_id": clientId, "code": code,
                "code_verifier": versuch.verifier, "redirect_uri": rueckruf, "resource": Self.ressource,
            ])
        } catch {
            protokolliere("Codetausch abgelehnt: \(error.localizedDescription)")
            // Laut OpenAI: Code verwerfen und neu beginnen. Bei der Erstregistrierung auch mit frischer Geräte-Kennung,
            // damit kein halb angelegter Eintrag beim nächsten Versuch im Weg steht.
            if registrierung.clientId == nil {
                registrierung = ChatGPTRegistrierung(hostId: "urn:uuid:" + UUID().uuidString.lowercased())
                try? Self.schreibe(registrierung, nach: registrierung_url)
            }
            throw error
        }
        protokolliere("Codetausch erfolgreich · scopes: \(token.scopes.joined(separator: " "))")
        guard let idToken = token.idToken else { throw ChatGPTFehler.anmeldungFehlgeschlagen("Kein ID-Token erhalten.") }
        let identitaet: Identitaet
        do {
            identitaet = try await pruefeIdToken(idToken, clientId: clientId, nonce: versuch.nonce)
        } catch {
            protokolliere("ID-Token abgelehnt: \(error.localizedDescription)")
            throw error
        }
        guard token.scopes.contains("chatgpt.tokens.use.direct") else {
            protokolliere("Abo-Nutzung nicht gewährt")
            throw ChatGPTFehler.keineAbonutzung
        }
        guard let refresh = token.refreshToken else { throw ChatGPTFehler.anmeldungFehlgeschlagen("Kein Refresh-Token erhalten.") }

        let neu = ChatGPTSitzung(
            email: identitaet.email, subject: identitaet.subject, clientId: clientId, idToken: idToken,
            accessToken: token.accessToken, refreshToken: refresh, ablauf: Date().addingTimeInterval(token.laufzeit), scopes: token.scopes
        )
        registrierung.clientId = clientId
        registrierung.idTokenHinweis = idToken
        try Self.schreibe(registrierung, nach: registrierung_url)
        try Self.schreibe(neu, nach: sitzung_url)
        sitzung = neu
        return neu
    }

    static func anmeldeadresse(versuch: Anmeldeversuch, rueckruf: String, registrierung: ChatGPTRegistrierung) -> URL {
        var teile = URLComponents(url: autorisierung, resolvingAgainstBaseURL: false)!
        var parameter: [(String, String)] = [
            ("client_id", registrierung.clientId ?? "dynamic_agent_client"),
            ("ext_agent_host_id", registrierung.hostId),
            ("response_type", "code"),
            ("redirect_uri", rueckruf),
            ("scope", scopes),
            ("resource", ressource),
            ("state", versuch.state),
            ("nonce", versuch.nonce),
            ("code_challenge_method", "S256"),
            ("code_challenge", versuch.challenge),
        ]
        // Den App-Namen nur bei der ersten Registrierung mitschicken, den alten ID-Token nur danach.
        if registrierung.clientId == nil {
            parameter.append(("agent_name_hint", "Kost"))
        } else if let hinweis = registrierung.idTokenHinweis {
            parameter.append(("id_token_hint", hinweis))
        }
        teile.percentEncodedQueryItems = parameter.map { URLQueryItem(name: $0.0, value: kodiere($0.1)) }
        return teile.url!
    }

    /// Strenger als `urlQueryAllowed`: auch `+`, `&`, `=` und `:` kodieren.
    static func kodiere(_ wert: String) -> String {
        var erlaubt = CharacterSet.alphanumerics
        erlaubt.insert(charactersIn: "-._~")
        return wert.addingPercentEncoding(withAllowedCharacters: erlaubt) ?? wert
    }

    // MARK: Gültiges Token

    /// Liefert ein gültiges Zugangstoken und frischt es kurz vor Ablauf auf.
    public func zugangstoken() async throws -> String {
        ladeNeu()
        guard let aktuell = sitzung else { throw ChatGPTFehler.nichtAngemeldet }
        if aktuell.ablauf.timeIntervalSinceNow > 120 { return aktuell.accessToken }
        return try await frischeAuf().accessToken
    }

    private var laufendeAuffrischung: Task<ChatGPTSitzung, Error>?

    /// Läuft schon eine Auffrischung, warten alle anderen auf deren Ergebnis: Refresh-Tokens rotieren,
    /// eine zweite gleichzeitige Auffrischung mit demselben Token würde die Anmeldung kosten.
    @discardableResult
    public func frischeAuf() async throws -> ChatGPTSitzung {
        if let laufend = laufendeAuffrischung { return try await laufend.value }
        let aufgabe = Task { try await self.frischeAufJetzt() }
        laufendeAuffrischung = aufgabe
        defer { laufendeAuffrischung = nil }
        return try await aufgabe.value
    }

    private func frischeAufJetzt() async throws -> ChatGPTSitzung {
        ladeNeu()
        guard var aktuell = sitzung else { throw ChatGPTFehler.nichtAngemeldet }
        let token: Tokenantwort
        do {
            token = try await tausche([
                "grant_type": "refresh_token", "client_id": aktuell.clientId,
                "refresh_token": aktuell.refreshToken, "resource": Self.ressource,
            ])
        } catch ChatGPTFehler.anmeldungFehlgeschlagen {
            // Refresh-Token abgelaufen oder widerrufen: neu anmelden lassen, Registrierung bleibt.
            vergiss()
            throw ChatGPTFehler.nichtAngemeldet
        }
        aktuell.accessToken = token.accessToken
        aktuell.ablauf = Date().addingTimeInterval(token.laufzeit)
        if let refresh = token.refreshToken { aktuell.refreshToken = refresh }
        if !token.scopes.isEmpty { aktuell.scopes = token.scopes }
        if let idToken = token.idToken { aktuell.idToken = idToken }
        try Self.schreibe(aktuell, nach: sitzung_url)
        sitzung = aktuell
        return aktuell
    }

    // MARK: Abmelden

    /// Widerruft die Anmeldung bei OpenAI und löscht sie lokal. Gerät und Client-ID bleiben registriert.
    public func abmelden() async {
        guard let aktuell = sitzung else { return }
        if let adresse = try? await endpunkte().widerruf {
            var anfrage = URLRequest(url: adresse)
            anfrage.httpMethod = "POST"
            anfrage.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            anfrage.httpBody = Self.formular(["token": aktuell.refreshToken, "token_type_hint": "refresh_token", "client_id": aktuell.clientId])
            _ = try? await netz.data(for: anfrage)
        }
        vergiss()
    }

    /// Refresh-Tokens rotieren: Hat ein anderer Kost-Prozess aufgefrischt, gilt nur noch dessen Stand.
    private func ladeNeu() {
        sitzung = Self.lies(ChatGPTSitzung.self, aus: sitzung_url)
    }

    private func vergiss() {
        sitzung = nil
        try? FileManager.default.removeItem(at: sitzung_url)
    }

    // MARK: Modelle

    /// Die Modelle, die dem angemeldeten Konto zur Verfügung stehen.
    public func modelle() async throws -> [String] {
        var anfrage = URLRequest(url: URL(string: "\(Self.ressource)/models")!)
        anfrage.setValue("Bearer \(try await zugangstoken())", forHTTPHeaderField: "Authorization")
        let (daten, _) = try await netz.data(for: anfrage)
        return Self.modellnamen(aus: daten)
    }

    static func modellnamen(aus daten: Data) -> [String] {
        guard let wurzel = try? JSONSerialization.jsonObject(with: daten) as? [String: Any],
              let liste = wurzel["data"] as? [[String: Any]] ?? wurzel["models"] as? [[String: Any]] else { return [] }
        return liste.compactMap { eintrag -> String? in
            if let sichtbar = eintrag["visibility"] as? String, sichtbar != "list" { return nil }
            return eintrag["slug"] as? String ?? eintrag["id"] as? String
        }
    }

    /// Ersatz, solange noch nicht gemessen wurde: die kleinen Modellreihen zuerst.
    public static func vorgabemodell(aus modelle: [String]) -> String? {
        modelle.first { $0.contains("luna") } ?? modelle.first { $0.contains("mini") } ?? modelle.first
    }

    struct Tempomessung: Codable {
        var modelle: [String]
        var schnellstes: String
        var sekunden: [String: Double]
        var gemessen: Date
    }

    /// Das schnellste Modell für eine Schätzung. Gemessen wird mit einer kleinen echten Schätzung je Modell,
    /// gleichzeitig; das Ergebnis gilt, bis sich die Modellliste ändert oder zwei Wochen um sind.
    public func schnellstesModell(aus modelle: [String], neuMessen: Bool = false) async -> String? {
        let datei = ordner.appendingPathComponent("chatgpt-tempo.json")
        if !neuMessen, let alt = Self.lies(Tempomessung.self, aus: datei),
           Set(alt.modelle) == Set(modelle), alt.gemessen.timeIntervalSinceNow > -14 * 86_400 {
            return alt.schnellstes
        }
        guard !modelle.isEmpty else { return nil }
        // Vorher einmal ein gültiges Token holen, damit die Messungen nicht alle zugleich auffrischen wollen.
        guard (try? await zugangstoken()) != nil else { return nil }
        var sekunden: [String: Double] = [:]
        await withTaskGroup(of: (String, Double?).self) { gruppe in
            for modell in modelle {
                gruppe.addTask {
                    let start = Date()
                    let schaetzer = ChatGPTSchaetzer(zugang: self, modell: modell)
                    guard (try? await schaetzer.schaetze(text: "1 Apfel")) != nil else { return (modell, nil) }
                    return (modell, Date().timeIntervalSince(start))
                }
            }
            for await (modell, dauer) in gruppe { if let dauer { sekunden[modell] = dauer } }
        }
        guard let schnellstes = sekunden.min(by: { $0.value < $1.value })?.key else { return nil }
        try? Self.schreibe(Tempomessung(modelle: modelle, schnellstes: schnellstes, sekunden: sekunden, gemessen: Date()), nach: datei)
        return schnellstes
    }

    // MARK: Netz

    struct Tokenantwort {
        let accessToken: String
        let refreshToken: String?
        let idToken: String?
        let laufzeit: TimeInterval
        let scopes: [String]
    }

    private func tausche(_ felder: [String: String]) async throws -> Tokenantwort {
        var anfrage = URLRequest(url: Self.tokenadresse)
        anfrage.httpMethod = "POST"
        anfrage.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        anfrage.httpBody = Self.formular(felder)
        let (daten, antwort) = try await netz.data(for: anfrage)
        let objekt = (try? JSONSerialization.jsonObject(with: daten) as? [String: Any]) ?? [:]
        let status = (antwort as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let zugang = objekt["access_token"] as? String else {
            // Alles außer Tokens in die Meldung – nur der Fehlercode allein sagt zu wenig.
            let teile = [objekt["error"] as? String, objekt["error_description"] as? String, (objekt["detail"] as? String)]
                .compactMap { $0 }.filter { !$0.isEmpty }
            let text = (teile.isEmpty ? String(decoding: daten.prefix(300), as: UTF8.self) : teile.joined(separator: " – ")) + " (HTTP \(status))"
            throw ChatGPTFehler.anmeldungFehlgeschlagen(text)
        }
        let scopes: [String]
        if let text = objekt["scope"] as? String { scopes = text.split(separator: " ").map(String.init) }
        else { scopes = objekt["scope"] as? [String] ?? [] }
        return Tokenantwort(
            accessToken: zugang, refreshToken: objekt["refresh_token"] as? String, idToken: objekt["id_token"] as? String,
            laufzeit: (objekt["expires_in"] as? NSNumber)?.doubleValue ?? 3600, scopes: scopes
        )
    }

    struct Endpunkte {
        let jwks: URL
        let widerruf: URL?
    }

    private var endpunkteZwischenspeicher: Endpunkte?

    private func endpunkte() async throws -> Endpunkte {
        if let endpunkteZwischenspeicher { return endpunkteZwischenspeicher }
        let (daten, _) = try await netz.data(from: Self.konfiguration)
        guard let objekt = try JSONSerialization.jsonObject(with: daten) as? [String: Any],
              let jwks = (objekt["jwks_uri"] as? String).flatMap(URL.init(string:)) else {
            throw ChatGPTFehler.anmeldungFehlgeschlagen("Die Anmeldedaten von OpenAI waren nicht lesbar.")
        }
        let ergebnis = Endpunkte(jwks: jwks, widerruf: (objekt["revocation_endpoint"] as? String).flatMap(URL.init(string:)))
        endpunkteZwischenspeicher = ergebnis
        return ergebnis
    }

    private func pruefeIdToken(_ token: String, clientId: String, nonce: String) async throws -> Identitaet {
        let (daten, _) = try await netz.data(from: try await endpunkte().jwks)
        return try IdToken.pruefe(token, schluessel: daten, aussteller: Self.aussteller, publikum: clientId, nonce: nonce)
    }

    static func formular(_ felder: [String: String]) -> Data {
        Data(felder.sorted { $0.key < $1.key }.map { "\($0.key)=\(kodiere($0.value))" }.joined(separator: "&").utf8)
    }

    // MARK: Dateien

    static func lies<T: Decodable>(_ typ: T.Type, aus datei: URL) -> T? {
        guard let daten = try? Data(contentsOf: datei) else { return nil }
        return try? Ablage.entschluessler.decode(typ, from: daten)
    }

    /// Atomar und nur für den Nutzer lesbar, wie OpenAI es für Tokens verlangt.
    static func schreibe<T: Encodable>(_ wert: T, nach datei: URL) throws {
        try FileManager.default.createDirectory(at: datei.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Ablage.verschluessler.encode(wert).write(to: datei, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: datei.path)
    }
}

/// state, nonce und PKCE-Schlüssel – für jeden Versuch neu.
struct Anmeldeversuch {
    let state = Anmeldeversuch.zufall()
    let nonce = Anmeldeversuch.zufall()
    let verifier = Anmeldeversuch.zufall(bytes: 48)

    var challenge: String { Anmeldeversuch.base64url(Data(SHA256.hash(data: Data(verifier.utf8)))) }

    static func zufall(bytes: Int = 32) -> String {
        var daten = Data(count: bytes)
        _ = daten.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return base64url(daten)
    }

    static func base64url(_ daten: Data) -> String {
        daten.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - ID-Token

struct Identitaet: Equatable {
    let subject: String
    let email: String
}

/// Prüft den ID-Token so, wie OpenAI es vorgibt: Signatur gegen die veröffentlichten Schlüssel,
/// dann Aussteller, Empfänger, Ablauf und Nonce.
enum IdToken {
    static func pruefe(_ token: String, schluessel jwks: Data, aussteller: String, publikum: String, nonce: String, jetzt: Date = Date()) throws -> Identitaet {
        let teile = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard teile.count == 3, let kopfDaten = base64url(teile[0]), let inhaltDaten = base64url(teile[1]), let signatur = base64url(teile[2]),
              let kopf = try? JSONSerialization.jsonObject(with: kopfDaten) as? [String: Any],
              let inhalt = try? JSONSerialization.jsonObject(with: inhaltDaten) as? [String: Any] else {
            throw ChatGPTFehler.anmeldungFehlgeschlagen("ID-Token ist nicht lesbar.")
        }
        guard kopf["alg"] as? String == "RS256" else { throw ChatGPTFehler.anmeldungFehlgeschlagen("Unerwartetes Signaturverfahren.") }

        let schluessel = ((try? JSONSerialization.jsonObject(with: jwks) as? [String: Any])?["keys"] as? [[String: Any]]) ?? []
        let passend = schluessel.filter { ($0["kty"] as? String) == "RSA" && (kopf["kid"] == nil || ($0["kid"] as? String) == kopf["kid"] as? String) }
        let gueltig = passend.contains { jwk in
            guard let n = (jwk["n"] as? String).flatMap(base64url), let e = (jwk["e"] as? String).flatMap(base64url),
                  let key = rsaSchluessel(modulus: n, exponent: e) else { return false }
            return SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data("\(teile[0]).\(teile[1])".utf8) as CFData, signatur as CFData, nil)
        }
        guard gueltig else { throw ChatGPTFehler.anmeldungFehlgeschlagen("Die Signatur des ID-Tokens stimmt nicht.") }

        guard inhalt["iss"] as? String == aussteller else { throw ChatGPTFehler.anmeldungFehlgeschlagen("Falscher Aussteller.") }
        let empfaenger = (inhalt["aud"] as? [String]) ?? [(inhalt["aud"] as? String) ?? ""]
        guard empfaenger.contains(publikum) else { throw ChatGPTFehler.anmeldungFehlgeschlagen("Der ID-Token ist für eine andere App.") }
        guard let ablauf = (inhalt["exp"] as? NSNumber)?.doubleValue, Date(timeIntervalSince1970: ablauf) > jetzt.addingTimeInterval(-60) else {
            throw ChatGPTFehler.anmeldungFehlgeschlagen("Der ID-Token ist abgelaufen.")
        }
        guard inhalt["nonce"] as? String == nonce else { throw ChatGPTFehler.anmeldungFehlgeschlagen("Nonce stimmt nicht.") }
        guard let subject = inhalt["sub"] as? String else { throw ChatGPTFehler.anmeldungFehlgeschlagen("Kein Konto im ID-Token.") }
        return Identitaet(subject: subject, email: inhalt["email"] as? String ?? "")
    }

    static func base64url(_ text: String) -> Data? {
        var b = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return Data(base64Encoded: b)
    }

    /// Baut aus Modulus und Exponent einen öffentlichen RSA-Schlüssel (PKCS#1, DER).
    static func rsaSchluessel(modulus: Data, exponent: Data) -> SecKey? {
        func laenge(_ n: Int) -> [UInt8] {
            if n < 0x80 { return [UInt8(n)] }
            let bytes = withUnsafeBytes(of: UInt32(n).bigEndian, Array.init).drop { $0 == 0 }
            return [0x80 | UInt8(bytes.count)] + bytes
        }
        func ganzzahl(_ daten: Data) -> [UInt8] {
            var wert = Array(daten.drop { $0 == 0 })
            if wert.isEmpty { wert = [0] }
            if wert[0] >= 0x80 { wert.insert(0, at: 0) }
            return [0x02] + laenge(wert.count) + wert
        }
        let folge = ganzzahl(modulus) + ganzzahl(exponent)
        let der = Data([0x30] + laenge(folge.count) + folge)
        let attribute: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
        return SecKeyCreateWithData(der as CFData, attribute as CFDictionary, nil)
    }
}

// MARK: - Rückruf

/// Lässt genau einen Aufrufer durch – für Fortsetzungen, die nur einmal fortgesetzt werden dürfen.
final class Einmal: @unchecked Sendable {
    private let schloss = NSLock()
    private var erledigt = false
    func zuerst() -> Bool {
        schloss.lock(); defer { schloss.unlock() }
        if erledigt { return false }
        erledigt = true
        return true
    }
}

/// Kleiner HTTP-Empfänger auf 127.0.0.1 für den einen Rückruf nach der Anmeldung im Browser.
final class Rueckrufempfaenger: @unchecked Sendable {
    private let lauscher: NWListener
    private let pfad: String
    private let schloss = NSLock()
    private var fortsetzung: CheckedContinuation<[String: String], Error>?
    private var ergebnis: Result<[String: String], Error>?
    private(set) var port: UInt16 = 0

    private init(lauscher: NWListener, pfad: String) {
        self.lauscher = lauscher
        self.pfad = pfad
    }

    static func starte(pfad: String) async throws -> Rueckrufempfaenger {
        let parameter = NWParameters.tcp
        parameter.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        let lauscher = try NWListener(using: parameter)
        let empfaenger = Rueckrufempfaenger(lauscher: lauscher, pfad: pfad)
        lauscher.newConnectionHandler = { [weak empfaenger] verbindung in empfaenger?.bediene(verbindung) }
        try await withCheckedThrowingContinuation { (bereit: CheckedContinuation<Void, Error>) in
            let einmal = Einmal()
            lauscher.stateUpdateHandler = { zustand in
                switch zustand {
                case .ready: if einmal.zuerst() { bereit.resume() }
                case .failed(let fehler): if einmal.zuerst() { bereit.resume(throwing: fehler) }
                default: break
                }
            }
            lauscher.start(queue: .global(qos: .userInitiated))
        }
        empfaenger.port = lauscher.port?.rawValue ?? 0
        return empfaenger
    }

    func warte(hoechstens sekunden: TimeInterval) async throws -> [String: String] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { fortsetzung in
                schloss.lock()
                if let ergebnis {
                    schloss.unlock()
                    fortsetzung.resume(with: ergebnis)
                    return
                }
                self.fortsetzung = fortsetzung
                schloss.unlock()
                DispatchQueue.global().asyncAfter(deadline: .now() + sekunden) { [weak self] in
                    self?.liefere(.failure(ChatGPTFehler.zeitueberschreitung))
                }
            }
        } onCancel: {
            liefere(.failure(ChatGPTFehler.abgebrochen))
        }
    }

    func beende() { lauscher.cancel() }

    private func liefere(_ wert: Result<[String: String], Error>) {
        schloss.lock()
        guard ergebnis == nil else { schloss.unlock(); return }
        ergebnis = wert
        let wartend = fortsetzung
        fortsetzung = nil
        schloss.unlock()
        wartend?.resume(with: wert)
    }

    private func bediene(_ verbindung: NWConnection) {
        verbindung.start(queue: .global(qos: .userInitiated))
        verbindung.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] daten, _, _, _ in
            guard let self else { return }
            let anfrage = String(decoding: daten ?? Data(), as: UTF8.self)
            let parameter = Self.parameter(ausAnfrage: anfrage, pfad: self.pfad)
            let seite = parameter == nil ? (404, "Nicht gefunden.") :
                (parameter?["error"] == nil ? (200, "Weiter in Kost – die App schließt die Anmeldung jetzt ab und zeigt, ob es geklappt hat. Dieses Fenster kannst du schließen.")
                                            : (200, "Anmeldung abgebrochen. Du kannst dieses Fenster schließen."))
            let html = "<!doctype html><meta charset=utf-8><title>Kost</title><body style=\"font:16px -apple-system;margin:4em;text-align:center\"><p>\(seite.1)</p>"
            let antwort = "HTTP/1.1 \(seite.0) OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(Data(html.utf8).count)\r\nConnection: close\r\n\r\n\(html)"
            verbindung.send(content: Data(antwort.utf8), completion: .contentProcessed { _ in verbindung.cancel() })
            if let parameter { self.liefere(.success(parameter)) }
        }
    }

    /// Liest aus "GET /auth/callback?code=…&state=… HTTP/1.1" die Parameter – nil bei anderem Pfad.
    static func parameter(ausAnfrage anfrage: String, pfad: String) -> [String: String]? {
        guard let zeile = anfrage.split(separator: "\r\n", maxSplits: 1).first ?? anfrage.split(separator: "\n").first else { return nil }
        let teile = zeile.split(separator: " ")
        guard teile.count >= 2, teile[0] == "GET", let adresse = URLComponents(string: String(teile[1])), adresse.path == pfad else { return nil }
        var ergebnis: [String: String] = [:]
        for eintrag in adresse.queryItems ?? [] { ergebnis[eintrag.name] = eintrag.value ?? "" }
        return ergebnis
    }
}

// MARK: - Schätzer

/// Schätzt über die Responses-API mit dem ChatGPT-Abo des Nutzers.
public struct ChatGPTSchaetzer: Sendable {
    public let zugang: ChatGPTZugang
    public let modell: String

    public init(zugang: ChatGPTZugang, modell: String) {
        self.zugang = zugang
        self.modell = modell
    }

    public func schaetze(text: String, bilder: [Bildanhang] = []) async throws -> Schaetzung {
        do {
            return try await sende(text: text, bilder: bilder, token: try await zugang.zugangstoken())
        } catch let fehler as Abgelehnt where fehler.status == 401 {
            // Token kurz vor der Zeit ungültig geworden: einmal auffrischen und nochmal.
            return try await sende(text: text, bilder: bilder, token: try await zugang.frischeAuf().accessToken)
        }
    }

    struct Abgelehnt: Error {
        let status: Int
        let text: String
    }

    static func anfrage(modell: String, text: String, bilder: [Bildanhang]) -> [String: Any] {
        var inhalt: [[String: Any]] = bilder.map {
            ["type": "input_image", "image_url": "data:image/jpeg;base64," + $0.jpeg.base64EncodedString()]
        }
        inhalt.append(["type": "input_text", "text": Schaetzauftrag.anfrage(text: text, bilder: bilder.count)])
        return [
            "model": modell,
            "instructions": Schaetzauftrag.systemprompt,
            "input": [["role": "user", "content": inhalt]],
            "text": ["format": ["type": "json_schema", "name": "schaetzung", "schema": Schaetzauftrag.schema, "strict": true]],
            // Vorgabe von OpenAI für Abo-Nutzung: nichts speichern, immer streamen.
            "store": false,
            "stream": true,
        ]
    }

    private func sende(text: String, bilder: [Bildanhang], token: String) async throws -> Schaetzung {
        var anfrage = URLRequest(url: URL(string: "\(ChatGPTZugang.ressource)/responses")!, timeoutInterval: 120)
        anfrage.httpMethod = "POST"
        anfrage.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        anfrage.setValue("application/json", forHTTPHeaderField: "Content-Type")
        anfrage.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        anfrage.httpBody = try JSONSerialization.data(withJSONObject: Self.anfrage(modell: modell, text: text, bilder: bilder))

        let (bytes, antwort) = try await URLSession.shared.bytes(for: anfrage)
        let status = (antwort as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var koerper = ""
            for try await zeile in bytes.lines { koerper += zeile }
            throw status == 401 ? Abgelehnt(status: status, text: koerper) : Self.fehler(ausKoerper: koerper, status: status)
        }
        var zeilen: [String] = []
        for try await zeile in bytes.lines { zeilen.append(zeile) }
        return try Self.werteAus(stream: zeilen)
    }

    /// Wertet die Server-Sent-Events aus: Textstücke sammeln, erst bei `response.completed` gilt es als fertig.
    static func werteAus(stream zeilen: [String]) throws -> Schaetzung {
        var text = ""
        var fertig = false
        for zeile in zeilen where zeile.hasPrefix("data:") {
            let nutzlast = zeile.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard nutzlast != "[DONE]", let ereignis = try? JSONSerialization.jsonObject(with: Data(nutzlast.utf8)) as? [String: Any] else { continue }
            switch ereignis["type"] as? String {
            case "response.output_text.delta":
                text += ereignis["delta"] as? String ?? ""
            case "response.completed":
                fertig = true
            case "response.failed":
                let fehler = (ereignis["response"] as? [String: Any])?["error"] as? [String: Any]
                throw Self.fehler(code: fehler?["code"] as? String, meldung: fehler?["message"] as? String)
            case "response.incomplete":
                throw ChatGPTFehler.antwortFehler("Die Antwort ist unvollständig geblieben.")
            case "error":
                throw Self.fehler(code: ereignis["code"] as? String, meldung: ereignis["message"] as? String)
            default:
                break
            }
        }
        guard fertig else { throw ChatGPTFehler.antwortFehler("Die Verbindung brach vor dem Ende der Antwort ab.") }
        guard let roh = Schaetzauftrag.jsonObjekt(aus: text) else { throw Schaetzfehler.antwortUnlesbar }
        return try Schaetzauftrag.schaetzung(aus: roh)
    }

    static func fehler(ausKoerper koerper: String, status: Int) -> Error {
        let objekt = (try? JSONSerialization.jsonObject(with: Data(koerper.utf8)) as? [String: Any])?["error"] as? [String: Any]
        return fehler(code: objekt?["code"] as? String, meldung: objekt?["message"] as? String ?? "HTTP \(status)")
    }

    static func fehler(code: String?, meldung: String?) -> Error {
        switch code {
        case "subscription_sharing_usage_limit_exceeded": return ChatGPTFehler.kontingentErschoepft
        case "subscription_sharing_usage_unavailable": return ChatGPTFehler.aboNichtVerfuegbar
        default: return ChatGPTFehler.antwortFehler(meldung ?? code ?? "unbekannter Fehler")
        }
    }
}
