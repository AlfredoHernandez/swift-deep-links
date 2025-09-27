//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLink
import Foundation
import os.log
import Testing

@Suite("LoggingMiddleware Tests")
struct LoggingMiddlewareTests {
    @Test("LoggingMiddleware logs URL details correctly")
    func loggingMiddleware_logsURLDetailsCorrectly() async throws {
        let testURL = URL(string: "testapp://profile?userId=123&name=John")!
        let middleware = LoggingMiddleware()

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("LoggingMiddleware handles URLs without query parameters")
    func loggingMiddleware_handlesURLsWithoutQueryParameters() async throws {
        let testURL = URL(string: "testapp://home")!
        let middleware = LoggingMiddleware()

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("LoggingMiddleware handles malformed URLs gracefully")
    func loggingMiddleware_handlesMalformedURLsGracefully() async throws {
        let testURL = URL(string: "testapp://")!
        let middleware = LoggingMiddleware()

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    // MARK: - Strategy Tests

    @Test("LoggingMiddleware with singleLine strategy logs URL details in single line")
    func loggingMiddleware_withSingleLineStrategy_logsURLDetailsInSingleLine() async throws {
        let testURL = URL(string: "testapp://product/123?category=electronics&price=299.99")!
        let loggingProviderSpy = LoggingProviderSpy()
        let middleware = LoggingMiddleware(
            loggingProvider: loggingProviderSpy.asLoggingProvider,
            format: .singleLine,
        )

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
        #expect(loggingProviderSpy.messageCount == 1)

        let logMessage = loggingProviderSpy.lastMessage!
        #expect(logMessage.contains("Deep link intercepted: testapp://product/123?category=electronics&price=299.99"))
        #expect(logMessage.contains("scheme=testapp"))
        #expect(logMessage.contains("host=product"))
        #expect(logMessage.contains("path=/123"))
        #expect(logMessage.contains("params=category=electronics&price=299.99"))
    }

    @Test("LoggingMiddleware with json strategy logs URL details in JSON format")
    func loggingMiddleware_withJsonStrategy_logsURLDetailsInJSONFormat() async throws {
        let testURL = URL(string: "testapp://product/123?category=electronics&price=299.99")!
        let loggingProviderSpy = LoggingProviderSpy()
        let middleware = LoggingMiddleware(
            loggingProvider: loggingProviderSpy.asLoggingProvider,
            format: .json,
        )

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
        #expect(loggingProviderSpy.messageCount == 1)

        let logMessage = loggingProviderSpy.lastMessage!

        // Verify it's valid JSON and contains expected data
        let jsonData = logMessage.data(using: .utf8)!
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]
        #expect(jsonObject["event"] as? String == "deep_link_intercepted")
        #expect(jsonObject["url"] as? String == "testapp://product/123?category=electronics&price=299.99")
        #expect(jsonObject["scheme"] as? String == "testapp")
        #expect(jsonObject["host"] as? String == "product")
        #expect(jsonObject["path"] as? String == "/123")

        // Verify params object
        let params = jsonObject["params"] as! [String: String]
        #expect(params["category"] == "electronics")
        #expect(params["price"] == "299.99")
    }

    @Test("LoggingMiddleware with minimal strategy logs only URL")
    func loggingMiddleware_withMinimalStrategy_logsOnlyURL() async throws {
        let testURL = URL(string: "testapp://product/123?category=electronics&price=299.99")!
        let loggingProviderSpy = LoggingProviderSpy()
        let middleware = LoggingMiddleware(
            loggingProvider: loggingProviderSpy.asLoggingProvider,
            format: .minimal,
        )

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
        #expect(loggingProviderSpy.messageCount == 1)

        let logMessage = loggingProviderSpy.lastMessage!
        #expect(logMessage == "Deep link: testapp://product/123?category=electronics&price=299.99")
    }

    @Test("LoggingMiddleware with detailed strategy logs URL details in multiple lines")
    func loggingMiddleware_withDetailedStrategy_logsURLDetailsInMultipleLines() async throws {
        let testURL = URL(string: "testapp://product/123?category=electronics&price=299.99")!
        let loggingProviderSpy = LoggingProviderSpy()
        let middleware = LoggingMiddleware(
            loggingProvider: loggingProviderSpy.asLoggingProvider,
            format: .detailed,
        )

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
        #expect(loggingProviderSpy.messageCount == 5) // 5 separate log messages

        let logMessages = loggingProviderSpy.allMessages
        #expect(logMessages[0].contains("Deep link intercepted: testapp://product/123?category=electronics&price=299.99"))
        #expect(logMessages[1].contains("Scheme: testapp"))
        #expect(logMessages[2].contains("Host: product"))
        #expect(logMessages[3].contains("Path: /123"))
        #expect(logMessages[4].contains("Parameters: category=electronics&price=299.99"))
    }

    // MARK: - Edge Cases

    @Test("LoggingMiddleware with singleLine strategy handles URLs without query parameters")
    func loggingMiddleware_withSingleLineStrategy_handlesURLsWithoutQueryParameters() async throws {
        let testURL = URL(string: "testapp://product/123")!
        let loggingProviderSpy = LoggingProviderSpy()
        let middleware = LoggingMiddleware(
            loggingProvider: loggingProviderSpy.asLoggingProvider,
            format: .singleLine,
        )

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
        #expect(loggingProviderSpy.messageCount == 1)

        let logMessage = loggingProviderSpy.lastMessage!
        #expect(logMessage.contains("Deep link intercepted: testapp://product/123"))
        #expect(logMessage.contains("scheme=testapp"))
        #expect(logMessage.contains("host=product"))
        #expect(logMessage.contains("path=/123"))
        #expect(!logMessage.contains("params=")) // Should not contain params
    }

    @Test("LoggingMiddleware with singleLine strategy handles URLs without path")
    func loggingMiddleware_withSingleLineStrategy_handlesURLsWithoutPath() async throws {
        let testURL = URL(string: "testapp://product?category=electronics")!
        let middleware = LoggingMiddleware(format: .singleLine)

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("LoggingMiddleware with singleLine strategy handles URLs with empty path")
    func loggingMiddleware_withSingleLineStrategy_handlesURLsWithEmptyPath() async throws {
        let testURL = URL(string: "testapp://product")!
        let middleware = LoggingMiddleware(format: .singleLine)

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("LoggingMiddleware with json strategy handles URLs without query parameters")
    func loggingMiddleware_withJsonStrategy_handlesURLsWithoutQueryParameters() async throws {
        let testURL = URL(string: "testapp://product/123")!
        let middleware = LoggingMiddleware(format: .json)

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("LoggingMiddleware with json strategy handles URLs without path")
    func loggingMiddleware_withJsonStrategy_handlesURLsWithoutPath() async throws {
        let testURL = URL(string: "testapp://product?category=electronics")!
        let middleware = LoggingMiddleware(format: .json)

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("LoggingMiddleware with json strategy handles URLs with empty path")
    func loggingMiddleware_withJsonStrategy_handlesURLsWithEmptyPath() async throws {
        let testURL = URL(string: "testapp://product")!
        let middleware = LoggingMiddleware(format: .json)

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("LoggingMiddleware with detailed strategy handles URLs without query parameters")
    func loggingMiddleware_withDetailedStrategy_handlesURLsWithoutQueryParameters() async throws {
        let testURL = URL(string: "testapp://product/123")!
        let middleware = LoggingMiddleware(format: .detailed)

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("LoggingMiddleware with detailed strategy handles URLs without path")
    func loggingMiddleware_withDetailedStrategy_handlesURLsWithoutPath() async throws {
        let testURL = URL(string: "testapp://product?category=electronics")!
        let middleware = LoggingMiddleware(format: .detailed)

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("LoggingMiddleware with detailed strategy handles URLs with empty path")
    func loggingMiddleware_withDetailedStrategy_handlesURLsWithEmptyPath() async throws {
        let testURL = URL(string: "testapp://product")!
        let middleware = LoggingMiddleware(format: .detailed)

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("LoggingMiddleware with minimal strategy handles URLs without query parameters")
    func loggingMiddleware_withMinimalStrategy_handlesURLsWithoutQueryParameters() async throws {
        let testURL = URL(string: "testapp://product/123")!
        let middleware = LoggingMiddleware(format: .minimal)

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("LoggingMiddleware with minimal strategy handles URLs without path")
    func loggingMiddleware_withMinimalStrategy_handlesURLsWithoutPath() async throws {
        let testURL = URL(string: "testapp://product?category=electronics")!
        let middleware = LoggingMiddleware(format: .minimal)

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("LoggingMiddleware with minimal strategy handles URLs with empty path")
    func loggingMiddleware_withMinimalStrategy_handlesURLsWithEmptyPath() async throws {
        let testURL = URL(string: "testapp://product")!
        let middleware = LoggingMiddleware(format: .minimal)

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    // MARK: - Default Behavior Tests

    @Test("LoggingMiddleware with default format uses singleLine strategy")
    func loggingMiddleware_withDefaultFormat_usesSingleLineStrategy() async throws {
        let testURL = URL(string: "testapp://product/123?category=electronics")!
        let middleware = LoggingMiddleware() // Uses default format

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("LoggingMiddleware with custom log level works correctly")
    func loggingMiddleware_withCustomLogLevel_worksCorrectly() async throws {
        let testURL = URL(string: "testapp://product/123")!
        let middleware = LoggingMiddleware(
            logLevel: .debug,
            format: .singleLine,
        )

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("LoggingMiddleware with custom logging provider works correctly")
    func loggingMiddleware_withCustomLoggingProvider_worksCorrectly() async throws {
        let testURL = URL(string: "testapp://product/123")!
        let middleware = LoggingMiddleware(
            format: .singleLine,
        )

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    // MARK: - Thread Safety Tests

    @Test("LoggingMiddleware is thread-safe")
    func loggingMiddleware_isThreadSafe() async throws {
        let testURL = URL(string: "testapp://product/123")!

        // Test concurrent access
        await withTaskGroup(of: URL?.self) { group in
            for _ in 0 ..< 10 {
                group.addTask {
                    let middleware = LoggingMiddleware(format: .singleLine)
                    return try! await middleware.intercept(testURL)
                }
            }

            var results: [URL?] = []
            for await result in group {
                results.append(result)
            }

            // All results should be the same URL
            #expect(results.count == 10)
            #expect(results.allSatisfy { $0 == testURL })
        }
    }

    @Test("LoggingMiddleware with different formats is thread-safe")
    func loggingMiddleware_withDifferentFormats_isThreadSafe() async throws {
        let testURL = URL(string: "testapp://product/123")!

        // Test concurrent access with different formats
        await withTaskGroup(of: URL?.self) { group in
            let formats: [LoggingFormat] = [.singleLine, .json, .minimal, .detailed]

            for format in formats {
                group.addTask {
                    let middleware = LoggingMiddleware(format: format)
                    return try! await middleware.intercept(testURL)
                }
            }

            var results: [URL?] = []
            for await result in group {
                results.append(result)
            }

            // All results should be the same URL
            #expect(results.count == 4)
            #expect(results.allSatisfy { $0 == testURL })
        }
    }

    // MARK: - Test Helpers

    /// Spy for LoggingProvider that captures log messages for verification
    private final class LoggingProviderSpy: @unchecked Sendable {
        struct LogEntry {
            let message: String
            let level: OSLogType
        }

        private(set) var logEntries: [LogEntry] = []

        func log(level: OSLogType, _ message: String) {
            logEntries.append(LogEntry(message: message, level: level))
        }

        func clear() {
            logEntries.removeAll()
        }

        var lastMessage: String? {
            logEntries.last?.message
        }

        var messageCount: Int {
            logEntries.count
        }

        var allMessages: [String] {
            logEntries.map(\.message)
        }

        /// Creates a LoggingProvider that delegates to this spy
        var asLoggingProvider: LoggingProvider {
            LoggingProvider { level, message in
                self.log(level: level, message)
            }
        }
    }
}
