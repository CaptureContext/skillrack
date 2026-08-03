import Foundation
import FileSystem

internal struct LocalSkillsRepository {
	internal let fileSystem: any FileSystem

	internal init(fileSystem: any FileSystem) {
		self.fileSystem = fileSystem
	}

	internal func listSkills(
		in inputURL: URL,
		recursively: Bool
	) throws -> [Skill.Descriptor] {
		let rootURL = skillDirectoryURL(for: inputURL)
		guard
			fileSystem.fileExists(atPath: rootURL.path),
			fileSystem.isDirectory(atPath: rootURL.path)
		else {
			throw SkillsManagerError.invalidSkill(
				inputURL,
				reason: "The local directory does not exist."
			)
		}

		let rootIsSkill = fileSystem.fileExists(
			atPath: rootURL.appendingPathComponent("SKILL.md").path
		)
		var descriptors: [Skill.Descriptor] = []

		func visit(
			_ directoryURL: URL,
			depth: Int
		) throws {
			let documentURL = directoryURL.appendingPathComponent("SKILL.md")
			if fileSystem.fileExists(atPath: documentURL.path) {
				descriptors.append(
					try descriptor(
						at: directoryURL,
						documentURL: documentURL
					)
				)
			}

			guard recursively || (!rootIsSkill && depth == 0) else {
				return
			}

			let children = try fileSystem
				.contentsOfDirectory(at: directoryURL)
				.filter { fileSystem.isDirectory(atPath: $0.path) }
				.sorted { $0.lastPathComponent < $1.lastPathComponent }
			for child in children {
				try visit(
					child,
					depth: depth + 1
				)
			}
		}

		try visit(
			rootURL,
			depth: 0
		)
		return descriptors
	}

	internal func loadSkill(from inputURL: URL) throws -> Skill {
		let directoryURL = skillDirectoryURL(for: inputURL)
		let documentURL = directoryURL.appendingPathComponent("SKILL.md")
		let document = try SkillDocument(
			data: fileSystem.data(at: documentURL),
			url: documentURL,
			fallbackName: directoryURL.lastPathComponent
		)
		return .init(
			name: document.name,
			description: document.description,
			properties: document.properties,
			body: document.body,
			attachments: try SkillAttachments(fileSystem: fileSystem)
				.load(from: directoryURL)
		)
	}

	internal func saveSkill(
		_ skill: Skill,
		to directoryURL: URL
	) throws -> [Skill.Descriptor] {
		guard directoryURL.isFileURL else {
			throw SkillsManagerError.unsupportedURL(directoryURL)
		}

		try SkillValidator.validate(skill)

		try fileSystem.createDirectory(
			at: directoryURL,
			withIntermediateDirectories: true
		)

		let destinationURL = directoryURL.appendingPathComponent(
			skill.name,
			isDirectory: true
		)
		let temporaryURL = directoryURL.appendingPathComponent(
			".\(skill.name).\(UUID().uuidString).tmp",
			isDirectory: true
		)

		if fileSystem.fileExists(atPath: temporaryURL.path) {
			try fileSystem.removeItem(at: temporaryURL)
		}

		var shouldRemoveTemporaryDirectory = true
		defer {
			if shouldRemoveTemporaryDirectory {
				try? fileSystem.removeItem(at: temporaryURL)
			}
		}

		try fileSystem.createDirectory(
			at: temporaryURL,
			withIntermediateDirectories: true
		)
		try fileSystem.write(
			try SkillDocument(skill: skill).data(),
			to: temporaryURL.appendingPathComponent("SKILL.md")
		)
		try SkillAttachments(fileSystem: fileSystem)
			.write(
				skill.attachments,
				to: temporaryURL
			)

		if fileSystem.fileExists(atPath: destinationURL.path) {
			try fileSystem.removeItem(at: destinationURL)
		}
		try fileSystem.moveItem(
			at: temporaryURL,
			to: destinationURL
		)
		shouldRemoveTemporaryDirectory = false

		return try listSkills(
			in: destinationURL,
			recursively: true
		)
	}

	internal func deleteSkill(_ descriptor: Skill.Descriptor) throws {
		try fileSystem.removeItem(at: skillDirectoryURL(for: descriptor.url))
	}

	internal func moveSkill(
		_ descriptor: Skill.Descriptor,
		to directoryURL: URL
	) throws {
		guard directoryURL.isFileURL else {
			throw SkillsManagerError.unsupportedURL(directoryURL)
		}

		let sourceURL = skillDirectoryURL(for: descriptor.url)
		try fileSystem.createDirectory(
			at: directoryURL,
			withIntermediateDirectories: true
		)
		let destinationURL = directoryURL.appendingPathComponent(
			sourceURL.lastPathComponent,
			isDirectory: true
		)
		guard !fileSystem.fileExists(atPath: destinationURL.path) else {
			throw SkillsManagerError.destinationAlreadyExists(destinationURL)
		}

		try fileSystem.moveItem(
			at: sourceURL,
			to: destinationURL
		)
	}

	private func descriptor(
		at directoryURL: URL,
		documentURL: URL
	) throws -> Skill.Descriptor {
		let document = try SkillDocument(
			data: fileSystem.data(at: documentURL),
			url: documentURL,
			fallbackName: directoryURL.lastPathComponent
		)
		return .init(
			url: directoryURL,
			name: document.name,
			description: document.description
		)
	}

	private func skillDirectoryURL(for url: URL) -> URL {
		url.lastPathComponent == "SKILL.md"
		? url.deletingLastPathComponent()
		: url
	}
}
