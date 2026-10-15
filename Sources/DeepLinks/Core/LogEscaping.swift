//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

/// Keeps attacker-controlled text on one log line.
///
/// Decoded URL parts and error text can carry `%0A`, `%0D` or terminal escape
/// sequences that would forge extra log lines or recolor a terminal, so
/// control, invisible-format and line/paragraph separator characters are
/// written as escapes: `\n`, `\r`, `\t`, or `\u{HEX}`.
enum LogEscaping {
	static func singleLine(_ text: String) -> String {
		guard text.unicodeScalars.contains(where: URLText.isInvisible) else { return text }
		var escaped = ""
		for scalar in text.unicodeScalars {
			guard URLText.isInvisible(scalar) else {
				escaped.unicodeScalars.append(scalar)
				continue
			}
			switch scalar {
			case "\n": escaped += "\\n"
			case "\r": escaped += "\\r"
			case "\t": escaped += "\\t"
			default: escaped += "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
			}
		}
		return escaped
	}
}
