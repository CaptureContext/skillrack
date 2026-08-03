import Dependencies
import Foundation
import SkillsManager

public protocol SkillsRegistryManager: Sendable {
	func list() async throws -> [RegistrySkill]
	func get(_ id: RegistrySkill.ID) async throws -> RegistrySkill
	func verify() async throws -> RegistryVerificationReport

	func resolve(
		_ candidates: DetectedSkills,
		source: SkillSource,
		handler:
			@escaping @Sendable (
				SkillResolutionContext
			) async throws -> SkillResolutionDecision
	) async throws -> SkillResolutionOutcome

	func install(_ draft: RegistrySkillDraft) async throws -> RegistrySkill
	func update(_ draft: RegistrySkillDraft) async throws -> RegistrySkill
	func uninstall(_ id: RegistrySkill.ID) async throws

	func link(
		_ skillID: RegistrySkill.ID,
		to target: LinkTarget,
		alias: String?
	) async throws -> SkillLink

	func unlink(_ link: SkillLink) async throws
}

extension DependencyValues {
	private enum SkillsRegistryManagerKey: DependencyKey {
		internal static var liveValue: any SkillsRegistryManager {
			LiveSkillsRegistryManager()
		}

		internal static var testValue: any SkillsRegistryManager { liveValue }
	}

	public var skillsRegistryManager: any SkillsRegistryManager {
		get { self[SkillsRegistryManagerKey.self] }
		set { self[SkillsRegistryManagerKey.self] = newValue }
	}
}

internal struct LiveSkillsRegistryManager: SkillsRegistryManager {
	@Dependency(\.date.now)
	private var now

	@Dependency(\.skillsManager)
	private var skillsManager

	@Dependency(\.skillsRegistryConfiguration)
	private var configuration

	@Dependency(\.uuid)
	private var uuid

	internal init() {}

	internal func list() async throws -> [RegistrySkill] {
		try storage.list()
	}

	internal func get(_ id: RegistrySkill.ID) async throws -> RegistrySkill {
		try storage.get(id)
	}

	internal func verify() async throws -> RegistryVerificationReport {
		try storage.verify()
	}

	internal func resolve(
		_ candidates: DetectedSkills,
		source: SkillSource,
		handler:
			@escaping @Sendable (
				SkillResolutionContext
			) async throws -> SkillResolutionDecision
	) async throws -> SkillResolutionOutcome {
		try await ResolutionSession(
			candidates: candidates,
			source: source,
			storage: storage,
			generateID: { RegistrySkill.ID(uuid()) },
			handler: handler
		).resolve()
	}

	internal func install(_ draft: RegistrySkillDraft) async throws -> RegistrySkill {
		try await storage.install(
			draft,
			at: now,
			using: skillsManager
		)
	}

	internal func update(_ draft: RegistrySkillDraft) async throws -> RegistrySkill {
		try await storage.update(
			draft,
			at: now,
			using: skillsManager
		)
	}

	internal func uninstall(_ id: RegistrySkill.ID) async throws {
		try storage.uninstall(id)
	}

	internal func link(
		_ skillID: RegistrySkill.ID,
		to target: LinkTarget,
		alias: String?
	) async throws -> SkillLink {
		try storage.link(
			skillID,
			to: target,
			alias: alias,
			at: now
		)
	}

	internal func unlink(_ link: SkillLink) async throws {
		try storage.unlink(
			link,
			at: now
		)
	}

	private var storage: RegistryStorage {
		.init(
			configuration: configuration,
			fileManager: .default
		)
	}
}
