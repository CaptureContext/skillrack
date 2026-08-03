import Dependencies
import Foundation
import Testing

@testable import SkillsManager
import FileSystem

@Suite
struct SkillsManagerTests {
	@Test
	func savesListsLoadsInstallsAndUninstallsSkills() async throws {
		let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
			"skills-manager-tests-\(UUID().uuidString)",
			isDirectory: true
		)
		defer { try? FileManager.default.removeItem(at: rootURL) }

		let fileSystem = try TestFileSystem(rootURL: rootURL)
		let sharedSkillsURL = rootURL.appendingPathComponent(
			"shared",
			isDirectory: true
		)
		try await withDependencies {
			$0.fileSystem = fileSystem
			$0.skillsDirectoryURL = sharedSkillsURL
			$0.skillSourceLoaders = defaultSourceLoaders
			$0.skillsManager = .live
		} operation: {
			@Dependency(\.skillsManager) var manager

			let nestedDocument = Data(
				"""
				---
				name: nested-skill
				description: A nested skill.
				---

				# Nested
				""".utf8
			)
			let skill = Skill(
				name: "example-skill",
				description: "An example skill.",
				properties: [
					"disable-model-invocation": "true",
					"metadata.author": "CaptureContext",
				],
				body: "# Example",
				attachments: [
					.file(
						name: "README.txt",
						data: Data("attachment".utf8)
					),
					.group(
						name: "nested-skill",
						contents: [
							.file(name: "SKILL.md", data: nestedDocument)
						]
					),
				]
			)

			let saved = try await manager.saveSkill(skill, sharedSkillsURL)
			#expect(saved.map(\.name) == ["example-skill", "nested-skill"])

			let topLevel = try await manager.listSkills(sharedSkillsURL, false)
			#expect(topLevel.map(\.name) == ["example-skill"])

			let recursive = try await manager.listSkills(sharedSkillsURL, true)
			#expect(recursive.map(\.name) == ["example-skill", "nested-skill"])

			let loaded = try await manager.loadSkill(saved[0])
			#expect(loaded.name == skill.name)
			#expect(loaded.description == skill.description)
			#expect(loaded.properties == skill.properties)
			#expect(loaded.body == "# Example\n")
			#expect(loaded.attachments == skill.attachments)

			try await manager.installSkill(skill, .codex)
			let installedURL = fileSystem.homeDirectoryURL
				.appending(path: ".codex/skills/example-skill")
			#expect(fileSystem.fileExists(atPath: installedURL.path))
			#expect(
				try FileManager.default.destinationOfSymbolicLink(
					atPath: installedURL.path
				) == sharedSkillsURL.appending(path: "example-skill").path
			)

