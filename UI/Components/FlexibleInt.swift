// BOREAL_DIALER_DECODE_AND_ACCENT_v36
// Postgres count(*) is bigint, and node-postgres serialises bigint as a JSON
// string to avoid losing precision past 2^53. So a count arrives as "2" unless
// the query casts it with ::int. One uncast count on one endpoint took out an
// entire tab, silently, behind a generic "could not load" message.
//
// Rather than chase every endpoint, counts are decoded leniently.
import Foundation

enum FlexibleInt {
    static func decode<K: CodingKey>(
        _ container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> Int? {
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let text = try? container.decodeIfPresent(String.self, forKey: key) {
            return Int(text)
        }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        return nil
    }
}
