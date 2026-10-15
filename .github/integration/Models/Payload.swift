// Created by yuxilong on 2026/10/15.
import Foundation
import ReerCodable

@Codable
struct Payload {
    var enabled: Bool
    var count: Int
}

@Codable
struct Channel {
    var channel = "relay"
    var enabled = false
}
