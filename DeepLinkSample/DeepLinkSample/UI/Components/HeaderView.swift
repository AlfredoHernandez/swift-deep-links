//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import SwiftUI

/// A reusable header component that displays the app title and description.
///
/// This component provides a consistent header design across the app with:
/// - A prominent link icon to represent deep linking functionality
/// - The app title with bold typography
/// - A descriptive subtitle explaining the app's purpose
///
/// The header uses a vertical stack layout with consistent spacing and follows
/// the app's design system with blue accent colors.
struct HeaderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Deep Link Sample App")
                .font(.title)
                .fontWeight(.bold)

            Text("Test different types of deep links")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top)
    }
}

#Preview {
    HeaderView()
        .padding()
}
