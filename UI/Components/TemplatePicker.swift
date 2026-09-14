// BOREAL_DIALER_TEMPLATES_EVERYWHERE_v167
// A reusable snippet/template picker for any composer.
//
// A full native picker already existed, but it was written inline inside
// SMSNewMessageView - the "start a new conversation" screen. So templates were
// reachable only when texting someone for the first time, and never when
// replying in an SMS thread or in Messages, which is where they are actually
// wanted. This lifts the loader and the list out so every composer can present
// the same one.
//
// Reads GET /templates?channel=... - the same endpoint and the same shape the
// portal composer uses, so a snippet added in Settings appears on the phone
// with no extra work.
import SwiftUI

@MainActor
final class TemplateLibrary: ObservableObject {
    @Published private(set) var templates: [SMSTemplate] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?

    private var loadedChannel: String?

    /// Snippets first, then templates, each alphabetical - the order the
    /// original SMS picker used.
    func load(channel: String) async {
        if loadedChannel == channel && !templates.isEmpty { return }
        loading = true
        error = nil
        do {
            let request = try APIClient.shared.makeRequest(path: "/templates?channel=\(channel)")
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            templates = try JSONDecoder().decode(TemplateLibraryEnvelope.self, from: data).templates.sorted {
                if $0.isSnippet != $1.isSnippet { return $0.isSnippet }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            loadedChannel = channel
        } catch {
            self.error = "Could not load templates."
        }
        loading = false
    }
}

struct TemplateLibraryEnvelope: Decodable {
    let templates: [SMSTemplate]

    // BOREAL_DIALER_TEMPLATES_ITEMS_v179
    // GET /api/templates answers { items: [...] } - the shape the portal
    // composer reads. v167 modelled this on /api/watch/sms-templates, which
    // answers { templates: [...] }, so every fetch decoded to nothing and the
    // sheet showed "Could not load templates." Accept "items" first, and keep
    // the other keys so the Watch route and any bare array still decode.
    private enum CodingKeys: String, CodingKey { case items, templates, data }

    init(from decoder: Decoder) throws {
        if let array = try? decoder.singleValueContainer().decode([SMSTemplate].self) {
            templates = array
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let items = try container.decodeIfPresent([SMSTemplate].self, forKey: .items) {
            templates = items
            return
        }
        templates = try container.decodeIfPresent([SMSTemplate].self, forKey: .templates)
            ?? container.decode([SMSTemplate].self, forKey: .data)
    }
}

/// Inserts the chosen body at the caret rather than replacing what was typed.
/// A reply half-written should survive picking a snippet.
func insertingTemplate(_ body: String, into current: String) -> String {
    if current.isEmpty { return body }
    if current.hasSuffix(" ") || current.hasSuffix("\n") { return current + body }
    return current + " " + body
}

struct TemplatePickerSheet: View {
    let channel: String
    @Binding var isPresented: Bool
    @Binding var text: String

    @StateObject private var library = TemplateLibrary()

    var body: some View {
        NavigationStack {
            List {
                if library.loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let error = library.error {
                    Text(error).foregroundColor(Theme.red)
                } else if library.templates.isEmpty {
                    Text("No templates available for this channel.")
                        .foregroundColor(Theme.muted)
                } else {
                    ForEach(library.templates) { template in
                        Button {
                            text = insertingTemplate(template.bodyText, into: text)
                            isPresented = false
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(template.name).font(.headline)
                                    if let shortcut = template.shortcut, !shortcut.isEmpty {
                                        Text("#\(shortcut)")
                                            .font(.caption)
                                            .foregroundColor(Theme.muted)
                                    }
                                    Spacer()
                                    if template.isSnippet {
                                        Text("Snippet")
                                            .font(.caption2)
                                            .foregroundColor(Theme.green)
                                    }
                                }
                                Text(template.bodyText)
                                    .font(.caption)
                                    .foregroundColor(Theme.muted)
                                    .lineLimit(2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
        .task { await library.load(channel: channel) }
    }
}
