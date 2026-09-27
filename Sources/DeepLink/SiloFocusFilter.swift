import Foundation
#if canImport(AppIntents)
import AppIntents

// BOREAL_DIALER_v593_FOCUS_FILTER
@available(iOS 16.0, *)
enum BorealFocusSilo: String, AppEnum {
    case bf, bi, slf
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Boreal line"
    static var caseDisplayRepresentations: [BorealFocusSilo: DisplayRepresentation] = [
        .bf: "Boreal Financial",
        .bi: "Boreal Insurance",
        .slf: "Site Level Financial",
    ]
}

@available(iOS 16.0, *)
struct BorealSiloFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Boreal line"
    static var description = IntentDescription("Switch Boreal Dialer to one line while this Focus is on.")

    @Parameter(title: "Line", default: .bf)
    var line: BorealFocusSilo

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Boreal line", subtitle: "\(line.rawValue.uppercased())")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let target = VoiceEngine.Line(rawValue: line.rawValue) {
            VoiceEngine.shared.setActiveLine(target)
        }
        return .result()
    }
}
#endif
