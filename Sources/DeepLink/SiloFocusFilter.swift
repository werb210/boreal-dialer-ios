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

// BOREAL_DIALER_v821 - which Boreal alerts this Focus lets through (FocusAlertPolicy).
@available(iOS 16.0, *)
enum BorealFocusAlerts: String, AppEnum {
    case all, clientOnly
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Boreal alerts"
    static var caseDisplayRepresentations: [BorealFocusAlerts: DisplayRepresentation] = [
        .all: "All Boreal alerts",
        .clientOnly: "Only client calls and messages",
    ]

    var mode: FocusAlertMode {
        switch self {
        case .all: return .all
        case .clientOnly: return .clientOnly
        }
    }
}

// BOREAL_DIALER_v821 - the one Focus filter is now "Boreal Dialer": the line (v593) plus which alerts show.
// The type name stays BorealSiloFocusFilter so Focus filters people already set up keep working.
@available(iOS 16.0, *)
struct BorealSiloFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Boreal Dialer"
    static var description = IntentDescription("Choose the Boreal line and which Boreal alerts reach you while this Focus is on.")

    @Parameter(title: "Line", default: .bf)
    var line: BorealFocusSilo

    // BOREAL_DIALER_v821 - the default (.all) is also what the app falls back to when the Focus ends.
    @Parameter(title: "Alerts", default: .all)
    var alerts: BorealFocusAlerts

    var displayRepresentation: DisplayRepresentation {
        let alertText = alerts == .clientOnly ? "Client calls and messages only" : "All alerts"
        return DisplayRepresentation(title: "Boreal Dialer", subtitle: "\(line.rawValue.uppercased()) · \(alertText)")
    }

    // BOREAL_DIALER_v821 - the system hides notifications marked "internal" (filterCriteria) while this Focus is on.
    var appContext: FocusFilterAppContext {
        FocusFilterAppContext(notificationFilterPredicate: FocusAlertPolicy.notificationPredicate(for: alerts.mode))
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // BOREAL_DIALER_v831_DIALER_POLISH - through LineManager, the one place the line changes, so the server
        // requests, the calling token and the call screen all follow it. Setting VoiceEngine's line on its own moved
        // only texts and the token to the Focus's silo. A line this app doesn't offer is left alone.
        // Switching lines ends the call in progress, so a Focus that turns on mid-call leaves the line as it is.
        if !VoiceEngine.shared.isOnCall,
           let target = LineManager.shared.availableLines.first(where: { $0.silo.rawValue == line.rawValue }) {
            LineManager.shared.switchLine(to: target)
        }
        FocusAlertPolicy.currentMode = alerts.mode // BOREAL_DIALER_v821 - read by willPresent
        return .result()
    }
}
#endif
