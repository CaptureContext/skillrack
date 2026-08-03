import Foundation

internal struct SkillFrontmatterPrinter {
	internal func print(_ document: SkillDocument) throws -> String {
		var lines = [
			"name: \(try scalar(document.name))",
		]

		if let description = document.description {
			lines.append("description: \(try scalar(description))")
		}

		let topLevel = document.properties
			.filter { !$0.key.hasPrefix("metadata.") }
			.sorted { $0.key < $1.key }
		for (key, value) in topLevel {
			try validate(key: key)
			lines.append("\(key): \(try scalar(value))")
		}

		let metadata = document.properties
			.compactMap { key, value -> (String, String)? in
				guard key.hasPrefix("metadata.") else {
					return nil
				}
				return (
					String(key.dropFirst("metadata.".count)),
					value
				)
			}
			.sorted { $0.0 < $1.0 }
		if !metadata.isEmpty {
			lines.append("metadata:")
			for (key, value) in metadata {
				try validate(key: key)
				lines.append("  \(key): \(try scalar(value))")
			}
		}

		return lines.joined(separator: "\n")
	}

	private func scalar(_ value: String) throws -> String {
		let plainCharacters = CharacterSet(
			charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_. /()"
		)
		let canUsePlain = !value.isEmpty
		&& value == value.trimmingCharacters(in: .whitespacesAndNewlines)
		&& value.unicodeScalars.allSatisfy(plainCharacters.contains)
		&& !value.contains(": ")
		&& !value.contains(" #")

		if canUsePlain {
			return value
		}

		let data = try JSONEncoder().encode(value)
		return String(
			decoding: data,
			as: UTF8.self
		)
	}

	private func validate(key: String) throws {
		guard
			!key.isEmpty,
			!key.contains(":"),
			!key.contains("\n"),
			!key.contains("\r")
		else {
			throw SkillDocumentFormatError.invalidKey(key)
		}
	}
}