			try await manager.uninstallSkill(skill, .codex)
			#expect(!fileSystem.fileExists(atPath: installedURL.path))
		}
	}

	@Test
	func movesAndDeletesLocalSkills() async throws {
		let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
			"skills-manager-tests-\(UUID().uuidString)",
			isDirectory: true
		)
		defer { try? FileManager.default.removeItem(at: rootURL) }

		let fileSystem = try TestFileSystem(rootURL: rootURL)
		try await withDependencies {
			$0.fileSystem = fileSystem
			$0.skillSourceLoaders = defaultSourceLoaders
			$0.skillsManager = .live
		} operation: {
			@Dependency(\.skillsManager) var manager
			let sourceURL = rootURL.appending(path: "source")
			let destinationURL = rootURL.appending(path: "destination")
			let descriptors = try await manager.saveSkill(
				.init(
					name: "moving-skill",
					description: "Moves around."
				),
				sourceURL
			)

			try await manager.moveSkill(descriptors[0], destinationURL)
			let movedURL = destinationURL.appending(path: "moving-skill")
			#expect(fileSystem.fileExists(atPath: movedURL.path))

			let moved = try await manager.listSkills(movedURL, false)
			let movedDescriptor = try #require(moved.first)
			try await manager.deleteSkill(movedDescriptor)
			#expect(!fileSystem.fileExists(atPath: movedURL.path))
		}
	}

	@Test
	func listsAndLoadsGitHubSkills() async throws {
		let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
			"skills-manager-tests-\(UUID().uuidString)",
			isDirectory: true
		)
		defer { try? FileManager.default.removeItem(at: rootURL) }

		let repositoryURL = try #require(
			URL(string: "https://github.com/acme/skills/tree/main/skills")
		)
		let treeURL = try #require(
			URL(
				string: "https://api.github.com/repos/acme/skills/git/trees/main?recursive=1"
			)
		)
		let alphaDocumentURL = try #require(
			URL(
				string: "https://raw.githubusercontent.com/acme/skills/main/skills/alpha/SKILL.md"
			)
		)
		let betaDocumentURL = try #require(
			URL(
				string: "https://raw.githubusercontent.com/acme/skills/main/skills/beta/SKILL.md"
			)
		)
		let gammaDocumentURL = try #require(
			URL(
				string: "https://raw.githubusercontent.com/acme/skills/main/skills/deep/gamma/SKILL.md"
			)
		)
		let notesURL = try #require(
			URL(
				string: "https://raw.githubusercontent.com/acme/skills/main/skills/alpha/notes.txt"
			)
		)

		let tree = Data(
			"""
			{
			  "tree": [
			    {"path": "skills/alpha/SKILL.md", "type": "blob"},
			    {"path": "skills/alpha/notes.txt", "type": "blob"},
			    {"path": "skills/beta/SKILL.md", "type": "blob"},
			    {"path": "skills/deep/gamma/SKILL.md", "type": "blob"}
			  ],
			  "truncated": false
			}
			""".utf8
		)
		let fileSystem = try TestFileSystem(
			rootURL: rootURL,
			remoteData: [
				treeURL: tree,
				alphaDocumentURL: skillDocument(
					name: "alpha",
					description: "Alpha skill."
				),
				betaDocumentURL: skillDocument(
					name: "beta",
					description: "Beta skill."
				),
				gammaDocumentURL: skillDocument(
					name: "gamma",
					description: "Gamma skill."
				),
				notesURL: Data("remote attachment".utf8),
			]
		)

		try await withDependencies {
			$0.fileSystem = fileSystem
			$0.skillSourceLoaders = defaultSourceLoaders
			$0.skillsManager = .live
		} operation: {
			@Dependency(\.skillsManager) var manager

			let direct = try await manager.listSkills(repositoryURL, false)
			#expect(direct.map(\.name) == ["alpha", "beta"])

			let recursive = try await manager.listSkills(repositoryURL, true)
			#expect(recursive.map(\.name) == ["alpha", "beta", "gamma"])

			let alpha = try await manager.loadSkill(direct[0])
			#expect(alpha.name == "alpha")
			#expect(alpha.description == "Alpha skill.")
			#expect(
				alpha.attachments == [
					.file(
						name: "notes.txt",
						data: Data("remote attachment".utf8)
					)
				]
			)
		}
	}

	@Test
	func usesHighestPriorityInjectedLoader() async throws {
		let descriptor = Skill.Descriptor(
			url: URL(string: "custom://skill")!,
			name: "placeholder",
			description: nil
		)

		try await withDependencies {
			$0.skillSourceLoaders = [
				StubSkillSourceLoader(priority: 10, skillName: "low"),
				StubSkillSourceLoader(priority: 100, skillName: "high"),
			]
			$0.skillsManager = .live
		} operation: {
			@Dependency(\.skillsManager) var manager
			let skill = try await manager.loadSkill(descriptor)
			#expect(skill.name == "high")
		}
	}

	@Test
	func detectsMentionedSkillDependenciesAfterDiscoveringAllSkills() async throws {
		let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
			"skills-manager-tests-\(UUID().uuidString)",
			isDirectory: true
		)
		defer { try? FileManager.default.removeItem(at: rootURL) }

		let fileSystem = try TestFileSystem(rootURL: rootURL)
		let collectionURL = rootURL.appending(path: "collection")
		for (name, body) in [
			("alpha", "Use /gamma for this workflow."),
			("beta", "# Beta"),
			("gamma", "# Gamma"),
		] {
			let skillURL = collectionURL.appending(path: name)
			try FileManager.default.createDirectory(
				at: skillURL,
				withIntermediateDirectories: true
			)
			try Data(
				"""
				---
				name: \(name)
				description: \(name) fixture.
				---

				\(body)
				""".utf8
			).write(to: skillURL.appending(path: "SKILL.md"))
		}
		try Data("Always consult the `beta` skill.".utf8).write(
			to: collectionURL.appending(path: "alpha/notes.md")
		)

		try await withDependencies {
			$0.fileSystem = fileSystem
			$0.skillsManager = .live
		} operation: {
			@Dependency(\.skillsManager) var manager
			let detected = try await manager.detectSkills(collectionURL)
			let alpha = try #require(
				detected.skills.values.first { $0.skill.name == "alpha" }
			)
			let dependencies = detected.dependencies(of: alpha.id)
			#expect(dependencies.map(\.kind) == [.mentioned, .mentioned])
			#expect(Set(dependencies.map(\.path)) == ["beta", "gamma"])
		}
	}
}

