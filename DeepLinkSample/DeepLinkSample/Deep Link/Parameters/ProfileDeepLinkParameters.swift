//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

nonisolated struct ProfileDeepLinkParameters: Decodable, Sendable {
	let userID: String
	let name: String?
}
