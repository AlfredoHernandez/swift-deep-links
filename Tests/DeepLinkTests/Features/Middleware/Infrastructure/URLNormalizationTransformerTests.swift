//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLink
import Foundation
import Testing

@Suite("URLNormalizationTransformer Tests")
struct URLNormalizationTransformerTests {
    @Test("URLNormalizationTransformer normalizes URLs correctly")
    func urlNormalizationTransformer_normalizesURLsCorrectly() async throws {
        let testURL = URL(string: "testapp://test//path?param1=value1&param2=&param3=value3")!
        let transformer = URLNormalizationTransformer()

        let result = try await transformer.transform(testURL)

        #expect(result.path == "/path")
        #expect(result.query?.contains("param1=value1") == true)
        #expect(result.query?.contains("param2=") == false) // Empty param removed
        #expect(result.query?.contains("param3=value3") == true)
    }

    @Test("URLNormalizationTransformer handles URLs without query parameters")
    func urlNormalizationTransformer_handlesURLsWithoutQueryParameters() async throws {
        let testURL = URL(string: "testapp://test//path")!
        let transformer = URLNormalizationTransformer()

        let result = try await transformer.transform(testURL)

        #expect(result.path == "/path")
        #expect(result.query == nil)
    }

    @Test("URLNormalizationTransformer handles URLs with empty path")
    func urlNormalizationTransformer_handlesURLsWithEmptyPath() async throws {
        let testURL = URL(string: "testapp://host")!
        let transformer = URLNormalizationTransformer()

        let result = try await transformer.transform(testURL)

        #expect(result.path == "")
        #expect(result.host == "host")
    }
}
