//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

struct JSONQueryParameterParserTests {
	@Test
	func `JSONQueryParameterParser parse returns valid instance with simple parameters`() throws {
		let parser = JSONQueryParameterParser()
		let parameters = ["userID": "123", "name": "John Doe", "isActive": "true"]

		struct SimpleParameters: Decodable {
			let userID: String
			let name: String
			let isActive: String
		}

		let result = try parser.parse(SimpleParameters.self, from: parameters)

		#expect(result.userID == "123")
		#expect(result.name == "John Doe")
		#expect(result.isActive == "true")
	}

	@Test
	func `JSONQueryParameterParser parse returns valid instance with boolean parameters`() throws {
		let parser = JSONQueryParameterParser()
		let parameters = ["isActive": "true", "isPremium": "false", "hasAccess": "1"]

		struct BooleanParameters: Decodable {
			let isActive: String
			let isPremium: String
			let hasAccess: String
		}

		let result = try parser.parse(BooleanParameters.self, from: parameters)

		#expect(result.isActive == "true")
		#expect(result.isPremium == "false")
		#expect(result.hasAccess == "1")
	}

	@Test
	func `JSONQueryParameterParser parse returns valid instance with numeric parameters`() throws {
		let parser = JSONQueryParameterParser()
		let parameters = ["count": "42", "price": "29.99", "rating": "4.5"]

		struct NumericParameters: Decodable {
			let count: String
			let price: String
			let rating: String
		}

		let result = try parser.parse(NumericParameters.self, from: parameters)

		#expect(result.count == "42")
		#expect(result.price == "29.99")
		#expect(result.rating == "4.5")
	}

	@Test
	func `JSONQueryParameterParser parse returns valid instance with URL encoded parameters`() throws {
		let parser = JSONQueryParameterParser()
		let parameters = ["title": "News & Updates", "description": "Latest information about our app", "category": "Technology"]

		struct URLEncodedParameters: Decodable {
			let title: String
			let description: String
			let category: String
		}

		let result = try parser.parse(URLEncodedParameters.self, from: parameters)

		#expect(result.title == "News & Updates")
		#expect(result.description == "Latest information about our app")
		#expect(result.category == "Technology")
	}

	@Test
	func `JSONQueryParameterParser parse returns valid instance with special characters`() throws {
		let parser = JSONQueryParameterParser()
		let parameters = ["symbol": "@#$%", "unicode": "ñáéíóú", "emoji": "🚀📱💻"]

		struct SpecialCharacterParameters: Decodable {
			let symbol: String
			let unicode: String
			let emoji: String
		}

		let result = try parser.parse(SpecialCharacterParameters.self, from: parameters)

		#expect(result.symbol == "@#$%")
		#expect(result.unicode == "ñáéíóú")
		#expect(result.emoji == "🚀📱💻")
	}

	@Test
	func `JSONQueryParameterParser parse returns valid instance with empty parameters`() throws {
		let parser = JSONQueryParameterParser()
		let parameters = ["empty": "", "normal": "value", "spaces": "   "]

		struct EmptyParameters: Decodable {
			let empty: String
			let normal: String
			let spaces: String
		}

		let result = try parser.parse(EmptyParameters.self, from: parameters)

		#expect(result.empty == "")
		#expect(result.normal == "value")
		#expect(result.spaces == "   ")
	}

	@Test
	func `JSONQueryParameterParser parse returns valid instance with single parameter`() throws {
		let parser = JSONQueryParameterParser()
		let parameters = ["userID": "123"]

		struct SingleParameter: Decodable {
			let userID: String
		}

		let result = try parser.parse(SingleParameter.self, from: parameters)

		#expect(result.userID == "123")
	}

