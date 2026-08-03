import Foundation
import SkillsManager

internal final class ResolutionSession: @unchecked Sendable {
	private let candidates: DetectedSkills
	private let source: SkillSource
	private let storage: RegistryStorage
	private let generateID: @Sendable () -> RegistrySkill.ID
	private let handler:
		@Sendable (
			SkillResolutionContext
		) async throws -> SkillResolutionDecision

	private var decisions: [DetectedSkill.ID: SkillResolutionDecision] = [:]
	private var resolvedIDs: [DetectedSkill.ID: RegistrySkill.ID] = [:]
	private var stack: [DetectedSkill.ID] = []
	private var drafts: [RegistrySkillDraft] = []

	internal init(
		candidates: DetectedSkills,
		source: SkillSource,
		storage: RegistryStorage,
		generateID: @escaping @Sendable () -> RegistrySkill.ID,
		handler:
			@escaping @Sendable (
				SkillResolutionContext
			) async throws -> SkillResolutionDecision
	) {
		self.candidates = candidates
		self.source = source
		self.storage = storage
		self.generateID = generateID
		self.handler = handler
	}

	internal func resolve() async throws -> SkillResolutionOutcome {
		do {
			var rootIDs: [RegistrySkill.ID] = []
			for root in candidates.roots {
				rootIDs.append(try await visit(root))
			}
			return .resolved(
				.init(
					roots: rootIDs,
					skills: drafts
				)
			)
		} catch is ResolutionAborted {
			return .aborted
		}
	}

	private func visit(
		_ candidateID: DetectedSkill.ID
	) async throws -> RegistrySkill.ID {
		if let cycleIndex = stack.firstIndex(of: candidateID) {
			let cycle = stack[cycleIndex...].map(\.rawValue) + [candidateID.rawValue]
			throw SkillsRegistryError.dependencyCycle(cycle)
		}
		if let resolvedID = resolvedIDs[candidateID] {
			return resolvedID
		}
		guard let candidate = candidates.skills[candidateID] else {
			throw SkillsRegistryError.unresolvedDependency(candidateID.rawValue)
		}

		stack.append(candidateID)
		defer { _ = stack.popLast() }

		let candidateSource = try source.appending(
			relativePath: candidate.relativePath
		)
		let incomingReferences = candidates.references.filter {
			$0.dependency == candidateID
		}
		let context = SkillResolutionContext(
			skill: candidate,
			references: incomingReferences,
			decisions: decisions,
			verification: { [storage] in
				let matches = try storage.list().filter {
					$0.source.matches(candidateSource)
				}
				switch matches.count {
				case 0:
					return .available
				case 1:
					return .alreadyInstalled(matches[0])
				default:
					return .conflictingSources(matches)
				}
			}
		)
		let decision = try await handler(context)
		decisions[candidateID] = decision

		switch decision {
		case .abort:
			throw ResolutionAborted()

		case .useExisting(let skillID):
			let existing = try storage.get(skillID)
			guard existing.source.matches(candidateSource) else {
				throw SkillsRegistryError.resolutionDoesNotMatchSource(skillID)
			}

			resolvedIDs[candidateID] = skillID
			return skillID

		case .install(let skill):
			return try await resolveMutation(
				candidateID,
				skill: skill,
				skillID: generateID(),
				source: candidateSource,
				operation: .install
			)

		case .update(let skillID, let skill):
			let existing = try storage.get(skillID)
			guard existing.source.matches(candidateSource) else {
				throw SkillsRegistryError.resolutionDoesNotMatchSource(skillID)
			}

			return try await resolveMutation(
				candidateID,
				skill: skill,
				skillID: skillID,
				source: candidateSource,
				operation: .update
			)
		}
	}

	private func resolveMutation(
		_ candidateID: DetectedSkill.ID,
		skill: Skill,
		skillID: RegistrySkill.ID,
		source: SkillSource,
		operation: RegistrySkillDraft.Operation
	) async throws -> RegistrySkill.ID {
		var dependencies: [RegistrySkill.Dependency] = []
		for reference in candidates.dependencies(of: candidateID) {
			let dependencyID = try await visit(reference.dependency)
			dependencies.append(
				.init(
					skillID: dependencyID,
					path: reference.path,
					kind: reference.kind == .embedded ? .embedded : .mentioned
				)
			)
		}

		resolvedIDs[candidateID] = skillID
		drafts.append(
			.init(
				id: skillID,
				skill: skill,
				source: source,
				dependencies: dependencies,
				operation: operation
			)
		)
		return skillID
	}
}

private struct ResolutionAborted: Error {}
