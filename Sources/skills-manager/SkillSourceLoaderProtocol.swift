import Foundation

/// Loads skills from a particular URL source.
///
/// Loaders are attempted from highest to lowest priority. A loader that does
/// not support a URL should throw ``SkillsManagerError/unsupportedURL(_:)``.
public protocol SkillSourceLoaderProtocol: Sendable {
	var priority: Int { get }

	func loadSkill(from url: URL) async throws -> Skill
}

/// A source loader that can also discover skills beneath a URL.
public protocol SkillSourceListingProtocol: SkillSourceLoaderProtocol {
	func listSkills(
		in url: URL,
		recursively: Bool
	) async throws -> [Skill.Descriptor]
}
