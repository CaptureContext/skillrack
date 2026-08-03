import Foundation

internal struct SkillDocument {
	internal var name: String
	internal var description: String?
	internal var properties: [String: String]
	internal var body: String

	internal init(
		name: String,
		description: String?,
		properties: [String: String],
		body: String
	) {
		self.name = name
		self.description = description
		self.properties = properties
		self.body = body
	}

	internal init(
		data: Data,
		url: URL,
		fallbackName: String? = nil
	) throws {
		guard var source = String(
			data: data,
			encoding: .utf8
		) else {
			throw SkillsManagerError.invalidSkill(
				url,
				reason: "SKILL.md is not valid UTF-8."
			)
		}

		source = source
			.replacingOccurrences(
				of: "\r\n",
				with: "\n"
			)
			.replacingOccurrences(
				of: "\r",
				with: "\n"
			)
		if !source.hasSuffix("\n") {
			source.append("\n")
		}

		var input = source[...]
		self = try SkillDocumentParser(
			url: url,
			fallbackName: fallbackName
		)
		.parse(&input)
	}

	internal init(skill: Skill) {
		self.name = skill.name
		self.description = skill.description
		self.properties = skill.properties
		self.body = skill.body
	}

	internal func data() throws -> Data {
		var output: Substring = ""
		try SkillDocumentParser(
			url: URL(fileURLWithPath: "SKILL.md"),
			fallbackName: nil
		)
		.print(
			self,
			into: &output
		)
		return Data(output.utf8)
	}
}
