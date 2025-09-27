//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import SwiftUI

/// A view that displays all available deep link examples with copy functionality.
///
/// This view provides a comprehensive showcase of all supported deep link formats:
/// - **Information deep links**: Modal sheet presentations
/// - **Profile deep links**: User profile modal presentations
/// - **Product deep links**: Navigation stack pushes
/// - **Settings deep links**: Navigation stack pushes
/// - **Alert deep links**: Alert presentations
///
/// Each example is displayed in a card format with:
/// - Color-coded indicators for easy identification
/// - Individual copy buttons for each example
/// - A "Copy All" button to copy all examples at once
/// - Visual feedback for copy operations
///
/// This view serves as both documentation and a testing tool for developers
/// to understand the deep link URL formats and test them in external apps.
struct DeepLinkExamplesView: View {
    @State private var showingAllCopiedAlert = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Deep Link Examples")
                    .font(.headline)

                Spacer()

                Button("Copy All") {
                    copyAllExamples()
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }

            // deeplink://info - modal sheet presentation
            DeepLinkExampleCard(
                title: "Information",
                url: "deeplink://info?title=News&brief=News description",
                color: .blue,
            )

            // deeplink://profile - modal sheet with user data
            DeepLinkExampleCard(
                title: "Profile",
                url: "deeplink://profile?userID=123&name=John Doe",
                color: .green,
            )

            // deeplink://product - navigation stack push
            DeepLinkExampleCard(
                title: "Product",
                url: "deeplink://product?productID=PROD-001&category=Electronics",
                color: .orange,
            )

            // deeplink://settings - navigation stack push
            DeepLinkExampleCard(
                title: "Settings",
                url: "deeplink://settings?section=account",
                color: .gray,
            )

            // deeplink://alert - system alert presentation
            DeepLinkExampleCard(
                title: "Alert",
                url: "deeplink://alert?title=Error&message=Something went wrong&type=error",
                color: .red,
            )
        }
        .alert("Examples Copied", isPresented: $showingAllCopiedAlert) {
            Button("OK") {}
        } message: {
            Text("All deep link examples have been copied to the clipboard")
        }
    }

    /// Copies all deep link URL examples to clipboard for external testing.
    ///
    /// This enables batch testing of deep links in external apps by providing
    /// all supported URL formats in a single clipboard operation.
    private func copyAllExamples() {
        let examples = [
            "deeplink://info?title=News&brief=News description",
            "deeplink://profile?userID=123&name=John Doe",
            "deeplink://product?productID=PROD-001&category=Electronics",
            "deeplink://settings?section=account",
            "deeplink://alert?title=Error&message=Something went wrong&type=error",
        ]

        let allExamplesText = examples.joined(separator: "\n\n")
        UIPasteboard.general.string = allExamplesText

        showingAllCopiedAlert = true
    }
}

#Preview {
    DeepLinkExamplesView()
        .padding()
}
