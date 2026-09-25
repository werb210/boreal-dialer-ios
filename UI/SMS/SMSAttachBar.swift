import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

// BOREAL_DIALER_BLOCK_v503_SMS_ATTACH_EVERYWHERE
// The photo/PDF attach row and length/text counter from the SMS thread (v501),
// as one reusable piece so every place that sends a text matches the portal.
enum SMSMediaLoader {
    static let maxBytes = 5 * 1024 * 1024

    static func photo(from data: Data) -> (media: SMSMediaPayload?, error: String?) {
        guard let image = UIImage(data: data) else { return (nil, "Couldn't read that photo.") }
        var jpeg = image.jpegData(compressionQuality: 0.7)
        if let current = jpeg, current.count > maxBytes {
            let scale = 2048.0 / max(image.size.width, image.size.height)
            if scale < 1 {
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                jpeg = resized.jpegData(compressionQuality: 0.6)
            }
        }
        guard let final = jpeg, final.count <= maxBytes else { return (nil, "That photo is too large to text (5 MB limit).") }
        return (SMSMediaPayload(name: "photo.jpg", contentType: "image/jpeg", dataUrl: "data:image/jpeg;base64," + final.base64EncodedString()), nil)
    }

    static func pdf(from url: URL) -> (media: SMSMediaPayload?, error: String?) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return (nil, "Couldn't read that PDF.") }
        guard data.count <= maxBytes else { return (nil, "Files sent by text must be 5 MB or smaller.") }
        return (SMSMediaPayload(name: url.lastPathComponent, contentType: "application/pdf", dataUrl: "data:application/pdf;base64," + data.base64EncodedString()), nil)
    }
}

struct SMSAttachBar: View {
    @Binding var text: String
    @Binding var media: SMSMediaPayload?
    @Binding var error: String?

    @State private var photoItem: PhotosPickerItem?
    @State private var showingPdfImporter = false

    private var textIsEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(spacing: 14) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Photo", systemImage: "photo")
            }
            Button {
                showingPdfImporter = true
            } label: {
                Label("PDF", systemImage: "doc")
            }
            if let media {
                Text(media.name).lineLimit(1).foregroundColor(Theme.green)
                Button {
                    self.media = nil
                    photoItem = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .accessibilityLabel("Remove attachment")
            }
            Spacer()
            if !textIsEmpty {
                Text(SmsSegments.label(text))
                    .foregroundColor(SmsSegments.count(text).segments > 1 ? .orange : Theme.faint)
            }
        }
        .font(.caption)
        .padding(.horizontal)
        .padding(.top, 6)
        .onChange(of: photoItem) { item in
            Task { await loadPhoto(item) }
        }
        .onChange(of: media) { value in
            if value == nil { photoItem = nil }
        }
        .fileImporter(isPresented: $showingPdfImporter, allowedContentTypes: [UTType.pdf]) { result in
            guard case .success(let url) = result else { return }
            let loaded = SMSMediaLoader.pdf(from: url)
            error = loaded.error
            if let m = loaded.media { media = m }
        }
    }

    @MainActor private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            error = "Couldn't read that photo."
            return
        }
        let loaded = SMSMediaLoader.photo(from: data)
        error = loaded.error
        if let m = loaded.media { media = m }
    }
}
