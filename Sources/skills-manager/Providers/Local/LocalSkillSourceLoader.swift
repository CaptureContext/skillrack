import Dependencies
import Foundation
import FileSystem

public struct LocalSkillSourceLoader: SkillSourceListingProtocol {
	public let priority: Int

	public init(priority: Int = 100) {
		self.priority = priority
	}

	public func listSkills(
		in url: URL,
		recursively: Bool
	) async throws -> [Skill.Descriptor] {
		guard url.isFileURL else {
			throw SkillsManagerError.unsupportedURL(url)
		}

		@Dependency(\.fileSystem)
		var fileSystem

		return try LocalSkillsRepository(fileSystem: fileSystem)
			.listSkills(
				in: url,
				recursively: recursively
			)
	}

	public func loadSkill(from url: URL) async throws -> Skill {
		guard url.isFileURL else {
			throw SkillsManagerError.unsupportedURL(url)
		}

		@Dependency(\.fileSystem)
		var fileSystem

		return try LocalSkillsRepository(fileSystem: fileSystem)
			.loadSkill(from: url)
	}
}
