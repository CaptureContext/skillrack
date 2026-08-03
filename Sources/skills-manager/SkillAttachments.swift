import Foundation
import FileSystem

internal struct SkillAttachments {
	internal let fileSystem: any FileSystem

	internal init(fileSystem: any FileSystem) {
		self.fileSystem = fileSystem
	}

	internal func load(
		from directoryURL: URL,
		excludingSkillDocument: Bool = true,
		excluding excludedPaths: Set<String> = [],
		relativeTo rootURL: URL? = nil
	) throws -> [Skill.Attachment] {
		let rootURL = rootURL ?? directoryURL
		var attachments: [Skill.Attachment] = []
		for url in try fileSystem
			.contentsOfDirectory(at: directoryURL)
			.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
			where !excludingSkillDocument || url.lastPathComponent != "SKILL.md"
		{
			let relativePath = url.standardizedFileURL.pathComponents
				.dropFirst(rootURL.standardizedFileURL.pathComponents.count)
				.joined(separator: "/")
			guard !excludedPaths.contains(relativePath) else { continue }
			if fileSystem.isDirectory(atPath: url.path) {
				attachments.append(
					.group(
						name: url.lastPathComponent,
						contents: try load(
							from: url,
							excludingSkillDocument: false,
							excluding: excludedPaths,
							relativeTo: rootURL
						)
					)
				)

			} else {
				attachments.append(
					.file(
						name: url.lastPathComponent,
						data: try fileSystem.data(at: url)
					)
				)
			}
		}
		return attachments
	}

	internal func write(
		_ attachments: [Skill.Attachment],
		to directoryURL: URL
	) throws {
		for attachment in attachments {
			let url = directoryURL.appendingPathComponent(attachment.name)
			switch attachment.content {
			case let .data(data):
				try fileSystem.write(
					data,
					to: url
				)

			case let .group(contents):
				try fileSystem.createDirectory(
					at: url,
					withIntermediateDirectories: true
				)
				try write(
					contents,
					to: url
				)
			}
		}
	}

	internal static func make(
		from files: [(components: [String], data: Data)]
	) throws -> [Skill.Attachment] {
		let names = Set(files.compactMap(\.components.first))
		return try names.sorted().map { name in
			let matching = files.filter { $0.components.first == name }
			if let file = matching.first(where: { $0.components.count == 1 }) {
				guard matching.count == 1 else {
					throw SkillsManagerError.invalidAttachmentName(name)
				}
				return .file(
					name: name,
					data: file.data
				)
			}

			return .group(
				name: name,
				contents: try make(
					from: matching.map {
						(Array($0.components.dropFirst()), $0.data)
					}
				)
			)
		}
	}
}
