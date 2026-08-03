import Dependencies
import FileSystem
import Foundation
import SkillsManager
import Testing

@testable import SkillsRegistryManager

@Suite(.serialized)
struct SkillsRegistryManagerTests {
	@Test
	func detectsResolvesInstallsLinksAndVerifiesFlattenedDependencies() async throws {
		let fixture = try Fixture()
		defer { fixture.remove() }
		let sourceURL = fixture.sourceURL.appending(path: "root-skill")
		try fixture.writeSkill(named: "root-skill", at: sourceURL)
		let dependencyURL = sourceURL.appending(path: "dependencies/shared")
		try fixture.writeSkill(named: "shared-skill", at: dependencyURL)
		let duplicateURL = sourceURL.appending(path: "references/shared")
		try FileManager.default.createDirectory(
			at: duplicateURL.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		try FileManager.default.createSymbolicLink(
			atPath: duplicateURL.path,
			withDestinationPath: "../dependencies/shared"
		)

		try await fixture.withDependencies {
			@Dependency(\.skillsManager) var skillsManager
			@Dependency(\.skillsRegistryManager) var registry

			let candidates = try await skillsManager.detectSkills(sourceURL)
			#expect(candidates.skills.count == 2)
			#expect(candidates.roots.count == 1)
			let rootCandidateID = try #require(candidates.roots.first)
			let dependencies = candidates.dependencies(of: rootCandidateID)
			#expect(
				dependencies.map(\.path) == [
					"dependencies/shared",
					"references/shared",
				]
			)
			#expect(Set(dependencies.map(\.dependency)).count == 1)

			let remoteURL = try #require(
				URL(string: "https://github.com/acme/skills/tree/main/root-skill")
			)
			let outcome = try await registry.resolve(
				candidates,
				source: try SkillSource(remote: remoteURL)
			) { context in
				let status = try await context.verify()
				#expect(status == .available)
				return .install(context.skill.skill)
			}
			let plan = try resolvedPlan(outcome)
			#expect(plan.skills.count == 2)
			let rootID = try #require(plan.roots.first)
			let rootDraft = try #require(plan.skills.first { $0.id == rootID })
			#expect(rootDraft.dependencies.count == 2)
			#expect(Set(rootDraft.dependencies.map(\.skillID)).count == 1)

			var installed: [RegistrySkill] = []
			for draft in plan.skills {
				installed.append(try await registry.install(draft))
			}
			#expect(installed.map(\.id) == plan.skills.map(\.id))

			let link = try await registry.link(
				rootID,
				to: .directory(fixture.linksURL),
				alias: "root-alias"
			)
			let linkedURL = fixture.linksURL.appending(path: "root-alias")
			#expect(
				try FileManager.default.destinationOfSymbolicLink(
					atPath: linkedURL.path
				).hasSuffix("/skills/\(rootID.rawValue)/content")
			)

