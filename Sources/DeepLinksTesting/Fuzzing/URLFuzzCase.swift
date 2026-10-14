//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// One hostile URL from ``URLFuzzCorpus``.
public struct URLFuzzCase: Sendable, Hashable, CustomStringConvertible {
	/// The family of attack a case belongs to.
	public enum Category: String, Sendable, CaseIterable {
		/// `..` segments in raw, percent-encoded and double-encoded forms.
		case traversal

		/// Overlong or invalid UTF-8 and percent-encoding nested past the decoding limit.
		case encoding

		/// NUL, CR/LF, DEL, encoded newlines and invisible Unicode format or
		/// separator characters (bidi overrides, zero-width space, BOM, U+2028).
		case controlCharacters

		/// Userinfo credentials, `trusted@evil` hosts and trailing-dot hosts.
		case hostConfusion

		/// Lookalike (homograph) hosts in Unicode and punycode form.
		case internationalizedHost

		/// Repeated query keys, including valueless and percent-encoded ones.
		case duplicateParameters

		/// URLs, parameter counts and values beyond ``DeepLinks/DeepLinkInputLimits/recommended``.
		case oversize

		/// Schemes no deep link should accept (`javascript:`, `data:`, `file:`).
		case scheme
	}

	/// The attack family.
	public let category: Category

	/// A short, unique name within the category.
	public let name: String

	/// The hostile URL.
	public let url: URL

	public var description: String {
		"\(category.rawValue): \(name)"
	}
}
