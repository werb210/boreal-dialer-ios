import Foundation
import SwiftUI

struct BrandConfig {

    static func logo(for lineId: String) -> String {
        switch lineId {
        case "bf":
            return "boreal_logo"
        case "bi":
            return "bi_logo"
        case "slf":
            return "slf_logo"
        case "ks": // DIALER_v850_KS_CRM - no Keystone logo asset; the Boreal one
            return "boreal_logo"
        default:
            return "boreal_logo"
        }
    }

    static func primaryColor(for lineId: String) -> Color {
        switch lineId {
        case "bf":
            return Color.blue
        case "bi":
            return Color.green
        case "slf":
            return Color.orange
        case "ks": // DIALER_v850_KS_CRM - the portal's Keystone violet
            return Color(hex: KeystoneAccess.accentHex)
        default:
            return Color.blue
        }
    }
}
