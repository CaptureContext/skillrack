import Foundation

public struct RegistryVerificationReport: Equatable, Sendable {
	public let issues: [Issue]

	public init(issues: [Issue]) {
		self.issues = issues
	}

	public var isValid: Bool { issues.isEmpty }
}

extension RegistryVerificationReport {
	public enum Issue: Equatable, Sendable {
		case missingContent(RegistrySkill.ID)
		case digestMismatch(RegistrySkill.ID)
		case missingDependency(RegistrySkill.ID, RegistrySkill.ID)
		case brokenDependencyLink(RegistrySkill.ID, String)
		case brokenToolLink(RegistrySkill.ID, SkillLink)
	}
}
