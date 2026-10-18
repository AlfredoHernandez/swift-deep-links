//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import DeepLinks
import Foundation

enum TestRoute: DeepLinkRoute {
	case routeA
	case routeB

	var id: String {
		switch self {
		case .routeA: "routeA"

		case .routeB: "routeB"
		}
	}
}

let testURL = URL(string: "myapp://test")!
let anotherURL = URL(string: "myapp://other")!