private struct TestFileSystem: FileSystem, @unchecked Sendable {
	let manager = FileManager.default
	let homeDirectoryURL: URL
	let currentDirectoryPath: String
	let temporaryDirectoryURL: URL
	let remoteData: [URL: Data]

	init(
		rootURL: URL,
		remoteData: [URL: Data] = [:]
	) throws {
		self.homeDirectoryURL = rootURL.appendingPathComponent(
			"home",
			isDirectory: true
		)
		self.currentDirectoryPath = rootURL.path
		self.temporaryDirectoryURL = rootURL.appendingPathComponent(
			"tmp",
			isDirectory: true
		)
		self.remoteData = remoteData
		try manager.createDirectory(
			at: homeDirectoryURL,
			withIntermediateDirectories: true
		)
		try manager.createDirectory(
			at: temporaryDirectoryURL,
			withIntermediateDirectories: true
		)
	}

	func removeItem(at url: URL) throws {
		try manager.removeItem(at: url)
	}

	func fileExists(atPath path: String) -> Bool {
		manager.fileExists(atPath: path)
	}

	func isDirectory(atPath path: String) -> Bool {
		var isDirectory = ObjCBool(false)
		return manager.fileExists(
			atPath: path,
			isDirectory: &isDirectory
		) && isDirectory.boolValue
	}

	func createFile(at url: URL, contents: Data?) -> Bool {
		manager.createFile(atPath: url.path, contents: contents)
	}

	func write(_ data: Data, to url: URL) throws {
		try data.write(to: url)
	}

	func append(_ data: Data, to url: URL) throws {
		let handle = try FileHandle(forWritingTo: url)
		defer { try? handle.close() }
		try handle.seekToEnd()
		try handle.write(contentsOf: data)
	}

	func data(at url: URL) throws -> Data {
		if let data = remoteData[url] {
			return data
		}
		return try Data(contentsOf: url)
	}

	func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
		try manager.attributesOfItem(atPath: path)
	}

	func open(_ url: URL) {}

	func createDirectory(
		at url: URL,
		withIntermediateDirectories createIntermediates: Bool
	) throws {
		try manager.createDirectory(
			at: url,
			withIntermediateDirectories: createIntermediates
		)
	}

	func createSymbolicLink(
		at url: URL,
		withDestinationURL dstURL: URL
	) throws {
		try manager.createSymbolicLink(
			at: url,
			withDestinationURL: dstURL
		)
	}

	func moveItem(at srcURL: URL, to dstURL: URL) throws {
		try manager.moveItem(at: srcURL, to: dstURL)
	}

	func copyItem(at srcURL: URL, to dstURL: URL) throws {
		try manager.copyItem(at: srcURL, to: dstURL)
	}

	func contentsOfDirectory(at url: URL) throws -> [URL] {
		try manager.contentsOfDirectory(
			at: url,
			includingPropertiesForKeys: nil
		)
	}

	func urls(
		for directory: FileManager.SearchPathDirectory,
		in domainMask: FileManager.SearchPathDomainMask
	) -> [URL] {
		manager.urls(for: directory, in: domainMask)
	}

	func unzipItem(at srcURL: URL, to dstURL: URL) throws {
		throw TestError.unsupported
	}
}

private enum TestError: Error {
	case unsupported
}

private var defaultSourceLoaders: [any SkillSourceLoaderProtocol] {
	[
		LocalSkillSourceLoader(),
		GitHubSkillSourceLoader(),
	]
}

private struct StubSkillSourceLoader: SkillSourceLoaderProtocol {
	let priority: Int
	let skillName: String

	func loadSkill(from url: URL) async throws -> Skill {
		.init(name: skillName, description: nil)
	}
}

private func skillDocument(
	name: String,
	description: String
) -> Data {
	Data(
		"""
		---
		name: \(name)
		description: \(description)
		---

		# \(name)
		""".utf8
	)
}
