import Dependencies
import Foundation
import FileSystem

internal struct SkillsDetector {
	internal let fileSystem: any FileSystem

	internal init(fileSystem: any FileSystem) {
		self.fileSystem = fileSystem
	}

	internal func detect(in inputURL: URL) throws -> DetectedSkills {
		guard inputURL.isFileURL else {
			throw SkillsManagerError.unsupportedURL(inputURL)
		}

		let rootURL = skillDirectoryURL(for: inputURL).standardizedFileURL
		guard
			fileSystem.fileExists(atPath: rootURL.path),
			fileSystem.isDirectory(atPath: rootURL.path)
		else {
			throw SkillsManagerError.invalidSkill(
				inputURL,
				reason: "The local directory does not exist."
			)
		}

		var occurrences: [DetectedSkill.ID: URL] = [:]
		var roots: [DetectedSkill.ID] = []
		var references: Set<DetectedSkills.Reference> = []
		var visitedDirectories: Set<URL> = []

		func visit(
			_ directoryURL: URL,
			parent: (id: DetectedSkill.ID, url: URL)?
		) throws {
			let canonicalURL = directoryURL
				.resolvingSymlinksInPath()
				.standardizedFileURL
			let documentURL = directoryURL.appendingPathComponent("SKILL.md")
			let isSkill = fileSystem.fileExists(atPath: documentURL.path)
			var nextParent = parent

			if isSkill {
				let id = DetectedSkill.ID(url: canonicalURL)
				occurrences[id] = occurrences[id] ?? directoryURL.standardizedFileURL

				if let parent {
					references.insert(
						.init(
							parent: parent.id,
							dependency: id,
							path: relativePath(
								from: parent.url,
								to: directoryURL
							)
						)
					)

				} else if !roots.contains(id) {
					roots.append(id)
				}

				nextParent = (id, directoryURL.standardizedFileURL)
			}

			guard visitedDirectories.insert(canonicalURL).inserted else {
				return
			}

			let children = try fileSystem.contentsOfDirectory(at: directoryURL)
				.filter { fileSystem.isDirectory(atPath: $0.path) }
				.sorted { $0.lastPathComponent < $1.lastPathComponent }
			for child in children {
				try visit(
					child,
					parent: nextParent
				)
			}
		}

		try visit(
			rootURL,
			parent: nil
		)

		let sortedReferences = references.sorted { lhs, rhs in
			if lhs.parent != rhs.parent {
				return lhs.parent.rawValue < rhs.parent.rawValue
			}
			if lhs.path != rhs.path {
				return lhs.path < rhs.path
			}
			return lhs.dependency.rawValue < rhs.dependency.rawValue
		}

		var skills: [DetectedSkill.ID: DetectedSkill] = [:]
		for (id, url) in occurrences {
			let excludedPaths = Set(
				sortedReferences
					.filter { $0.parent == id }
					.map(\.path)
			)
			let documentURL = url.appendingPathComponent("SKILL.md")
			let document = try SkillDocument(
				data: fileSystem.data(at: documentURL),
				url: documentURL,
				fallbackName: url.lastPathComponent
			)
			let skill = Skill(
				name: document.name,
				description: document.description,
				properties: document.properties,
				body: document.body,
				attachments: try SkillAttachments(fileSystem: fileSystem).load(
					from: url,
					excluding: excludedPaths
				)
			)
			skills[id] = DetectedSkill(
				id: id,
				url: url,
				relativePath: relativePath(
					from: rootURL,
					to: url
				),
				skill: skill
			)
		}

		let skillsByName = Dictionary(grouping: skills.values, by: \.skill.name)
		for parent in skills.values {
			let document = [
				parent.skill.description,
				parent.skill.body,
				markdownText(in: parent.skill.attachments),
			]
				.compactMap { $0 }
				.joined(separator: "\n")
				.replacingOccurrences(of: "`", with: "")
				.lowercased()
			for name in skillsByName.keys.sorted() {
				guard
					name != parent.skill.name,
					mentionsSkill(named: name, in: document),
					let matches = skillsByName[name]
				else { continue }

				guard matches.count == 1 else {
					let paths = matches.map(\.relativePath).sorted().joined(separator: ", ")
					throw SkillsManagerError.invalidSkill(
						parent.url,
						reason: "The mentioned skill '\(name)' is ambiguous: \(paths)."
					)
				}

				guard
					let dependency = matches.first,
					!references.contains(where: {
						$0.parent == parent.id && $0.dependency == dependency.id
					})
				else { continue }

				references.insert(
					.init(
						parent: parent.id,
						dependency: dependency.id,
						path: name,
						kind: .mentioned
					)
				)
			}
		}

		let allReferences = references.sorted { lhs, rhs in
			if lhs.parent != rhs.parent {
				return lhs.parent.rawValue < rhs.parent.rawValue
			}
			if lhs.path != rhs.path {
				return lhs.path < rhs.path
			}
			if lhs.kind != rhs.kind {
				return lhs.kind.rawValue < rhs.kind.rawValue
			}
			return lhs.dependency.rawValue < rhs.dependency.rawValue
		}

		return DetectedSkills(
			rootURL: rootURL,
			roots: roots.sorted { $0.rawValue < $1.rawValue },
			skills: skills,
			references: allReferences
		)
	}

	private func mentionsSkill(
		named name: String,
		in document: String
	) -> Bool {
		let escapedName = NSRegularExpression.escapedPattern(for: name.lowercased())
		let pattern = "(?<![a-z0-9-])(?:/\(escapedName)|\(escapedName)\\s+skill)(?![a-z0-9-])"
		guard let expression = try? NSRegularExpression(pattern: pattern) else {
			return false
		}

		let range = NSRange(document.startIndex..., in: document)
		return expression.firstMatch(in: document, range: range) != nil
	}

	private func markdownText(
		in attachments: [Skill.Attachment]
	) -> String {
		attachments.compactMap { attachment in
			switch attachment.content {
			case let .data(data):
				guard attachment.name.lowercased().hasSuffix(".md") else {
					return nil
				}

				return String(data: data, encoding: .utf8)

			case let .group(children):
				return markdownText(in: children)
			}
		}
		.joined(separator: "\n")
	}

	private func skillDirectoryURL(for url: URL) -> URL {
		url.lastPathComponent == "SKILL.md"
		? url.deletingLastPathComponent()
		: url
	}

	private func relativePath(
		from parentURL: URL,
		to childURL: URL
	) -> String {
		let parentComponents = parentURL.standardizedFileURL.pathComponents
		let childComponents = childURL.standardizedFileURL.pathComponents
		guard childComponents.starts(with: parentComponents) else {
			return childURL.lastPathComponent
		}

		return childComponents.dropFirst(parentComponents.count).joined(separator: "/")
	}
}
