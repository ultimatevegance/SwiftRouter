import Foundation
import Testing
@testable import SwiftRouter

struct RouteParametersTests {
    @Test func typedAccessorsConvert() throws {
        let uuid = UUID()
        let parameters = RouteParameters(pathValues: [
            "id": "42", "lat": "1.5", "flag": "TRUE", "token": uuid.uuidString, "slug": "hello",
        ])
        #expect(try parameters.int("id") == 42)
        #expect(try parameters.double("lat") == 1.5)
        #expect(try parameters.bool("flag") == true)
        #expect(try parameters.uuid("token") == uuid)
        #expect(try parameters.string("slug") == "hello")
    }

    @Test func missingParameterThrows() {
        let parameters = RouteParameters()
        #expect(throws: RouterError.parameterMissing(name: "id")) { try parameters.int("id") }
    }

    @Test func typeMismatchThrows() {
        let parameters = RouteParameters(pathValues: ["id": "abc"])
        #expect(throws: RouterError.parameterTypeMismatch(name: "id", expected: "Int", actual: "abc")) {
            try parameters.int("id")
        }
    }

    @Test func pathWinsOverQueryOnCollision() throws {
        let parameters = RouteParameters(pathValues: ["id": "7"], queryValues: ["id": "9", "ref": "email"])
        #expect(try parameters.int("id") == 7)
        #expect(parameters.stringIfPresent("ref") == "email")
    }

    @Test func ifPresentReturnsNilOnMissingOrMismatch() {
        let parameters = RouteParameters(pathValues: ["id": "abc"])
        #expect(parameters.intIfPresent("missing") == nil)
        #expect(parameters.intIfPresent("id") == nil)
        #expect(parameters.stringIfPresent("id") == "abc")
        #expect(parameters.boolIfPresent("id") == nil)
        #expect(parameters.doubleIfPresent("id") == nil)
        #expect(parameters.uuidIfPresent("id") == nil)
    }
}
