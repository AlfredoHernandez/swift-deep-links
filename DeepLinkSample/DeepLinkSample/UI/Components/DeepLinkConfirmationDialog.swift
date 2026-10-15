//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import SwiftUI

/// Presents the ``ConfirmationPrompter``'s pending prompt as a dialog.
///
/// Only the buttons answer: SwiftUI clears the presentation binding before it
/// runs a button's action, so answering from the binding would deny every
/// link. Tapping outside the dialog runs the cancel button.
struct DeepLinkConfirmationDialog: ViewModifier {
	let prompter: ConfirmationPrompter

	func body(content: Content) -> some View {
		content.confirmationDialog(
			prompter.prompt?.message ?? "",
			isPresented: Binding(get: { prompter.prompt != nil }, set: { _ in }),
			titleVisibility: .visible,
		) {
			Button("Open") { prompter.answer(true) }
			Button("Cancel", role: .cancel) { prompter.answer(false) }
		}
	}
}

extension View {
	func deepLinkConfirmations(_ prompter: ConfirmationPrompter) -> some View {
		modifier(DeepLinkConfirmationDialog(prompter: prompter))
	}
}
