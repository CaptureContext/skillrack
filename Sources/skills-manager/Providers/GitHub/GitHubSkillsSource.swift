import Foundation
import FileSystem

internal struct GitHubSkillsSource {
	internal struct Entry: Decodable {
		internal var path: String
		internal var type: String

		internal init(
			path: String,
			type: String
		) {
			self.path = path
			self.type = type
		}
	}

	internal struct Tree: Decodable {
		internal var tree: [Entry]
		internal var truncated: Bool

		internal init(
			tree: [Entry],
			truncated: Bool
		) {
			self.tree = tree
			self.truncated = truncated
		}
	}

	internal var owner: String
	internal var repository: String
	internal var revision: String
	internal var path: String
	internal var originalURL: URL

	internal init?(url: URL) {
		let components = url.pathComponents.filter { $0 != "/" }
		let host = url.host?.lowercased()

		switch host {
		case "github.com", "www.github.com":
			guard components.count >= 2 else { return nil }
			self.owner = components[0]
			self.repository = components[1].removingSuffix(".git")
			self.originalURL = url

			if components.count == 2 {
				self.revision = "HEAD"
				self.path = ""
				return
			}

			guard
				components.count >= 4,
				components[2] == "tree" || components[2] == "blob"
			else { return nil }

			self.revision = components[3]
			let resourcePath = components.dropFirst(4).joined(separator: "/")
			let isSkillDocument = components[2] == "blob"
			&& resourcePath.lastPathComponent == "SKILL.md"
			if isSkillDocument {
				self.path = resourcePath.deletingLastPathComponent
			} else {
				self.path = resourcePath
			}

		case "raw.githubusercontent.com":
			guard components.count >= 3 else { return nil }
			self.owner = components[0]
			self.repository = components[1].removingSuffix(".git")
			self.revision = components[2]
			let resourcePath = components.dropFirst(3).joined(separator: "/")
			self.path = resourcePath.lastPathComponent == "SKILL.md"
			? resourcePath.deletingLastPathComponent
			: resourcePath
			self.originalURL = url

		default:
			return nil
		}
	}

	internal func entries(
		fileSystem: any FileSystem
	) throws -> [Entry] {
		var components = URLComponents()
		components.scheme = "https"
		components.host = "api.github.com"
		components.path = "/repos/\(owner)/\(repository)/git/trees/\(revision)"
		components.queryItems = [
			.init(
				name: "recursive",
				value: "1"
			),
		]

		guard let url = components.url else {
			throw SkillsManagerError.unsupportedURL(originalURL)
		}

		let data = try fileSystem.data(at: url)
		let tree = try JSONDecoder().decode(
			Tree.self,
			from: data
		)
		guard !tree.truncated else {
			throw SkillsManagerError.truncatedGitHubRepository(originalURL)
		}

		return tree.tree
	}

	internal func data(
		at path: String,
		fileSystem: any FileSystem
	) throws -> Data {
		var components = URLComponents()
		components.scheme = "https"
		components.host = "raw.githubusercontent.com"
		components.path = "/\(owner)/\(repository)/\(revision)/\(path)"

		guard let url = components.url else {
			throw SkillsManagerError.unsupportedURL(originalURL)
		}

		return try fileSystem.data(at: url)
	}

	internal func skillURL(at directoryPath: String) -> URL {
		var components = URLComponents()
		components.scheme = "https"
		components.host = "github.com"
		components.path = "/\(owner)/\(repository)/tree/\(revision)"
		if !directoryPath.isEmpty {
			components.path += "/\(directoryPath)"
		}
		return components.url!
	}
}

private extension String {
	var lastPathComponent: String {
		(self as NSString).lastPathComponent
	}

	var deletingLastPathComponent: String {
		(self as NSString).deletingLastPathComponent
	}

	func removingSuffix(_ suffix: String) -> String {
		guard hasSuffix(suffix) else { return self }
		return String(dropLast(suffix.count))
	}
}
