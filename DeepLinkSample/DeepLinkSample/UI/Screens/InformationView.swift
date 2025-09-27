//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import SwiftUI

struct InformationView: View {
    @Environment(\.dismiss) var onDismiss
    let infoTitle: String
    let infoBrief: String

    var body: some View {
        VStack(spacing: 20) {
            if !infoTitle.isEmpty {
                Text(infoTitle)
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
            }

            if !infoBrief.isEmpty {
                Text(infoBrief)
                    .font(.body)
                    .multilineTextAlignment(.center)
            }

            if infoTitle.isEmpty, infoBrief.isEmpty {
                Text("Info")
                    .font(.title)
            }

            Button("Close Sheet") {
                onDismiss()
            }
            .padding()
        }
        .padding()
    }
}

#Preview {
    InformationView(infoTitle: "This is a title", infoBrief: "This is a brief description")
}
