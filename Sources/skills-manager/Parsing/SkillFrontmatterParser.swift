import Foundation
import Parsing

internal struct SkillFrontmatterParser: Parser {
	internal func parse(
		_ input: inout Substring
	) throws -> [String: String] {
		let lines = try Self.linesParser.parse(&input)
		var isParsingMetadata = false
		var properties: [String: String] = [:]

		for line in lines {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
				continue
			}

			var lineInput = line
			let entry: SkillFrontmatterLine
			do {
				entry = try SkillFrontmatterLineParser().parse(&lineInput)
			} catch {
				throw SkillDocumentFormatError.invalidLine(String(line))
			}

			guard !entry.key.isEmpty else {
				throw SkillDocumentFormatError.emptyKey
			}

			if entry.indentation == 0 {
				isParsingMetadata = entry.key == "metadata"
					&& entry.value.isEmpty
				if isParsingMetadata {
					continue
				}

				guard !entry.value.isEmpty else {
					throw SkillDocumentFormatError.missingValue(entry.key)
				}

				properties[entry.key] = try SkillFrontmatterScalarParser()
					.parse(entry.value)

			} else {
				guard isParsingMetadata else {
					throw SkillDocumentFormatError.unsupportedNestedKey(entry.key)
				}

				guard !entry.value.isEmpty else {
					throw SkillDocumentFormatError.missingValue(entry.key)
				}

				properties["metadata.\(entry.key)"] =
					try SkillFrontmatterScalarParser().parse(entry.value)
			}
		}

		return properties
	}

	private static var linesParser: some Parser<
		Substring,
		[Substring]
	> {
		Many {
			Prefix<Substring> { !$0.isNewline }
		} separator: {
			"\n"
		}
	}
}

private struct SkillFrontmatterLine {
	internal var indentation: Int
	internal var key: String
	internal var value: Substring

	internal init(
		indentation: Int,
		key: String,
		value: Substring
	) {
		self.indentation = indentation
		self.key = key
		self.value = value
	}
}

private struct SkillFrontmatterLineParser: Parser {
	internal var body: some Parser<Substring, SkillFrontmatterLine> {
		Parse(input: Substring.self) {
			Prefix { $0 == " " }
			Prefix(1...) { $0 != ":" && !$0.isNewline }
			":"
			Prefix { $0 == " " || $0 == "\t" }
			Prefix { _ in true }
		}
		.map { output in
			SkillFrontmatterLine(
				indentation: output.0.count,
				key: output.1.trimmingCharacters(in: .whitespaces),
				value: output.3
			)
		}
	}
}

private struct SkillFrontmatterScalarParser {
	internal func parse(_ input: Substring) throws -> String {
		let scalar = input.trimmingCharacters(in: .whitespaces)
		guard scalar.count >= 2 else {
			return scalar
		}

		if scalar.first == "\"", scalar.last == "\"" {
			do {
				return try JSONDecoder().decode(
					String.self,
					from: Data(scalar.utf8)
				)
			} catch {
				throw SkillDocumentFormatError.invalidQuotedScalar(scalar)
			}
		}

		if scalar.first == "'", scalar.last == "'" {
			return String(scalar.dropFirst().dropLast())
				.replacingOccurrences(
					of: "''",
					with: "'"
				)
		}

		return scalar
	}
}
