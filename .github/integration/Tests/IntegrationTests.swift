// Created by yuxilong on 2026/10/15.
import Foundation
import XCTest

final class IntegrationTests: XCTestCase {
    func testAutomaticConversionWithoutFieldAnnotations() throws {
        let value = try JSONDecoder().decode(Payload.self, from: Data(#"{"enabled":1,"count":"42"}"#.utf8))
        XCTAssertTrue(value.enabled)
        XCTAssertEqual(value.count, 42)
    }

    func testNativeValuesAndEncodingRoundTrip() throws {
        let value = try JSONDecoder().decode(Payload.self, from: Data(#"{"enabled":true,"count":7}"#.utf8))
        let decoded = try JSONDecoder().decode(Payload.self, from: JSONEncoder().encode(value))
        XCTAssertTrue(decoded.enabled)
        XCTAssertEqual(decoded.count, 7)
    }

    func testInferredTypesAndDefaults() throws {
        let empty = try JSONDecoder().decode(Channel.self, from: Data("{}".utf8))
        XCTAssertEqual(empty.channel, "relay")
        XCTAssertFalse(empty.enabled)
        let converted = try JSONDecoder().decode(Channel.self, from: Data(#"{"enabled":1}"#.utf8))
        XCTAssertTrue(converted.enabled)
    }
}
