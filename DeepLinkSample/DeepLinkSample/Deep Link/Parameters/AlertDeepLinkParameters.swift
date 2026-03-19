//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

nonisolated struct AlertDeepLinkParameters: Decodable, Sendable {
	let title: String
	let message: String
	let type: String
}
