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

// BOREAL_DIALER_v821 - the quick replies (GET /templates/quick?channel=sms), the same list and order the Watch shows,
// cached for a day. Shown above the full template list in the SMS composers.
@MainActor
final class QuickReplyLibrary: ObservableObject {
    @Published private(set) var replies: [QuickReply] = []
    private let cache = QuickReplyCache()

    func load() async {
        if let cached = cache.load() {
            replies = cached.items
            if cached.fresh && !cached.items.isEmpty { return }
        }
        do {
            let request = try APIClient.shared.makeRequest(path: QuickReplyOrdering.path(channel: "sms"))
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            let items = try JSONDecoder().decode(QuickReplyEnvelope.self, from: data).items
            cache.store(items)
            replies = QuickReplyOrdering.ordered(items)
        } catch {
            // The full template list below still works; the cached quick replies (if any) stay on screen.
            Telemetry.event("quick_replies_load_failed")
        }
    }
}

struct TemplatePickerSheet: View {
    let channel: String
    @Binding var isPresented: Bool
    @Binding var text: String

    @StateObject private var library = TemplateLibrary()
    @StateObject private var quick = QuickReplyLibrary() // BOREAL_DIALER_v821

    var body: some View {
        NavigationStack {
            List {
                // BOREAL_DIALER_v821 - one tap drops a quick reply into the message.
                if channel == "sms" && !quick.replies.isEmpty {
                    Section("Quick replies") {
                        ForEach(quick.replies) { reply in
                            Button {
                                text = insertingTemplate(reply.body, into: text)
                                isPresented = false
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(reply.name).font(.headline)
                                    Text(reply.body)
                                        .font(.caption)
                                        .foregroundColor(Theme.muted)
                                        .lineLimit(2)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
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
        .task { if channel == "sms" { await quick.load() } } // BOREAL_DIALER_v821
    }
}
