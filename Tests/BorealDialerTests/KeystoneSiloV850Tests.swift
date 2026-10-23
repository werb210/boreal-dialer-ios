import XCTest
@testable import BorealDialer

// DIALER_v850_KS_CRM - the Keystone (KS) silo: parsing, the X-Silo header, who may use it, and readable colours.
final class KeystoneSiloV850Tests: XCTestCase {

    func testKeystoneParsesAndEncodesAsKS() throws {
        XCTAssertEqual(Silo(rawValue: "ks"), .ks)
        XCTAssertEqual(APIConfig.siloHeader(for: .ks), "KS")
        let encoded = try JSONEncoder().encode([Silo.ks])
        XCTAssertEqual(String(data: encoded, encoding: .utf8), #"["ks"]"#)
        XCTAssertEqual(try JSONDecoder().decode([Silo].self, from: encoded), [.ks])
    }

    func testEverySiloSendsItsOwnUpperCaseHeader() {
        let headers = Silo.allCases.map { APIConfig.siloHeader(for: $0) }
        XCTAssertEqual(headers, ["BF", "BI", "SLF", "KS"])
        for silo in Silo.allCases {
            XCTAssertEqual(APIConfig.siloHeader(for: silo), silo.rawValue.uppercased())
        }
    }

    @MainActor
    func testKeystoneLineMapsToTheKeystoneCallingLine() {
        XCTAssertEqual(KeystoneAccess.line.id, "KS")
        XCTAssertEqual(KeystoneAccess.line.silo, .ks)
        XCTAssertEqual(KeystoneAccess.line.name, "Keystone")
        // CallManager.setActiveLine maps Line.id (lower-cased) to the engine's line; the token asks for lineId KS.
        let engineLine = VoiceEngine.Line(rawValue: KeystoneAccess.line.id.lowercased())
        XCTAssertEqual(engineLine, .ks)
        XCTAssertEqual(engineLine?.backendLineId, "KS")
        XCTAssertEqual(Silo(rawValue: VoiceEngine.Line.ks.rawValue), .ks)
    }

    func testOnlyAdminAndMarketingSeeKeystone() {
        XCTAssertTrue(KeystoneAccess.canUse(role: "Admin"))
        XCTAssertTrue(KeystoneAccess.canUse(role: " marketing "))
        XCTAssertFalse(KeystoneAccess.canUse(role: "Staff"))
        XCTAssertFalse(KeystoneAccess.canUse(role: "Ops"))
        XCTAssertFalse(KeystoneAccess.canUse(role: "Lender"))
        XCTAssertFalse(KeystoneAccess.canUse(role: nil))

        let bf = Line(id: "BF", name: "Boreal Financial", baseURL: URL(string: APIConfig.BASE_URL)!, wsURL: nil, silo: .bf)
        XCTAssertEqual(KeystoneAccess.lines(base: [bf], role: "Admin").map(\.id), ["BF", "KS"])
        XCTAssertEqual(KeystoneAccess.lines(base: [bf], role: "Staff").map(\.id), ["BF"])
        XCTAssertEqual(KeystoneAccess.lines(base: [bf], role: nil).map(\.id), ["BF"])

        XCTAssertEqual(KeystoneAccess.contactSilos(role: "Marketing"), [.bf, .bi, .slf, .ks])
        XCTAssertEqual(KeystoneAccess.contactSilos(role: "Staff"), [.bf, .bi, .slf])
    }

    func testSiriSearchesTheLineInUse() {
        XCTAssertEqual(KeystoneAccess.searchSilo(active: .ks), .ks)
        XCTAssertEqual(KeystoneAccess.searchSilo(active: .bf), .bf)
        XCTAssertEqual(KeystoneAccess.searchSilo(active: .bi), .bf)
    }

    func testKeystoneColoursAreReadable() {
        // White text on the violet fill (the "Keystone line" banner).
        XCTAssertGreaterThanOrEqual(KeystoneAccess.contrastRatio(0xFFFFFF, KeystoneAccess.accentHex), 4.5)
        // Violet text on the dark theme's background and raised surfaces.
        for surface: UInt32 in [0x0A0B0D, 0x121419, 0x181B21, 0x1F232B, 0x000000] {
            XCTAssertGreaterThanOrEqual(KeystoneAccess.contrastRatio(KeystoneAccess.textHex, surface), 4.5)
        }
        // The portal accent itself is too dark to be text on this theme - which is why it is only a fill here.
        XCTAssertLessThan(KeystoneAccess.contrastRatio(KeystoneAccess.accentHex, 0x0A0B0D), 4.5)
    }

    func testLiveActivityNamesTheKeystoneLine() {
        XCTAssertEqual(SiloLabel.callStatus("Connected", line: "KS"), "Keystone \u{00B7} Connected")
        XCTAssertEqual(SiloLabel.callStatus("Connected", line: "BF"), "Connected")
        XCTAssertEqual(SiloLabel.callStatus("Connected", line: "??"), "Connected")
        XCTAssertEqual(SiloLabel.name(forCode: "ks"), "Keystone")
    }

    func testWatchVocabularyCarriesKeystoneCalls() throws {
        XCTAssertEqual(try JSONDecoder().decode(BorealLine.self, from: Data(#""KS""#.utf8)), .KS)
        XCTAssertEqual(BorealLine.KS.displayName, "Keystone")
        XCTAssertEqual(BorealLine(rawValue: APIConfig.siloHeader(for: .ks)), .KS)
    }

    #if canImport(AppIntents)
    func testFocusFilterOffersTheKeystoneLine() {
        XCTAssertEqual(BorealFocusSilo(rawValue: Silo.ks.rawValue), .ks)
        XCTAssertNotNil(BorealFocusSilo.caseDisplayRepresentations[.ks])
    }
    #endif
}
