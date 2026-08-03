import Foundation
import FileSystem

internal struct GitHubSkillsRepository {
	internal let fileSystem: any FileSystem

	internal init(fileSystem: any FileSystem) {
		self.fileSystem = fileSystem
	}

	internal func listSkills(
		in source: GitHubSkillsSource,
		recursively: Bool
	) throws -> [Skill.Descriptor] {
		let entries = try source.entries(fileSystem: fileSystem)
		let basePath = source.path.trimmingCharacters(
			in: CharacterSet(charactersIn: "/")
		)
		let rootDocumentPath = joinedPath(
			basePath,
			"SKILL.md"
		)
		let rootIsSkill = entries.contains {
			$0.type == "blob" && $0.path == rootDocumentPath
		}

		let documentPaths = entries
			.filter { entry in
				guard
					entry.type == "blob",
					entry.path.lastPathComponent == "SKILL.md",
					isPath(
						entry.path,
						inside: basePath
					)
				else { return false }

				let directoryPath = entry.path.deletingLastPathComponent
				if recursively {
					return true
				}
				if rootIsSkill {
					return directoryPath == basePath
				}

				let relative = relativePath(
					directoryPath,
					to: basePath
				)
				return !relative.isEmpty && !relative.contains("/")
			}
			.map(\.path)
			.sorted()

		return try documentPaths.map { documentPath in
			let directoryPath = documentPath.deletingLastPathComponent
			let document = try SkillDocument(
				data: source.data(
					at: documentPath,
					fileSystem: fileSystem
				),
				url: source.skillURL(at: directoryPath),
				fallbackName: directoryPath.lastPathComponent
			)
			return .init(
				url: source.skillURL(at: directoryPath),
				name: document.name,
				description: document.description
			)
		}
	}

	internal func loadSkill(from source: GitHubSkillsSource) throws -> Skill {
		let documentPath = joinedPath(
			source.path,
			"SKILL.md"
		)
		let documentURL = source.skillURL(at: source.path)
		let document = try SkillDocument(
			data: source.data(
				at: documentPath,
				fileSystem: fileSystem
			),
			url: documentURL,
			fallbackName: source.path.lastPathComponent
		)

		let prefix = source.path.isEmpty ? "" : source.path + "/"
		let files = try source.entries(fileSystem: fileSystem)
			.filter {
				$0.type == "blob"
					&& $0.path.hasPrefix(prefix)
					&& $0.path != documentPath
			}
			.map { entry in
				(
					components: Array(
						entry.path
							.dropFirst(prefix.count)
							.split(separator: "/")
							.map(String.init)
					),
					data: try source.data(
						at: entry.path,
						fileSystem: fileSystem
					)
				)
			}

		return .init(
			name: document.name,
			description: document.description,
			properties: document.properties,
			body: document.body,
			attachments: try SkillAttachments.make(from: files)
		)
	}

	private func joinedPath(
		_ lhs: String,
		_ rhs: String
	) -> String {
		lhs.isEmpty ? rhs : lhs + "/" + rhs
	}

	private func isPath(
		_ path: String,
		inside basePath: String
	) -> Bool {
		basePath.isEmpty || path == basePath || path.hasPrefix(basePath + "/")
	}

	private func relativePath(
		_ path: String,
		to basePath: String
	) -> String {
		guard !basePath.isEmpty else { return path }
		guard path != basePath else { return "" }
		return String(path.dropFirst(basePath.count + 1))
	}
}

private extension String {
	var lastPathComponent: String {
		(self as NSString).lastPathComponent
	}

	var deletingLastPathComponent: String {
		(self as NSString).deletingLastPathComponent
	}
}
