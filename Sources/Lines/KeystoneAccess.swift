import Foundation

// DIALER_v850_KS_CRM - Keystone (KS), the fourth silo. BF-Server treats X-Silo: KS exactly like BF for CRM and
// communications (contacts, companies, SMS threads, call events, the contact timeline), so the dialler only sends it.
//
// Who sees it: Admin and Marketing staff, read from the role claim of the BF-Server sign-in (the same role
// /api/auth/me reports). Everyone else never sees a Keystone line, a Keystone contacts option or a Keystone Focus
// line, and a Keystone line saved on this phone by someone else falls back to BF (LineManager.enforceAccess).
enum KeystoneAccess {
    static let allowedRoles: Set<String> = ["admin", "marketing"]
    static let lineName = "Keystone"

    /// The portal's Keystone violet, used as a fill: white text on it is 7.1:1.
    static let accentHex: UInt32 = 0x6D28D9
    /// Violet for text on the app's dark surfaces: 10.7:1 on the background (#6D28D9 there would be only 2.8:1).
    static let textHex: UInt32 = 0xC4B5FD

    static func canUse(role: String?) -> Bool {
        guard let role else { return false }
        return allowedRoles.contains(role.trimmingCharacters(in: .whitespaces).lowercased())
    }

    static func currentRole() -> String? {
        JWTClaims.role(of: TokenStorage.shared.getToken())
    }

    /// The Keystone calling line. Same server as BF; the silo travels in X-Silo.
    static let line = Line(
        id: "KS",
        name: lineName,
        baseURL: URL(string: APIConfig.BASE_URL)!,
        wsURL: nil,
        silo: .ks
    )

    /// The lines this role may pick: the base lines, plus Keystone for Admin and Marketing.
    static func lines(base: [Line], role: String?) -> [Line] {
        canUse(role: role) ? base + [line] : base
    }

    /// The Contacts tab's silo options.
    static func contactSilos(role: String?) -> [Silo] {
        canUse(role: role) ? [.bf, .bi, .slf, .ks] : [.bf, .bi, .slf]
    }

    /// Siri's "call a client" searches the line in use: Keystone's contacts on the Keystone line, otherwise BF's.
    static func searchSilo(active: Silo) -> Silo {
        active == .ks ? .ks : .bf
    }

    /// WCAG contrast ratio between two sRGB colours (0xRRGGBB); 4.5 is the minimum for body text.
    static func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double {
        func channel(_ value: UInt32) -> Double {
            let c = Double(value & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        func luminance(_ hex: UInt32) -> Double {
            0.2126 * channel(hex >> 16) + 0.7152 * channel(hex >> 8) + 0.0722 * channel(hex)
        }
        let la = luminance(a)
        let lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
