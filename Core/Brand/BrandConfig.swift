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
        default:
            return Color.blue
        }
    }
}
