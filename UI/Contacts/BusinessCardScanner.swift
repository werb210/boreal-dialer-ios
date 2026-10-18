import SwiftUI
import UIKit
import Vision
import VisionKit

// BOREAL_DIALER_v823_CARD_SCAN
// New contact > "Scan business card": the iPhone document camera finds and flattens the card, the text is read on the
// phone (Vision), and name, company, mobile and email are filled in for checking before Save. Nothing is uploaded.
struct ScannedCard: Equatable {
    var firstName = ""
    var lastName = ""
    var company = ""
    var phone = ""
    var email = ""
}

enum BusinessCardParser {
    private static let companyWords = ["inc", "ltd", "llc", "corp", "corporation", "company", "co.", "group", "capital",
                                       "financial", "finance", "leasing", "holdings", "partners", "solutions", "services",
                                       "enterprises", "construction", "logistics", "industries", "limited"]
    private static let titleWords = ["president", "ceo", "cfo", "coo", "owner", "director", "manager", "vp", "vice",
                                     "founder", "partner", "officer", "sales", "account", "executive", "broker",
                                     "advisor", "consultant", "controller", "principal", "associate"]

    /// Lines of text read off a card -> the fields a contact needs. Unknown fields stay empty.
    static func parse(_ lines: [String]) -> ScannedCard {
        var card = ScannedCard()
        let cleaned = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let joined = cleaned.joined(separator: "\n")

        // BOREAL_DIALER_v823b_CARD_PHONE - a plain pattern for North American numbers, line by line. NSDataDetector
        // missed a number on its own line ("780-555-0100") on the CI simulator, so it is not used.
        // Prefer a number on a line that says mobile / cell; otherwise the first one.
        var phones: [(number: String, line: String)] = []
        for line in cleaned {
            if let number = phoneIn(line) { phones.append((number, line.lowercased())) }
        }
        let mobile = phones.first { $0.line.contains("cell") || $0.line.contains("mobile") || $0.line.hasPrefix("m:") || $0.line.hasPrefix("m ") }
        if let pick = mobile ?? phones.first { card.phone = pick.number }

        if let email = cleaned.lazy.compactMap({ emailIn($0) }).first {
            card.email = email
        }

        let candidates = cleaned.filter { line in
            let lower = line.lowercased()
            return emailIn(line) == nil
                && !lower.contains("www") && !lower.contains("http") && !lower.contains(".com")
                && line.filter(\.isNumber).count < 3
        }
        if let company = candidates.first(where: { isCompany($0) }) {
            card.company = company
        }
        if let name = candidates.first(where: { isPersonName($0) && $0 != card.company }) {
            let parts = name.split(separator: " ").map(String.init)
            card.firstName = parts.first ?? ""
            card.lastName = parts.dropFirst().joined(separator: " ")
        }
        return card
    }

    /// "+1 (403) 555-0142", "780.555.0100", "4035550142" -> "+14035550142"; nil when the line holds no such number.
    static func phoneIn(_ line: String) -> String? {
        let pattern = "(?<![0-9])(?:\\+?1[\\s.-]?)?\\(?[2-9][0-9]{2}\\)?[\\s.-]?[0-9]{3}[\\s.-]?[0-9]{4}(?![0-9])"
        guard let range = line.range(of: pattern, options: .regularExpression) else { return nil }
        let digits = line[range].filter(\.isNumber)
        if digits.count == 10 { return "+1" + digits }
        if digits.count == 11, digits.hasPrefix("1") { return "+" + digits }
        return nil
    }

    static func emailIn(_ line: String) -> String? {
        guard let range = line.range(of: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", options: .regularExpression) else { return nil }
        return String(line[range]).lowercased()
    }

    static func normalizedPhone(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        if digits.count == 10 { return "+1" + digits }
        if digits.count == 11, digits.hasPrefix("1") { return "+" + digits }
        return raw
    }

    static func isCompany(_ line: String) -> Bool {
        let words = line.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "." }).map(String.init)
        return words.contains { companyWords.contains($0) }
    }

    /// Two or three capitalised words, no title words, no company words.
    static func isPersonName(_ line: String) -> Bool {
        let words = line.split(separator: " ").map(String.init)
        guard (2...3).contains(words.count) else { return false }
        let lower = words.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        guard !lower.contains(where: { titleWords.contains($0) || companyWords.contains($0) }) else { return false }
        return words.allSatisfy { word in
            guard let first = word.first, first.isLetter, first.isUppercase else { return false }
            return word.allSatisfy { $0.isLetter || $0 == "-" || $0 == "'" || $0 == "." }
        }
    }

    /// Reads the text off scanned card images, top to bottom. Synchronous: call it off the main thread.
    static func recognizeLines(in images: [CGImage]) -> [String] {
        var lines: [String] = []
        for image in images {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            let observations = (request.results ?? []).sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
            lines.append(contentsOf: observations.compactMap { $0.topCandidates(1).first?.string })
        }
        return lines
    }
}

/// The system document camera; hands back the scanned pages.
struct CardCameraView: UIViewControllerRepresentable {
    var onFinish: ([CGImage]) -> Void
    var onCancel: () -> Void

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: CardCameraView
        init(_ parent: CardCameraView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<min(scan.pageCount, 2)).compactMap { scan.imageOfPage(at: $0).cgImage }
            parent.onFinish(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.onCancel()
        }
    }
}
