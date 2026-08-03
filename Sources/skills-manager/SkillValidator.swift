internal enum SkillValidator {
	internal static func validate(_ skill: Skill) throws {
		try validateName(skill.name)
		try validateAttachments(
			skill.attachments,
			isSkillRoot: true
		)
	}

	internal static func validateName(_ name: String) throws {
		let hasValidCharacters = name.allSatisfy {
			$0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-")
		}
		guard
			(1...64).contains(name.count),
			name.first != "-",
			name.last != "-",
			!name.contains("--"),
			hasValidCharacters
		else {
			throw SkillsManagerError.invalidSkillName(name)
		}
	}

	private static func validateAttachments(
		_ attachments: [Skill.Attachment],
		isSkillRoot: Bool
	) throws {
		var names: Set<String> = []
		for attachment in attachments {
			let name = attachment.name
			guard
				!name.isEmpty,
				name != ".",
				name != "..",
				!name.contains("/"),
				!name.contains("\\"),
				!(isSkillRoot && name == "SKILL.md"),
				names.insert(name).inserted
			else {
				throw SkillsManagerError.invalidAttachmentName(name)
			}

			if case let .group(contents) = attachment.content {
				try validateAttachments(
					contents,
					isSkillRoot: false
				)
			}
		}
	}
}
