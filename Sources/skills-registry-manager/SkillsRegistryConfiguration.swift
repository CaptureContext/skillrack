import Dependencies
import Foundation

public struct SkillsRegistryConfiguration: Sendable {
	public let rootURL: URL
	public let homeDirectoryURL: URL

	public init(
		rootURL: URL,
		homeDirectoryURL: URL
	) {
		self.rootURL = rootURL.standardizedFileURL
		self.homeDirectoryURL = homeDirectoryURL.standardizedFileURL
	}

	@inlinable
	public func contentURL(for skillID: RegistrySkill.ID) -> URL {
		rootURL
			.appending(path: "skills", directoryHint: .isDirectory)
			.appending(path: skillID.rawValue, directoryHint: .isDirectory)
			.appending(path: "content", directoryHint: .isDirectory)
	}

	public static func live(fileManager: FileManager = .default) -> Self {
		let environment = ProcessInfo.processInfo.environment
		let applicationSupportURL = fileManager.urls(
			for: .applicationSupportDirectory,
			in: .userDomainMask
		).first
		?? fileManager.homeDirectoryForCurrentUser.appending(
			path: "Library/Application Support",
			directoryHint: .isDirectory
		)

		let defaultRootURL = applicationSupportURL.appending(
			path: "skillrack",
			directoryHint: .isDirectory
		)
		let rootURL = environment["SKILLRACK_ROOT"].flatMap {
			$0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil
		} ?? defaultRootURL
		let homeDirectoryURL = environment["SKILLRACK_HOME"].flatMap {
			$0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil
		} ?? fileManager.homeDirectoryForCurrentUser

		return .init(
			rootURL: rootURL,
			homeDirectoryURL: homeDirectoryURL
		)
	}
}

extension DependencyValues {
	private enum SkillsRegistryConfigurationKey: DependencyKey {
		internal static var liveValue: SkillsRegistryConfiguration { .live() }
		internal static var testValue: SkillsRegistryConfiguration { .live() }
	}

	public var skillsRegistryConfiguration: SkillsRegistryConfiguration {
		get { self[SkillsRegistryConfigurationKey.self] }
		set { self[SkillsRegistryConfigurationKey.self] = newValue }
	}
}