			let recordURL = fixture.registryURL
				.appending(path: "skills/\(rootID.rawValue)")
			#expect(
				FileManager.default.fileExists(
					atPath: recordURL.appending(path: "skill.json").path
				)
			)
			#expect(
				!FileManager.default.fileExists(
					atPath: recordURL.appending(path: "content/skill.json").path
				)
			)
			for dependency in rootDraft.dependencies {
				let dependencyLink =
					recordURL
						.appending(path: "content")
						.appending(path: dependency.path)
				#expect(
					(try? FileManager.default.destinationOfSymbolicLink(
						atPath: dependencyLink.path
					)) != nil
				)
			}

			#expect(try await registry.verify().isValid)
			try Data("tampered".utf8).write(
				to: recordURL.appending(path: "content/README.txt")
			)
			let verification = try await registry.verify()
			#expect(verification.issues.contains(.digestMismatch(rootID)))

			try await registry.unlink(link)
			try await registry.uninstall(rootID)
			let dependencyID = try #require(rootDraft.dependencies.first?.skillID)
			try await registry.uninstall(dependencyID)
			#expect(try await registry.list().isEmpty)
		}
	}

	@Test
	func resolutionCanReuseAnExistingCanonicalSource() async throws {
		let fixture = try Fixture()
		defer { fixture.remove() }
		let sourceURL = fixture.sourceURL.appending(path: "single")
		try fixture.writeSkill(named: "single-skill", at: sourceURL)

		try await fixture.withDependencies {
			@Dependency(\.skillsManager) var skillsManager
			@Dependency(\.skillsRegistryManager) var registry
			let candidates = try await skillsManager.detectSkills(sourceURL)
			let remoteURL = URL(string: "https://example.com/skills.git")!
			let source = try SkillSource(
				remote: remoteURL,
				local: sourceURL,
				revision: "first"
			)

			let first = try await registry.resolve(candidates, source: source) { context in
				.install(context.skill.skill)
			}
			let firstPlan = try resolvedPlan(first)
			for draft in firstPlan.skills {
				_ = try await registry.install(draft)
			}

			let updatedSource = try SkillSource(
				remote: remoteURL,
				revision: "second"
			)
			let second = try await registry.resolve(candidates, source: updatedSource) { context in
				let status = try await context.verify()
				guard case let .alreadyInstalled(skill) = status else {
					return .abort
				}
				return .useExisting(skill.id)
			}
			let secondPlan = try resolvedPlan(second)
			#expect(secondPlan.skills.isEmpty)
			#expect(secondPlan.roots == firstPlan.roots)
		}
	}

	@Test
	func linkRefusesToOverwriteForeignItems() async throws {
		let fixture = try Fixture()
		defer { fixture.remove() }
		let sourceURL = fixture.sourceURL.appending(path: "single")
		try fixture.writeSkill(named: "single-skill", at: sourceURL)

		try await fixture.withDependencies {
			@Dependency(\.skillsManager) var skillsManager
			@Dependency(\.skillsRegistryManager) var registry
			let candidates = try await skillsManager.detectSkills(sourceURL)
			let outcome = try await registry.resolve(
				candidates,
				source: try SkillSource(local: sourceURL)
			) { .install($0.skill.skill) }
			let plan = try resolvedPlan(outcome)
			let draft = try #require(plan.skills.first)
			_ = try await registry.install(draft)

			try FileManager.default.createDirectory(
				at: fixture.linksURL,
				withIntermediateDirectories: true
			)
			let collisionURL = fixture.linksURL.appending(path: "single-skill")
			try Data("foreign".utf8).write(to: collisionURL)

			await #expect(throws: SkillsRegistryError.linkCollision(collisionURL)) {
				try await registry.link(
					draft.id,
					to: .directory(fixture.linksURL),
					alias: nil
				)
			}
		}
	}

	@Test
	func rejectsMalformedSourcesAndRegistryDirectories() async throws {
		#expect(throws: SkillsRegistryError.sourceIsMissing) {
			try JSONDecoder().decode(
				SkillSource.self,
				from: Data(#"{"remote":null,"local":null}"#.utf8)
			)
		}

		let fixture = try Fixture()
		defer { fixture.remove() }
		try FileManager.default.createDirectory(
			at: fixture.registryURL.appending(path: "skills/not-a-uuid"),
			withIntermediateDirectories: true
		)

		try await fixture.withDependencies {
			@Dependency(\.skillsRegistryManager) var registry
			await #expect(
				throws: SkillsRegistryError.invalidRegistrySkillID("not-a-uuid")
			) {
				try await registry.list()
			}
		}
	}
}

private func resolvedPlan(
	_ outcome: SkillResolutionOutcome
) throws -> SkillResolutionPlan {
	guard case let .resolved(plan) = outcome else {
		throw UnexpectedResolutionAbort()
	}
	return plan
}

private struct UnexpectedResolutionAbort: Error {}

