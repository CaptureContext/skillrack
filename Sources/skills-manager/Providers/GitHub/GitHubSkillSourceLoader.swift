import Dependencies
import Foundation
import FileSystem

public struct GitHubSkillSourceLoader: SkillSourceListingProtocol {
	public let priority: Int

	public init(priority: Int = 90) {
		self.priority = priority
	}

	public func listSkills(
		in url: URL,
		recursively: Bool
	) async throws -> [Skill.Descriptor] {
		guard let source = GitHubSkillsSource(url: url) else {
			throw SkillsManagerError.unsupportedURL(url)
		}

		@Dependency(\.fileSystem)
		var fileSystem

		return try GitHubSkillsRepository(fileSystem: fileSystem)
			.listSkills(
				in: source,
				recursively: recursively
			)
	}

	public func loadSkill(from url: URL) async throws -> Skill {
		guard let source = GitHubSkillsSource(url: url) else {
			throw SkillsManagerError.unsupportedURL(url)
		}

		@Dependency(\.fileSystem)
		var fileSystem

		return try GitHubSkillsRepository(fileSystem: fileSystem)
			.loadSkill(from: source)
	}
}
