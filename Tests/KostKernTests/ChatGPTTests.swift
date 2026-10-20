import CryptoKit
import Security
import XCTest
@testable import KostKern

final class ChatGPTTests: XCTestCase {
    func testAnmeldeadresseErsteRegistrierungUndWiederkehr() throws {
        let versuch = Anmeldeversuch()
        let erste = ChatGPTZugang.anmeldeadresse(
            versuch: versuch, rueckruf: "http://127.0.0.1:51234/auth/callback",
            registrierung: ChatGPTRegistrierung(hostId: "urn:uuid:abc")
        )
        let teile = try XCTUnwrap(URLComponents(url: erste, resolvingAgainstBaseURL: false))
        let p = Dictionary(uniqueKeysWithValues: (teile.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(teile.host, "auth.openai.com")
        XCTAssertEqual(teile.path, "/api/accounts/authorize")
        XCTAssertEqual(p["client_id"], "dynamic_agent_client")
        XCTAssertEqual(p["agent_name_hint"], "Kost")
        XCTAssertNil(p["id_token_hint"])
        XCTAssertEqual(p["redirect_uri"], "http://127.0.0.1:51234/auth/callback")
        XCTAssertEqual(p["scope"], "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct")
        XCTAssertEqual(p["resource"], "https://api.openai.com/v1")
        XCTAssertEqual(p["code_challenge_method"], "S256")
        XCTAssertEqual(p["ext_agent_host_id"], "urn:uuid:abc")
        // PKCE: Challenge = base64url(SHA-256(Verifier)) ohne Auffüllung
        let erwartet = Anmeldeversuch.base64url(Data(SHA256.hash(data: Data(versuch.verifier.utf8))))
        XCTAssertEqual(p["code_challenge"], erwartet)
        XCTAssertFalse(erwartet.contains("="))
        // Leerzeichen als %20, nicht als +
        XCTAssertTrue(erste.absoluteString.contains("scope=openid%20profile"))

        let wieder = ChatGPTZugang.anmeldeadresse(
            versuch: versuch, rueckruf: "http://127.0.0.1:60000/auth/callback",
            registrierung: ChatGPTRegistrierung(hostId: "urn:uuid:abc", clientId: "oaiapp_123", idTokenHinweis: "eyJ.x.y")
        )
        let q = Dictionary(uniqueKeysWithValues: (URLComponents(url: wieder, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(q["client_id"], "oaiapp_123")
        XCTAssertNil(q["agent_name_hint"], "Name nur bei der ersten Registrierung")
        XCTAssertEqual(q["id_token_hint"], "eyJ.x.y")
    }

    func testRueckrufWirdNurAufDemRichtigenPfadGelesen() {
        let anfrage = "GET /auth/callback?code=abc%2B1&state=xyz&client_id=oaiapp_9 HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        XCTAssertEqual(Rueckrufempfaenger.parameter(ausAnfrage: anfrage, pfad: "/auth/callback"), ["code": "abc+1", "state": "xyz", "client_id": "oaiapp_9"])
        XCTAssertNil(Rueckrufempfaenger.parameter(ausAnfrage: "GET /favicon.ico HTTP/1.1\r\n\r\n", pfad: "/auth/callback"))
        XCTAssertNil(Rueckrufempfaenger.parameter(ausAnfrage: "GET /callback?code=1 HTTP/1.1\r\n\r\n", pfad: "/auth/callback"))
    }

    func testRueckrufUeberEchtenLokalenAnschluss() async throws {
        let empfaenger = try await Rueckrufempfaenger.starte(pfad: "/auth/callback")
        defer { empfaenger.beende() }
        XCTAssertGreaterThan(empfaenger.port, 0)
        let adresse = URL(string: "http://127.0.0.1:\(empfaenger.port)/auth/callback?code=c1&state=s1")!
        async let seite = URLSession.shared.data(from: adresse)
        let parameter = try await empfaenger.warte(hoechstens: 5)
        XCTAssertEqual(parameter["code"], "c1")
        let (daten, _) = try await seite
        XCTAssertTrue(String(decoding: daten, as: UTF8.self).contains("Weiter in Kost"))
    }

    func testStreamAuswerten() throws {
        let json = #"{"posten":[{"name":"Apfel","menge":180,"einheit":"g","kcal":95,"eiweiss":0.5,"kohlenhydrate":25,"zucker":19,"fett":0.3,"gesaettigt":0.1,"ballaststoffe":4.4,"salz":0}],"annahmen":"","sicherheit":"hoch"}"#
        let mitte = json.index(json.startIndex, offsetBy: 40)
        func delta(_ text: Substring) -> String {
            let objekt: [String: Any] = ["type": "response.output_text.delta", "delta": String(text)]
            return "data: " + String(decoding: try! JSONSerialization.data(withJSONObject: objekt), as: UTF8.self)
        }
        let zeilen = [
            "event: response.created", #"data: {"type":"response.created"}"#, "",
            "event: response.output_text.delta", delta(json[..<mitte]), "",
            "event: response.output_text.delta", delta(json[mitte...]), "",
            "event: response.completed", #"data: {"type":"response.completed","response":{}}"#,
        ]
        let schaetzung = try ChatGPTSchaetzer.werteAus(stream: zeilen)
        XCTAssertEqual(schaetzung.posten.first?.name, "Apfel")
        XCTAssertEqual(schaetzung.sicherheit, .hoch)

        XCTAssertThrowsError(try ChatGPTSchaetzer.werteAus(stream: Array(zeilen.dropLast()))) { fehler in
            guard case ChatGPTFehler.antwortFehler = fehler else { return XCTFail("\(fehler)") }
        }
        let gesperrt = [#"data: {"type":"response.failed","response":{"error":{"code":"subscription_sharing_usage_limit_exceeded","message":"limit"}}}"#]
        XCTAssertThrowsError(try ChatGPTSchaetzer.werteAus(stream: gesperrt)) { XCTAssertEqual($0 as? ChatGPTFehler, .kontingentErschoepft) }
    }

    func testAnfrageHaeltSichAnDieVorgaben() throws {
        let anfrage = ChatGPTSchaetzer.anfrage(modell: "gpt-x-mini", text: "Apfel", bilder: [Bildanhang(jpeg: Data([1, 2]))])
        XCTAssertEqual(anfrage["store"] as? Bool, false)
        XCTAssertEqual(anfrage["stream"] as? Bool, true)
        XCTAssertNotNil(anfrage["instructions"], "Systemtext über instructions, nie als system-Nachricht")
        let verboten = ["background", "conversation", "max_output_tokens", "metadata", "temperature", "top_p", "truncation", "user", "previous_response_id"]
        for feld in verboten { XCTAssertNil(anfrage[feld], feld) }
        let inhalt = try XCTUnwrap(((anfrage["input"] as? [[String: Any]])?.first)?["content"] as? [[String: Any]])
        XCTAssertEqual(inhalt.first?["type"] as? String, "input_image")
        XCTAssertEqual(inhalt.first?["image_url"] as? String, "data:image/jpeg;base64,AQI=")
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: anfrage))
    }

    func testIdTokenPruefung() throws {
        // Eigenen Schlüssel erzeugen, Token signieren und als JWKS bereitstellen
        let attribute: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048]
        let privat = try XCTUnwrap(SecKeyCreateRandomKey(attribute as CFDictionary, nil))
        let oeffentlich = try XCTUnwrap(SecKeyCopyPublicKey(privat))
        let der = try XCTUnwrap(SecKeyCopyExternalRepresentation(oeffentlich, nil) as Data?)
        let (n, e) = try Self.modulusUndExponent(ausDER: der)
        let jwks = try JSONSerialization.data(withJSONObject: ["keys": [["kty": "RSA", "kid": "k1", "n": Anmeldeversuch.base64url(n), "e": Anmeldeversuch.base64url(e)]]])

        func token(_ inhalt: [String: Any], kid: String = "k1") throws -> String {
            let kopf = Anmeldeversuch.base64url(try JSONSerialization.data(withJSONObject: ["alg": "RS256", "kid": kid]))
            let rumpf = Anmeldeversuch.base64url(try JSONSerialization.data(withJSONObject: inhalt))
            let signatur = try XCTUnwrap(SecKeyCreateSignature(privat, .rsaSignatureMessagePKCS1v15SHA256, Data("\(kopf).\(rumpf)".utf8) as CFData, nil) as Data?)
            return "\(kopf).\(rumpf).\(Anmeldeversuch.base64url(signatur))"
        }
        let gut: [String: Any] = ["iss": "https://auth.openai.com", "aud": "oaiapp_1", "exp": Date().timeIntervalSince1970 + 600, "nonce": "n1", "sub": "user-1", "email": "a@b.de"]
        let identitaet = try IdToken.pruefe(try token(gut), schluessel: jwks, aussteller: "https://auth.openai.com", publikum: "oaiapp_1", nonce: "n1")
        XCTAssertEqual(identitaet, Identitaet(subject: "user-1", email: "a@b.de"))

        XCTAssertThrowsError(try IdToken.pruefe(try token(gut), schluessel: jwks, aussteller: "https://auth.openai.com", publikum: "oaiapp_1", nonce: "falsch"))
        XCTAssertThrowsError(try IdToken.pruefe(try token(gut), schluessel: jwks, aussteller: "https://auth.openai.com", publikum: "andere-app", nonce: "n1"))
        var faelschung = try token(gut)
        faelschung.removeLast(4)
        faelschung += "AAAA"
        XCTAssertThrowsError(try IdToken.pruefe(faelschung, schluessel: jwks, aussteller: "https://auth.openai.com", publikum: "oaiapp_1", nonce: "n1"))
    }

    func testSitzungLiegtNurFuerDenNutzerLesbar() throws {
        let ordner = FileManager.default.temporaryDirectory.appendingPathComponent("kost-gpt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: ordner) }
        let datei = ordner.appendingPathComponent("chatgpt-sitzung.json")
        let sitzung = ChatGPTSitzung(email: "a@b.de", subject: "s", clientId: "c", idToken: "i", accessToken: "a", refreshToken: "r", ablauf: Date(), scopes: ["x"])
        try ChatGPTZugang.schreibe(sitzung, nach: datei)
        let rechte = try FileManager.default.attributesOfItem(atPath: datei.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(rechte?.intValue, 0o600)
        XCTAssertEqual(ChatGPTZugang.lies(ChatGPTSitzung.self, aus: datei)?.refreshToken, "r")
    }

    func testModellliste() {
        let daten = Data(#"{"data":[{"slug":"gpt-6.1-sol","visibility":"list"},{"slug":"gpt-6.1-mini","visibility":"list"},{"slug":"intern","visibility":"hide"}]}"#.utf8)
        let namen = ChatGPTZugang.modellnamen(aus: daten)
        XCTAssertEqual(namen, ["gpt-6.1-sol", "gpt-6.1-mini"])
        XCTAssertEqual(ChatGPTZugang.vorgabemodell(aus: namen), "gpt-6.1-mini")
    }

    /// PKCS#1-DER: SEQUENCE { INTEGER n, INTEGER e }
    static func modulusUndExponent(ausDER der: Data) throws -> (Data, Data) {
        var stelle = der.startIndex
        func laenge() -> Int {
            let erstes = Int(der[stelle]); stelle += 1
            guard erstes & 0x80 != 0 else { return erstes }
            var wert = 0
            for _ in 0..<(erstes & 0x7F) { wert = wert << 8 | Int(der[stelle]); stelle += 1 }
            return wert
        }
        func ganzzahl() -> Data {
            stelle += 1 // 0x02
            let l = laenge()
            let wert = der[stelle..<stelle + l]
            stelle += l
            return Data(wert)
        }
        stelle += 1 // 0x30
        _ = laenge()
        return (ganzzahl(), ganzzahl())
    }
}
