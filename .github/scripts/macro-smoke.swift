import Foundation
import ReerCodable

@Codable
struct Payload {
    var enabled: Bool
    var count: Int
}

let decoder = JSONDecoder()
let converted = try decoder.decode(Payload.self, from: Data(#"{"enabled":1,"count":"42"}"#.utf8))
precondition(converted.enabled && converted.count == 42, "AutoFlexibleType must be enabled")
let native = try decoder.decode(Payload.self, from: Data(#"{"enabled":true,"count":7}"#.utf8))
precondition(native.enabled && native.count == 7)
let roundTrip = try decoder.decode(Payload.self, from: JSONEncoder().encode(converted))
precondition(roundTrip.enabled && roundTrip.count == 42)
print("Distributed macro expansion and AutoFlexibleType passed")
