import XCTest
@testable import BogeyCore

final class StoreTests: XCTestCase {
    func testRoundTripAndPhotos() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bogey-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = try Store(folder: dir)
        try s.set("players", id: "abc123", json: #"{"name":"Marcel","hcp":18.4,"hidden":false}"#)
        try s.set("rounds", id: "r1", json: #"{"date":"2026-11-15","entries":[]}"#)
        try s.delete("rounds", id: "r1")
        XCTAssertThrowsError(try s.set("players", id: "../x", json: "{}"))

        let again = try Store(folder: dir)
        let json = try again.allJSON()
        XCTAssertTrue(json.contains(#""hidden":false"#))
        XCTAssertEqual(again.documents("rounds").count, 0)

        let id = try again.addPhoto(Data([0xFF, 0xD8, 0xFF]), type: "image/jpeg")
        XCTAssertEqual(again.photo(id)?.type, "image/jpeg")
        again.deletePhoto(id)
        XCTAssertNil(again.photo(id))
        XCTAssertNil(again.photo("../daten"))
    }
}
