//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import SwiftUI

struct ProductView: View {
    @Environment(\.dismiss) var onDismiss
    let productID: String
    let category: String?

    var body: some View {
        VStack(spacing: 20) {
            // Product Image Placeholder
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .frame(height: 200)
                .overlay {
                    VStack {
                        Image(systemName: "photo")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("Product Image")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }

            VStack(spacing: 8) {
                Text("Product #\(productID)")
                    .font(.title2)
                    .fontWeight(.semibold)

                if let category {
                    Text("Category: \(category)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    Button("Buy") {
                        // Simulate purchase
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)

                    Button("Add to Cart") {
                        // Simulate adding to cart
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }

                Button("View Details") {
                    // Simulate viewing details
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }

            Spacer()

            Button("Close") {
                onDismiss()
            }
            .foregroundColor(.secondary)
        }
        .padding()
        .navigationTitle("Product")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationView {
        ProductView(productID: "PROD-001", category: "Electronics")
    }
}
