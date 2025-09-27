//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Combine
import DeepLink
import SwiftUI

/// A view that provides a testing interface for custom deep links.
///
/// This view allows developers to:
/// - Enter custom deep link URLs manually
/// - Test the deep link parsing and routing system
/// - Validate URL formats and parameters
/// - See immediate results of deep link processing
///
/// The tester integrates with the complete deep link infrastructure:
/// - Uses all available parsers (Information, Profile, Product, Settings, Alert)
/// - Employs the `DefaultDeepLinkRouting` system
/// - Connects to the `AppDeepLinkHandler` for navigation
/// - Provides error handling and user feedback
///
/// This is particularly useful for:
/// - Testing new deep link formats during development
/// - Debugging parsing issues
/// - Validating URL parameters
/// - Demonstrating the deep link system to stakeholders
struct CustomDeepLinkTesterView: View {
    @EnvironmentObject var navigationRouter: NavigationRouter
    @State private var customDeepLink = ""
    @State private var showingCustomLinkAlert = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Custom Deep Link Tester")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                TextField("Enter a custom deep link", text: $customDeepLink)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                HStack(spacing: 12) {
                    // Process deep link through complete parsing pipeline
                    Button("Test Deep Link") {
                        testCustomDeepLink()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(customDeepLink.isEmpty)

                    Button("Clear") {
                        customDeepLink = ""
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue.opacity(0.3), lineWidth: 1),
            )
        }
        .alert("Deep Link Error", isPresented: $showingCustomLinkAlert) {
            Button("OK") {}
        } message: {
            Text("Could not process the deep link. Please verify the format is correct.")
        }
    }

    /// Tests a custom deep link URL through the complete parsing and routing system.
    ///
    /// This method validates the URL format and processes it through the full deep link
    /// pipeline: parsing → routing → navigation execution. It uses all available parsers
    /// to handle different URL types and provides comprehensive error handling.
    private func testCustomDeepLink() {
        guard let url = URL(string: customDeepLink) else {
            showingCustomLinkAlert = true
            return
        }

        Task {
            let parsers: [any DeepLinkParser<AppRoute>] = [
                InformationParser(),
                ProfileParser(),
                ProductParser(),
                SettingsParser(),
                AlertParser(),
            ]

            let routing = DefaultDeepLinkRouting<AppRoute>(parsers: parsers)
            let handler = AppDeepLinkHandler(navigationRouter: navigationRouter)
            let deepLinkCoordinator = DeepLinkCoordinator(routing: routing, handler: handler)

            await deepLinkCoordinator.handle(url: url)
        }
    }
}

#Preview {
    CustomDeepLinkTesterView()
        .environmentObject(NavigationRouter())
        .padding()
}
