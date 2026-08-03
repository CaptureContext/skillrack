import Foundation
import Dependencies
import DependenciesMacros

@DependencyClient
public struct SkillsManager: Sendable {
	/// Detects local skills and their nested/symlinked dependency relationships.
	public var detectSkills: @Sendable (_ in: URL) async throws -> DetectedSkills

	/// Lists skills in specified url
	///
	/// Supports file urls and GitHub repos
	public var listSkills: @Sendable (
		_ in: URL,
		_ recursively: Bool
	) async throws -> [Skill.Descriptor]

	/// Loads a skill into memory
	///
	/// Supported descriptor urls are:
	/// - fileURL
	/// - GitHub repoURL
	public var loadSkill: @Sendable (_: Skill.Descriptor) async throws -> Skill

	/// Saves a skill to a shared skills directory
	public var saveSkill: @Sendable (
		_: Skill,
		_ to: URL
	) async throws -> [Skill.Descriptor]

	/// Deletes a skill with all subfolders
	public var deleteSkill: @Sendable (_: Skill.Descriptor) async throws -> Void

	/// Moves a skill with all subfolders to a specified directory
	public var moveSkill: @Sendable (
		_: Skill.Descriptor,
		_ to: URL
	) async throws -> Void

	/// Creates a symlink for a skill in a shared skills directory for specified tool
	public var installSkill: @Sendable (_: Skill, _ for: Tool) async throws -> Void

	/// Removes an installed skill for the specified tool
	public var uninstallSkill: @Sendable (_: Skill, _ for: Tool) async throws -> Void
}

extension SkillsManager {
	public static var live: Self {
		let service = SkillsManagerService()

		return Self(
			detectSkills: { url in
				try await service.detectSkills(in: url)
			},
			listSkills: { url, recursively in
				try await service.listSkills(
					in: url,
					recursively: recursively
				)
			},
			loadSkill: { descriptor in
				try await service.loadSkill(descriptor)
			},
			saveSkill: { skill, directoryURL in
				try await service.saveSkill(
					skill,
					to: directoryURL
				)
			},
			deleteSkill: { descriptor in
				try await service.deleteSkill(descriptor)
			},
			moveSkill: { descriptor, directoryURL in
				try await service.moveSkill(
					descriptor,
					to: directoryURL
				)
			},
			installSkill: { skill, tool in
				try await service.installSkill(
					skill,
					for: tool
				)
			},
			uninstallSkill: { skill, tool in
				try await service.uninstallSkill(
					skill,
					for: tool
				)
			}
		)
	}
}

extension DependencyValues {
	private enum SkillsManagerKey: DependencyKey {
		internal static var liveValue: SkillsManager { .live }

		internal static var testValue: SkillsManager { liveValue }
	}

	public var skillsManager: SkillsManager {
		get { self[SkillsManagerKey.self] }
		set { self[SkillsManagerKey.self] = newValue }
	}
}