private struct RegistryTestFileSystem: FileSystem, @unchecked Sendable {
	private let manager = FileManager.default

	var homeDirectoryURL: URL { manager.homeDirectoryForCurrentUser }
	var currentDirectoryPath: String { manager.currentDirectoryPath }
	var temporaryDirectoryURL: URL { manager.temporaryDirectory }

	func removeItem(at url: URL) throws { try manager.removeItem(at: url) }
	func fileExists(atPath path: String) -> Bool { manager.fileExists(atPath: path) }
	func isDirectory(atPath path: String) -> Bool {
		var isDirectory = ObjCBool(false)
		return manager.fileExists(atPath: path, isDirectory: &isDirectory)
			&& isDirectory.boolValue
	}
	func createFile(at url: URL, contents: Data?) -> Bool {
		manager.createFile(atPath: url.path, contents: contents)
	}
	func write(_ data: Data, to url: URL) throws { try data.write(to: url) }
	func append(_ data: Data, to url: URL) throws {
		let handle = try FileHandle(forWritingTo: url)
		defer { try? handle.close() }
		try handle.seekToEnd()
		try handle.write(contentsOf: data)
	}
	func data(at url: URL) throws -> Data { try Data(contentsOf: url) }
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
	func createSymbolicLink(at url: URL, withDestinationURL dstURL: URL) throws {
		try manager.createSymbolicLink(at: url, withDestinationURL: dstURL)
	}
	func moveItem(at srcURL: URL, to dstURL: URL) throws {
		try manager.moveItem(at: srcURL, to: dstURL)
	}
	func copyItem(at srcURL: URL, to dstURL: URL) throws {
		try manager.copyItem(at: srcURL, to: dstURL)
	}
	func contentsOfDirectory(at url: URL) throws -> [URL] {
		try manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
	}
	func urls(
		for directory: FileManager.SearchPathDirectory,
		in domainMask: FileManager.SearchPathDomainMask
	) -> [URL] {
		manager.urls(for: directory, in: domainMask)
	}
	func unzipItem(at srcURL: URL, to dstURL: URL) throws {
		throw RegistryTestFileSystemError.unsupported
	}
}

private enum RegistryTestFileSystemError: Error {
	case unsupported
}

private struct Fixture {
	let rootURL: URL
	let sourceURL: URL
	let registryURL: URL
	let homeURL: URL
	let linksURL: URL

	init() throws {
		self.rootURL = FileManager.default.temporaryDirectory.appending(
			path: "skills-registry-tests-\(UUID().uuidString)",
			directoryHint: .isDirectory
		)
		self.sourceURL = rootURL.appending(path: "source", directoryHint: .isDirectory)
		self.registryURL = rootURL.appending(path: "registry", directoryHint: .isDirectory)
		self.homeURL = rootURL.appending(path: "home", directoryHint: .isDirectory)
		self.linksURL = rootURL.appending(path: "links", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(
			at: sourceURL,
			withIntermediateDirectories: true
		)
	}

	func writeSkill(named name: String, at url: URL) throws {
		try FileManager.default.createDirectory(
			at: url,
			withIntermediateDirectories: true
		)
		try Data(
			"""
			---
			name: \(name)
			description: Fixture \(name).
			---

			# \(name)
			""".utf8
		).write(to: url.appending(path: "SKILL.md"))
	}

	func withDependencies<Value: Sendable>(
		_ operation: () async throws -> Value
	) async throws -> Value {
		try await Dependencies.withDependencies {
			$0.skillsRegistryConfiguration = .init(
				rootURL: registryURL,
				homeDirectoryURL: homeURL
			)
			$0.uuid = .incrementing
			$0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
			$0.fileSystem = RegistryTestFileSystem()
			$0.skillsManager = .live
			$0.skillsRegistryManager = LiveSkillsRegistryManager()
		} operation: {
			try await operation()
		}
	}

	func remove() {
		try? FileManager.default.removeItem(at: rootURL)
	}
}
