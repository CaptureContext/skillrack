import Foundation
import SkillsManager

public struct RegistrySkillDraft: Equatable, Sendable {
	public enum Operation: Equatable, Sendable {
		case install
		case update
	}

	public let id: RegistrySkill.ID
	public let skill: Skill
	public let source: SkillSource
	public let dependencies: [RegistrySkill.Dependency]
	public let operation: Operation

	public init(
		id: RegistrySkill.ID,
		skill: Skill,
		source: SkillSource,
		dependencies: [RegistrySkill.Dependency],
		operation: Operation = .install
	) {
		self.id = id
		self.skill = skill
		self.source = source
		self.dependencies = dependencies
		self.operation = operation
	}
}

public struct SkillResolutionPlan: Equatable, Sendable {
	public let roots: [RegistrySkill.ID]
	public let skills: [RegistrySkillDraft]

	public init(
		roots: [RegistrySkill.ID],
		skills: [RegistrySkillDraft]
	) {
		self.roots = roots
		self.skills = skills
	}
}

public enum SkillResolutionOutcome: Equatable, Sendable {
	case resolved(SkillResolutionPlan)
	case aborted
}

public enum SkillResolutionDecision: Equatable, Sendable {
	case install(Skill)
	case update(RegistrySkill.ID, Skill)
	case useExisting(RegistrySkill.ID)
	case abort
}

public enum SkillResolutionStatus: Equatable, Sendable {
	case available
	case alreadyInstalled(RegistrySkill)
	case conflictingSources([RegistrySkill])
}

public struct SkillResolutionContext: Sendable {
	public let skill: DetectedSkill
	public let references: [DetectedSkills.Reference]
	public let decisions: [DetectedSkill.ID: SkillResolutionDecision]

	private let verification: @Sendable () async throws -> SkillResolutionStatus

	internal init(
		skill: DetectedSkill,
		references: [DetectedSkills.Reference],
		decisions: [DetectedSkill.ID: SkillResolutionDecision],
		verification: @escaping @Sendable () async throws -> SkillResolutionStatus
	) {
		self.skill = skill
		self.references = references
		self.decisions = decisions
		self.verification = verification
	}

	public func verify() async throws -> SkillResolutionStatus {
		try await verification()
	}
}
