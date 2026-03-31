import UIKit

final class DialerViewController: UIViewController {

    private let phoneField = UITextField()
    private let callButton = UIButton(type: .system)
    private let hangupButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        phoneField.placeholder = "Enter phone"
        phoneField.borderStyle = .roundedRect

        callButton.setTitle("Call", for: .normal)
        hangupButton.setTitle("Hangup", for: .normal)

        callButton.addTarget(self, action: #selector(callTapped), for: .touchUpInside)
        hangupButton.addTarget(self, action: #selector(hangupTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [phoneField, callButton, hangupButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.widthAnchor.constraint(equalToConstant: 250),
        ])

        CallManager.shared.initialize { success in
            print("Init:", success)
        }
    }

    @objc private func callTapped() {
        guard let number = phoneField.text, !number.isEmpty else { return }
        CallManager.shared.startCall(to: number)
    }

    @objc private func hangupTapped() {
        CallManager.shared.hangup()
    }
}
