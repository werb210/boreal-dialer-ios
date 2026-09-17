import Foundation

// BOREAL_DIALER_SHARE_TO_BOREAL_v319
// "Share to Boreal": Boreal Dialer registers as a handler for PDFs, images,
// Word, Excel, CSV and Numbers files, so it appears in the iOS share sheet
// (Mail attachments, Files, Photos, Safari downloads). iOS copies the file into
// the app and opens it; this keeps it until staff choose where it belongs.
// Using document types rather than a Share Extension needs no extra target,
// App Group or provisioning, so it works on today's signing.
struct SharedFile: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }

    var mimeType: String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "application/pdf"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "heic": return "image/heic"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls": return "application/vnd.ms-excel"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "csv": return "text/csv"
        case "numbers": return "application/vnd.apple.numbers"
        default: return "application/octet-stream"
        }
    }
}

@MainActor
final class SharedDocumentInbox: ObservableObject {
    static let shared = SharedDocumentInbox()
    @Published var pending: SharedFile?

    private init() {}

    /// Accepts a file handed to the app. Returns false for anything that is not a local file.
    @discardableResult
    func receive(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SharedToBoreal", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: copy)
        do {
            try FileManager.default.copyItem(at: url, to: copy)
        } catch {
            return false
        }
        pending = SharedFile(url: copy)
        return true
    }

    func finish() {
        if let file = pending { try? FileManager.default.removeItem(at: file.url) }
        pending = nil
    }

    static let categories: [String] = [
        "6 months business banking statements",
        "3 years accountant prepared financials",
        "3 years business tax returns",
        "PnL – Interim financials",
        "Balance Sheet – Interim financials",
        "A/R",
        "A/P",
        "2 pieces of Government Issued ID",
        "VOID cheque or PAD",
        "2 years personal tax returns (T1 generals)",
        "Corporate structure / org chart",
        "Business plan / projections",
        "Lease agreement (if applicable)",
        "Other",
    ]

    /// multipart/form-data body for POST /api/documents/upload.
    nonisolated static func multipartBody(applicationId: String, category: String, file: SharedFile, fileData: Data, boundary: String) -> Data {
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("applicationId", applicationId)
        field("category", category)
        let safeName = file.name.replacingOccurrences(of: "\"", with: "")
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\nContent-Type: \(file.mimeType)\r\n\r\n".utf8))
        body.append(fileData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }
}
