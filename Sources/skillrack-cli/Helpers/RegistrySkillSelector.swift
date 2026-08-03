import ArgumentParser
import Foundation
import SkillsRegistryManager

internal func resolveRegistrySkills(
	_ selectors: [String],
	from skills: [RegistrySkill]
) throws -> [RegistrySkill] {
	var result: [RegistrySkill] = []
	var seen: Set<RegistrySkill.ID> = []
	for selector in selectors {
		let skill = try resolveRegistrySkill(
			selector,
			from: skills
		)
		if seen.insert(skill.id).inserted { result.append(skill) }
	}
	return result
}

internal func resolveRegistrySkill(
	_ selector: String,
	from skills: [RegistrySkill]
) throws -> RegistrySkill {
	if let id = RegistrySkill.ID(rawValue: selector) {
		guard let skill = skills.first(where: { $0.id == id }) else {
			throw CLIError(
				code: "skill_not_found",
				message: "Registry skill was not found: \(selector)"
			)
		}

		return skill
	}

	let matches = skills.filter { $0.name == selector }
	guard !matches.isEmpty else {
		throw CLIError(
			code: "skill_not_found",
			message: "Skill was not found: \(selector)"
		)
	}

	guard matches.count == 1 else {
		let ids = matches.map(\.id.rawValue).joined(separator: ", ")
		throw CLIError(
			code: "skill_not_found",
			message: "Skill name '\(selector)' is ambiguous. Matching IDs: \(ids)"
		)
	}

	return matches[0]
}

internal func registrySkillPromptOptions(
	_ skills: [RegistrySkill]
) -> [TerminalPromptOption] {
	skills.map {
		.init(
			value: $0.id.rawValue,
			label: $0.displayName ?? $0.name,
			hint: "\($0.id.rawValue.prefix(8)) · \(sourceDescription($0.source))"
		)
	}
}
