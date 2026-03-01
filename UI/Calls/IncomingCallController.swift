import UIKit
import TwilioVoice

enum IncomingCallController {

    static func present(invite: CallInvite) {
        guard let root = topViewController() else { return }

        let alert = UIAlertController(
            title: "Incoming Call",
            message: invite.from ?? "Unknown caller",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Reject", style: .destructive) { _ in
            VoiceManager.shared.rejectCall(invite: invite)
        })

        alert.addAction(UIAlertAction(title: "Accept", style: .default) { _ in
            VoiceManager.shared.acceptCall(invite: invite)
        })

        root.present(alert, animated: true)
    }

    private static func topViewController(
        from root: UIViewController? = UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow })?
            .rootViewController
    ) -> UIViewController? {
        if let nav = root as? UINavigationController {
            return topViewController(from: nav.visibleViewController)
        }

        if let tab = root as? UITabBarController,
           let selected = tab.selectedViewController {
            return topViewController(from: selected)
        }

        if let presented = root?.presentedViewController {
            return topViewController(from: presented)
        }

        return root
    }
}