	@Test
	func `JSONQueryParameterParser parse returns valid instance with many parameters`() throws {
		let parser = JSONQueryParameterParser()
		let parameters = [
			"param1": "value1", "param2": "value2", "param3": "value3",
			"param4": "value4", "param5": "value5", "param6": "value6",
			"param7": "value7", "param8": "value8", "param9": "value9",
			"param10": "value10",
		]

		struct ManyParameters: Decodable {
			let param1: String
			let param2: String
			let param3: String
			let param4: String
			let param5: String
			let param6: String
			let param7: String
			let param8: String
			let param9: String
			let param10: String
		}

		let result = try parser.parse(ManyParameters.self, from: parameters)

		#expect(result.param1 == "value1")
		#expect(result.param5 == "value5")
		#expect(result.param10 == "value10")
	}

	@Test
	func `JSONQueryParameterParser parse returns valid instance with custom JSON decoder`() throws {
		let customDecoder = JSONDecoder()
		let parser = JSONQueryParameterParser(jsonDecoder: customDecoder)
		let parameters = ["userID": "123", "fullName": "John Doe"]

		struct CustomParameters: Decodable {
			let userID: String
			let fullName: String
		}

		let result = try parser.parse(CustomParameters.self, from: parameters)

		#expect(result.userID == "123")
		#expect(result.fullName == "John Doe")
	}

	@Test
	func `JSONQueryParameterParser parse returns valid instance with optional parameters`() throws {
		let parser = JSONQueryParameterParser()
		let parameters = ["required": "value", "optional": "present"]

		struct OptionalParameters: Decodable {
			let required: String
			let optional: String?
			let missing: String?
		}

		let result = try parser.parse(OptionalParameters.self, from: parameters)

		#expect(result.required == "value")
		#expect(result.optional == "present")
		#expect(result.missing == nil)
	}

