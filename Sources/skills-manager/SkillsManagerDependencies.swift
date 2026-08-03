import Dependencies
import Foundation

extension DependencyValues {
	private enum SkillsDirectoryURLKey: DependencyKey {
		internal static var liveValue: URL {
			.homeDirectory.appending(component: ".skills")
		}
	}

	/// The central directory where managed skills are stored.
	public var skillsDirectoryURL: URL {
		get { self[SkillsDirectoryURLKey.self] }
		set { self[SkillsDirectoryURLKey.self] = newValue }
	}

	private enum SkillSourceLoadersKey: DependencyKey {
		internal static var liveValue: [any SkillSourceLoaderProtocol] {
			[
				LocalSkillSourceLoader(),
				GitHubSkillSourceLoader(),
			]
		}
	}

	/// Ordered skill sources. Higher-priority loaders are attempted first.
	public var skillSourceLoaders: [any SkillSourceLoaderProtocol] {
		get { self[SkillSourceLoadersKey.self] }
		set { self[SkillSourceLoadersKey.self] = newValue }
	}
}
