import Dependencies
import Foundation
import FileSystem

internal struct SkillsManagerService {
	@Dependency(\.skillSourceLoaders)
	private var sourceLoaders

	@Dependency(\.skillsDirectoryURL)
	private var skillsDirectoryURL

	@Dependency(\.fileSystem)
	private var fileSystem

	internal init() {}

	private var orderedSourceLoaders: [any SkillSourceLoaderProtocol] {
		sourceLoaders.enumerated()
			.sorted { lhs, rhs in
				if lhs.element.priority == rhs.element.priority {
					return lhs.offset < rhs.offset
				}
				return lhs.element.priority > rhs.element.priority
			}
			.map(\.element)
	}

	private var localRepository: LocalSkillsRepository {
		.init(fileSystem: fileSystem)
	}

	private var installer: SkillsInstaller {
		.init(
			fileSystem: fileSystem,
			skillsDirectoryURL: skillsDirectoryURL
		)
	}

	internal func detectSkills(in url: URL) async throws -> DetectedSkills {
		try SkillsDetector(fileSystem: fileSystem).detect(in: url)
	}

	internal func listSkills(
		in url: URL,
		recursively: Bool
	) async throws -> [Skill.Descriptor] {
		for loader in orderedSourceLoaders {
			guard let listingLoader = loader as? any SkillSourceListingProtocol
			else { continue }

			do {
				return try await listingLoader.listSkills(
					in: url,
					recursively: recursively
				)
			} catch {
				guard Self.isUnsupportedSource(error)
				else { throw error }
			}
		}

		throw SkillsManagerError.unsupportedURL(url)
	}

	internal func loadSkill(_ descriptor: Skill.Descriptor) async throws -> Skill {
		for loader in orderedSourceLoaders {
			do {
				return try await loader.loadSkill(from: descriptor.url)
			} catch {
				guard Self.isUnsupportedSource(error)
				else { throw error }
			}
		}

		throw SkillsManagerError.unsupportedURL(descriptor.url)
	}

	internal func saveSkill(
		_ skill: Skill,
		to directoryURL: URL
	) async throws -> [Skill.Descriptor] {
		try localRepository.saveSkill(
			skill,
			to: directoryURL
		)
	}

	internal func deleteSkill(_ descriptor: Skill.Descriptor) async throws {
		guard descriptor.url.isFileURL else {
			throw SkillsManagerError.remoteSkillIsReadOnly(descriptor.url)
		}

		try localRepository.deleteSkill(descriptor)
	}

	internal func moveSkill(
		_ descriptor: Skill.Descriptor,
		to directoryURL: URL
	) async throws {
		guard descriptor.url.isFileURL else {
			throw SkillsManagerError.remoteSkillIsReadOnly(descriptor.url)
		}

		try localRepository.moveSkill(
			descriptor,
			to: directoryURL
		)
	}

	internal func installSkill(
		_ skill: Skill,
		for tool: Tool
	) async throws {
		try installer.installSkill(
			skill,
			for: tool
		)
	}

	internal func uninstallSkill(
		_ skill: Skill,
		for tool: Tool
	) async throws {
		try installer.uninstallSkill(
			skill,
			for: tool
		)
	}

	private static func isUnsupportedSource(_ error: Error) -> Bool {
		guard let managerError = error as? SkillsManagerError
		else { return false }

		if case .unsupportedURL = managerError {
			return true
		}
		return false
	}
}
