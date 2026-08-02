// BOREAL_DIALER_MODULE_COMPILES_v4
// The payload shape VoiceEngine.handleIncomingEvent, VoiceService.handleIncoming
// and VoiceService.handleUpdate all read. It was referenced in three places and
// declared in none. Every field is optional because these arrive from push
// payloads and websocket events where nothing is guaranteed.
import Foundation

struct DataContainer: Decodable {
    let id: String?
    let number: String?
    let direction: String?
    let status: String?
    let body: String?
    let timestamp: Date?
}
