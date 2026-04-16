import UIKit

final class DialerViewController: UIViewController {

    private let phoneField = UITextField()
    private let stateLabel = UILabel()
    private let callButton = UIButton(type: .system)
    private let hangupButton = UIButton(type: .system)
    private let parkButton = UIButton(type: .system)

    static func embeddedInNavigationController() -> UINavigationController {
        UINavigationController(rootViewController: DialerViewController())
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Dialer"
        view.backgroundColor = .white

        phoneField.placeholder = "Enter phone"
        phoneField.borderStyle = .roundedRect

        stateLabel.text = "Idle"
        stateLabel.textAlignment = .center

        callButton.setTitle("Call", for: .normal)
        hangupButton.setTitle("Hangup", for: .normal)
        parkButton.setTitle("Park", for: .normal)
        parkButton.setTitleColor(.systemOrange, for: .normal)
        parkButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)

        callButton.addTarget(self, action: #selector(callTapped), for: .touchUpInside)
        hangupButton.addTarget(self, action: #selector(hangupTapped), for: .touchUpInside)
        parkButton.addTarget(self, action: #selector(parkCall), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [phoneField, stateLabel, callButton, hangupButton, parkButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.widthAnchor.constraint(equalToConstant: 280),
        ])

        CallManager.shared.onStateChange = { [weak self] state in
            DispatchQueue.main.async {
                self?.render(state: state)
            }
        }

        CallManager.shared.initialize { [weak self] result in
            guard let self else { return }
            if case .failure(let error) = result {
                self.render(state: .failed(error.localizedDescription))
            }
        }
    }

    @objc private func callTapped() {
        guard let number = phoneField.text, !number.isEmpty else {
            render(state: .failed("Please enter a destination number"))
            return
        }

        CallManager.shared.startCall(to: number)
    }

    @objc private func hangupTapped() {
        CallManager.shared.hangup()
    }

    @objc private func parkCall() {
        guard let callSid = CallManager.shared.activeCallSid else { return }

        Task {
            do {
                _ = try await APIClient.request(
                    path: "/api/telephony/park",
                    method: "POST",
                    body: ["callSid": callSid],
                    token: Environment.authToken
                )
                await MainActor.run {
                    self.parkButton.setTitle("Parked ✓", for: .normal)
                    self.parkButton.isEnabled = false
                }
            } catch {
                print("[PARK ERROR]", error)
            }
        }
    }

    private func render(state: CallState) {
        switch state {
        case .idle:
            stateLabel.text = "Idle"
        case .connecting:
            stateLabel.text = "Connecting…"
        case .ringing:
            stateLabel.text = "Ringing…"
        case .connected:
            stateLabel.text = "Connected"
        case .ended:
            stateLabel.text = "Ended"
        case .failed(let message):
            stateLabel.text = "Failed: \(message)"
        }

        callButton.isEnabled = state != .connecting && state != .connected
        hangupButton.isEnabled = state == .connecting || state == .ringing || state == .connected
        parkButton.isEnabled = state == .connected
        if state != .connected {
            parkButton.setTitle("Park", for: .normal)
        }
    }
}
