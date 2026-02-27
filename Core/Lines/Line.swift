import Foundation

struct Line: Identifiable, Codable, Equatable {
    let id: String
    let displayName: String
    let twilioVoiceAppSid: String
    let twilioConversationServiceSid: String
}