	@Test
	func `JSONQueryParameterParser parse throws error on missing required parameter`() {
		let parser = JSONQueryParameterParser()
		let parameters = ["name": "John"]

		struct RequiredParameters: Decodable {
			let name: String
			let userID: String
		}

		#expect(throws: Error.self) {
			try parser.parse(RequiredParameters.self, from: parameters)
		}
	}

	@Test
	func `JSONQueryParameterParser parse throws error on invalid JSON structure`() {
		let parser = JSONQueryParameterParser()
		let parameters = ["invalid": "value"]

		struct InvalidStructure: Decodable {
			let nested: NestedStructure
		}

		struct NestedStructure: Decodable {
			let value: String
		}

		#expect(throws: Error.self) {
			try parser.parse(InvalidStructure.self, from: parameters)
		}
	}

	@Test
	func `JSONQueryParameterParser parse throws error on empty parameters dictionary`() {
		let parser = JSONQueryParameterParser()
		let parameters: [String: String] = [:]

		struct EmptyParameters: Decodable {
			let required: String
		}

		#expect(throws: Error.self) {
			try parser.parse(EmptyParameters.self, from: parameters)
		}
	}

	@Test
	func `JSONQueryParameterParser parse handles parameters with JSON-like values`() throws {
		let parser = JSONQueryParameterParser()
		let parameters = ["jsonString": "{\"key\":\"value\"}", "arrayString": "[1,2,3]", "booleanString": "true"]

		struct JSONLikeParameters: Decodable {
			let jsonString: String
			let arrayString: String
			let booleanString: String
		}

		let result = try parser.parse(JSONLikeParameters.self, from: parameters)

		#expect(result.jsonString == "{\"key\":\"value\"}")
		#expect(result.arrayString == "[1,2,3]")
		#expect(result.booleanString == "true")
	}

	@Test
	func `JSONQueryParameterParser parse handles parameters with numeric strings`() throws {
		let parser = JSONQueryParameterParser()
		let parameters = ["integer": "42", "float": "3.14", "negative": "-10", "zero": "0"]

		struct NumericStringParameters: Decodable {
			let integer: String
			let float: String
			let negative: String
			let zero: String
		}

		let result = try parser.parse(NumericStringParameters.self, from: parameters)

		#expect(result.integer == "42")
		#expect(result.float == "3.14")
		#expect(result.negative == "-10")
		#expect(result.zero == "0")
	}

	@Test
	func `JSONQueryParameterParser parse handles parameters with whitespace`() throws {
		let parser = JSONQueryParameterParser()
		let parameters = ["leading": "  value", "trailing": "value  ", "both": "  value  ", "tabs": "\tvalue\t"]

		struct WhitespaceParameters: Decodable {
			let leading: String
			let trailing: String
			let both: String
			let tabs: String
		}

		let result = try parser.parse(WhitespaceParameters.self, from: parameters)

		#expect(result.leading == "  value")
		#expect(result.trailing == "value  ")
		#expect(result.both == "  value  ")
		#expect(result.tabs == "\tvalue\t")
	}

	// MARK: - Array Parameters Tests

	@Test
	func `JSONQueryParameterParser parse with fromAll handles array parameters`() throws {
		let parser = JSONQueryParameterParser()
		let parameters = ["tags": ["electronics", "new", "sale"]]

		struct ArrayParameters: Decodable {
			let tags: [String]
		}

		let result = try parser.parse(ArrayParameters.self, fromAll: parameters)

		#expect(result.tags == ["electronics", "new", "sale"])
	}

	@Test
	func `JSONQueryParameterParser parse with fromAll handles single value as string`() throws {
		let parser = JSONQueryParameterParser()
		let parameters = ["category": ["phones"]]

		struct SingleValueParameters: Decodable {
			let category: String
		}

		let result = try parser.parse(SingleValueParameters.self, fromAll: parameters)

		#expect(result.category == "phones")
	}

	@Test
	func `JSONQueryParameterParser parse with fromAll handles mixed array and single values`() throws {
		let parser = JSONQueryParameterParser()
		let parameters = [
			"category": ["phones"],
			"tags": ["electronics", "new", "sale"],
			"brand": ["Apple"],
		]

		struct MixedParameters: Decodable {
			let category: String
			let tags: [String]
			let brand: String
		}

		let result = try parser.parse(MixedParameters.self, fromAll: parameters)

		#expect(result.category == "phones")
		#expect(result.tags == ["electronics", "new", "sale"])
		#expect(result.brand == "Apple")
	}

	@Test
	func `JSONQueryParameterParser parse with fromAll handles optional array parameters`() throws {
		let parser = JSONQueryParameterParser()
		let parameters = [
			"category": ["phones"],
		]

		struct OptionalArrayParameters: Decodable {
			let category: String
			let tags: [String]?
		}

		let result = try parser.parse(OptionalArrayParameters.self, fromAll: parameters)

		#expect(result.category == "phones")
		#expect(result.tags == nil)
	}

	@Test
	func `JSONQueryParameterParser parse with fromAll handles empty array`() throws {
		let parser = JSONQueryParameterParser()
		let parameters = [
			"category": ["phones"],
			"tags": [],
		]

		struct EmptyArrayParameters: Decodable {
			let category: String
			let tags: [String]?
		}

		let result = try parser.parse(EmptyArrayParameters.self, fromAll: parameters)

		#expect(result.category == "phones")
		#expect(result.tags == [])
	}

	@Test
	func `JSONQueryParameterParser parse with fromAll handles URL encoded array values`() throws {
		let parser = JSONQueryParameterParser()
		let parameters = ["tags": ["new arrivals", "best sellers", "on sale"]]

		struct URLEncodedArrayParameters: Decodable {
			let tags: [String]
		}

		let result = try parser.parse(URLEncodedArrayParameters.self, fromAll: parameters)

		#expect(result.tags == ["new arrivals", "best sellers", "on sale"])
	}

	@Test
	func `JSONQueryParameterParser parse with fromAll handles numeric array values`() throws {
		let parser = JSONQueryParameterParser()
		let parameters = ["ids": ["1", "2", "3", "42"]]

		struct NumericArrayParameters: Decodable {
			let ids: [String]
		}

		let result = try parser.parse(NumericArrayParameters.self, fromAll: parameters)

		#expect(result.ids == ["1", "2", "3", "42"])
	}
}
