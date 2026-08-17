import ArgumentParser
import Foundation
import SkillsManager
import SkillsRegistryManager
import Testing

@testable import skillrack

@Suite(.serialized)
struct CLIContractTests {
	@Test
	func parsesCompleteCommandSurface() async throws {
		let list = try #require(
			try AppCommand.parseAsRoot([
				"list", "--no-print-all", "--print-name", "--print-desc",
			]) as? ListCommand
		)
		#expect(!list.printAll)
		#expect(list.printName)
		#expect(list.printDescription)
		#expect(try AppCommand.parseAsRoot(["show", "example"]) is ShowCommand)
		#expect(try AppCommand.parseAsRoot(["path", "example"]) is PathCommand)
		#expect(try AppCommand.parseAsRoot(["verify"]) is VerifyCommand)
		#expect(try AppCommand.parseAsRoot(["version"]) is VersionCommand)
		#expect(try AppCommand.parseAsRoot(["uninstall", "example", "--yes"]) is UninstallCommand)
		#expect(try AppCommand.parseAsRoot(["link", "example", "--tool", "codex"]) is LinkCommand)
		#expect(try AppCommand.parseAsRoot(["unlink", "example", "--all", "--yes"]) is UnlinkCommand)

		let install = try #require(
			try AppCommand.parseAsRoot([
				"install", "https://example.com/skills.git",
				"--clone-to", "/tmp/skills-checkout",
				"--if-present", "skip",
				"--skill", "one",
				"--skill", "two",
				"--show-descriptions",
				"--force",
				"--json",
			]) as? InstallCommand
		)
		#expect(install.skill == ["one", "two"])
		#expect(install.showDescriptions)
		#expect(install.force)
		#expect(
			try globalMachineOutputRequested(
				arguments: ["install", "https://example.com/skills.git", "--json"],
				environment: [:]
			)
		)
	}

	@Test
	func rootSkillSelectionIsCompactUnlessDescriptionsAreRequested() async throws {
		let root = DetectedSkill(
			id: .init(rawValue: "root"),
			url: URL(fileURLWithPath: "/tmp/skills/engineering/example"),
			relativePath: "engineering/example",
			skill: Skill(
				name: "example",
				description: "An example skill."
			)
		)

		let compact = try #require(
			rootSkillPromptOptions(
				[root],
				showDescriptions: false
			).first
		)
		#expect(compact.value == "engineering/example")
		#expect(compact.label == "example")
		#expect(compact.hint == nil)

		let described = try #require(
			rootSkillPromptOptions(
				[root],
				showDescriptions: true
			).first
		)
		#expect(described.value == "engineering/example")
		#expect(described.label == "example")
		#expect(described.hint == "An example skill.")
		#expect(described.hint?.contains(root.relativePath) == false)
	}

	@Test
	func promptOptionsFitWithinTheTerminalWidth() async throws {
		let option = TerminalPromptOption(
			value: "example",
			label: "example",
			hint: "A description that would otherwise wrap onto another terminal row."
		)

		let fitted = fittedPromptOption(
			option,
			terminalWidth: 40
		)
		let renderedContentCount = fitted.label.count
		+ (fitted.hint.map { 2 + $0.count } ?? 0)

		#expect(renderedContentCount <= 30)
		#expect(fitted.hint?.hasSuffix("…") == true)
	}

	@Test
	func listProjectsFieldsAndForceUpdatesACollectionInPlace() throws {
		let fixture = try CLIFixture(includingSecondRoot: true)
		defer { fixture.remove() }

		let initial = try fixture.run([
			"install", fixture.sourceURL.path, "--all", "--json",
		])
		#expect(initial.status == 0)
		let initialSkills = try installedSkills(in: initial.stdout)
		#expect(initialSkills.count == 2)
		let initialIDs: [String: String] = Dictionary(
			uniqueKeysWithValues: initialSkills.compactMap { skill in
				guard
					let name = skill["name"] as? String,
					let id = skill["id"] as? String
				else { return nil }
				return (name, id)
			}
		)
		let exampleID = try #require(initialIDs["example"])

		let link = try fixture.run([
			"link", "example", "--directory", fixture.linksURL.path, "--json",
		])
		#expect(link.status == 0)

		try fixture.writeExample(
			description: "Updated example.",
			body: "# Updated example"
		)
		try fixture.writeSecond(
			description: "Updated second.",
			body: "# Updated second"
		)

		let reused = try fixture.run([
			"install", fixture.sourceURL.path, "--all", "--json",
		])
		#expect(reused.status == 0)
		let reusedData = try responseData(in: reused.stdout)
		#expect((reusedData["reused"] as? [Any])?.count == 2)
		#expect((reusedData["updated"] as? [Any])?.isEmpty == true)

		let forced = try fixture.run([
			"install", fixture.sourceURL.path, "--all", "--force", "--json",
		])
		#expect(forced.status == 0)
		let forcedData = try responseData(in: forced.stdout)
		let updated = try #require(forcedData["updated"] as? [[String: Any]])
		#expect(updated.count == 2)
		let updatedIDs: [String: String] = Dictionary(
			uniqueKeysWithValues: updated.compactMap { skill in
				guard
					let name = skill["name"] as? String,
					let id = skill["id"] as? String
				else { return nil }
				return (name, id)
			}
		)
		#expect(updatedIDs == initialIDs)

		let descriptions = try fixture.run([
			"list", "--no-print-all", "--print-desc",
		])
		#expect(descriptions.status == 0)
		#expect(descriptions.stdout == "Updated example.\nUpdated second.\n")

		let namesAndDescriptions = try fixture.run([
			"list", "--no-print-all", "--print-name", "--print-desc",
		])
		#expect(namesAndDescriptions.status == 0)
		#expect(
			namesAndDescriptions.stdout
				== "example\tUpdated example.\nsecond\tUpdated second.\n"
		)

		let defaultList = try fixture.run(["list"])
		#expect(defaultList.status == 0)
		#expect(
			defaultList.stdout
				.split(separator: "\n")
				.allSatisfy { $0.split(separator: "\t", omittingEmptySubsequences: false).count == 6 }
		)

		let missingProjection = try fixture.run([
			"list", "--no-print-all",
		])
		#expect(missingProjection.status != 0)
		#expect(missingProjection.stderr.contains("requires at least one --print-* field"))

		let installedDocument = try String(
			contentsOf: fixture.registryURL.appending(
				path: "skills/\(exampleID)/content/SKILL.md"
			),
			encoding: .utf8
		)
		#expect(installedDocument.contains("Updated example."))
		#expect(
			(try? FileManager.default.destinationOfSymbolicLink(
				atPath: fixture.linksURL.appending(path: "example").path
			))?.contains(exampleID) == true
		)
	}

	@Test
	func rejectsMutuallyExclusiveInstallSelectors() {
		#expect(throws: (any Error).self) {
			_ = try AppCommand.parseAsRoot([
				"install", ".", "--skill", "one", "--all",
			])
		}
	}

	@Test(arguments: Tool.allCases)
	func parsesEveryTool(_ tool: Tool) throws {
		let command = try #require(
			try AppCommand.parseAsRoot([
				"link", "example", "--tool", tool.rawValue,
			]) as? LinkCommand
		)
		#expect(command.tool == [tool])
	}

	@Test
	func resolvesMachineOutputPrecedence() throws {
		#expect(
			try globalMachineOutputRequested(
				arguments: [],
				environment: ["SKILLRACK_JSON": "1"]
			)
		)
		#expect(
			try !globalMachineOutputRequested(
				arguments: ["list", "--no-json"],
				environment: ["SKILLRACK_JSON": "1"]
			)
		)
		#expect(
			try globalMachineOutputRequested(
				arguments: ["--no-json", "list", "--json"],
				environment: [:]
			)
		)
		#expect(throws: (any Error).self) {
			_ = try globalMachineOutputRequested(
				arguments: [],
				environment: ["SKILLRACK_JSON": "yes"]
			)
		}
	}

	@Test
	func encodesVersionedSnakeCaseEnvelope() throws {
		let data = try encodedJSON(
			MachineResponse(data: InstallEnvelopeFixture(checkoutRevision: "abc"))
		)
		let text = String(
			decoding: data,
			as: UTF8.self
		)
		#expect(text.contains(#""api_version" : 1"#))
		#expect(text.contains(#""checkout_revision" : "abc""#))
		#expect(text.contains(#""ok" : true"#))
	}

	@Test
	func parsesLocalRemoteAndTildeSources() throws {
		let home = URL(fileURLWithPath: "/Users/example")
		#expect(
			try SourceArgument(
				"skills",
				currentDirectory: "/work",
				homeDirectory: home
			) == .local(URL(fileURLWithPath: "/work/skills"))
		)
		#expect(
			try SourceArgument(
				"~/skills",
				currentDirectory: "/work",
				homeDirectory: home
			) == .local(URL(fileURLWithPath: "/Users/example/skills"))
		)
		#expect(
			try SourceArgument(
				"https://example.com/skills.git",
				currentDirectory: "/work",
				homeDirectory: home
			) == .remote(URL(string: "https://example.com/skills.git")!)
		)
		#expect(throws: (any Error).self) {
			_ = try SourceArgument(
				"git@example.com:org/skills.git",
				currentDirectory: "/work",
				homeDirectory: home
			)
		}
	}

	@Test
	func redactsCredentialBearingURLs() {
		let message = redactCredentials(
			in: "git clone https://token:secret@example.com/repo.git failed"
		)
		#expect(message == "git clone https://[redacted]@example.com/repo.git failed")
	}

	@Test
	func skillSourcePreservesRootRevisionAndRelativePath() throws {
		let root = try SkillSource(
			remote: URL(string: "https://example.com/repo.git"),
			local: URL(fileURLWithPath: "/tmp/repo"),
			revision: "deadbeef"
		)
		let nested = try root.appending(relativePath: "skills/example")
		#expect(nested.remote == root.remote)
		#expect(nested.local == root.local)
		#expect(nested.revision == "deadbeef")
		#expect(nested.path == "skills/example")
		#expect(root != nested)
		#expect(throws: SkillsRegistryError.invalidSourcePath("../secret")) {
			_ = try SkillSource(
				local: URL(fileURLWithPath: "/tmp/repo"),
				path: "../secret"
			)
		}
	}

	@Test
	func registrySelectorSupportsIDsAndReportsAmbiguousNames() throws {
		let first = try fixtureSkill(
			id: 1,
			name: "shared"
		)
		let second = try fixtureSkill(
			id: 2,
			name: "shared"
		)
		#expect(
			try resolveRegistrySkill(
				first.id.rawValue,
				from: [first, second]
			).id == first.id
		)
		#expect(throws: (any Error).self) {
			_ = try resolveRegistrySkill(
				"shared",
				from: [first, second]
			)
		}
	}

	@Test
	func executableInstallsLinksVerifiesUnlinksAndUninstallsInIsolation() throws {
		let fixture = try CLIFixture()
		defer { fixture.remove() }

		let missingSelector = try fixture.run(["show", "--json"])
		#expect(missingSelector.status != 0)
		#expect(missingSelector.stdout.isEmpty)
		#expect(missingSelector.stderr.contains(#""code" : "invalid_arguments""#))
		#expect(missingSelector.stderr.contains(#""ok" : false"#))
		#expect(missingSelector.stderr.hasSuffix("\n"))
		#expect(!missingSelector.stderr.hasSuffix("\n\n"))

		let install = try fixture.run([
			"install", fixture.sourceURL.path, "--json",
		])
		#expect(install.status == 0)
		#expect(install.stderr.isEmpty)
		#expect(install.stdout.contains(#""name" : "example""#))
		#expect(install.stdout.hasSuffix("\n"))
		#expect(!install.stdout.hasSuffix("\n\n"))
		let installObject = try #require(
			JSONSerialization.jsonObject(with: Data(install.stdout.utf8)) as? [String: Any]
		)
		let installData = try #require(installObject["data"] as? [String: Any])
		let installed = try #require(installData["installed"] as? [[String: Any]])
		let installedID = try #require(installed.first?["id"] as? String)
		let path = try fixture.run(["path", "example"])
		#expect(path.status == 0)
		#expect(
			path.stdout
				== fixture.registryURL.appending(path: "skills/\(installedID)/content").path + "\n"
		)

		let link = try fixture.run([
			"link", "example", "--directory", fixture.linksURL.path, "--json",
		])
		#expect(link.status == 0)
		#expect(link.stderr.isEmpty)
		let linkedDestination = try? FileManager.default.destinationOfSymbolicLink(
			atPath: fixture.linksURL.appending(path: "example").path
		)
		#expect(linkedDestination != nil)

		let verify = try fixture.run(["verify", "--json"])
		#expect(verify.status == 0)
		#expect(verify.stderr.isEmpty)
		#expect(verify.stdout.contains(#""valid" : true"#))

		try Data("tampered".utf8).write(
			to: fixture.registryURL
				.appending(path: "skills/\(installedID)/content/tampered.txt")
		)
		let invalidVerify = try fixture.run(["verify", "--json"])
		#expect(invalidVerify.status != 0)
		#expect(invalidVerify.stderr.isEmpty)
		#expect(invalidVerify.stdout.contains(#""ok" : true"#))
		#expect(invalidVerify.stdout.contains(#""valid" : false"#))

		let unlink = try fixture.run([
			"unlink", "example", "--all", "--yes", "--json",
		])
		#expect(unlink.status == 0)
		#expect(unlink.stderr.isEmpty)

		let uninstall = try fixture.run([
			"uninstall", "example", "--yes", "--json",
		])
		#expect(uninstall.status == 0)
		#expect(uninstall.stderr.isEmpty)

		let list = try fixture.run(["list", "--json"])
		#expect(list.status == 0)
		let object = try #require(
			JSONSerialization.jsonObject(with: Data(list.stdout.utf8)) as? [String: Any]
		)
		let data = try #require(object["data"] as? [String: Any])
		#expect((data["skills"] as? [Any])?.isEmpty == true)
	}

	@Test
	func linkRequiresExplicitOrAutomaticMentionedDependencies() throws {
		let fixture = try CLIFixture(includingMentionedDependency: true)
		defer { fixture.remove() }

		let install = try fixture.run([
			"install", fixture.sourceURL.path, "--skill", "example", "--json",
		])
		#expect(install.status == 0)
		#expect(install.stdout.contains(#""name" : "dependency""#))

		let unresolved = try fixture.run([
			"link", "example", "--directory", fixture.linksURL.path, "--json",
		])
		#expect(unresolved.status != 0)
		#expect(unresolved.stderr.contains("--with-dependencies"))
		#expect(!FileManager.default.fileExists(atPath: fixture.linksURL.path))

		let linked = try fixture.run([
			"link", "example", "--directory", fixture.linksURL.path,
			"--with-dependencies", "--json",
		])
		#expect(linked.status == 0)
		#expect(
			(try? FileManager.default.destinationOfSymbolicLink(
				atPath: fixture.linksURL.appending(path: "dependency").path
			)) != nil
		)
		#expect(
			(try? FileManager.default.destinationOfSymbolicLink(
				atPath: fixture.linksURL.appending(path: "example").path
			)) != nil
		)
	}
}

private struct InstallEnvelopeFixture: Encodable {
	let checkoutRevision: String
}

private func responseData(in output: String) throws -> [String: Any] {
	let object = try #require(
		JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]
	)
	return try #require(object["data"] as? [String: Any])
}

private func installedSkills(in output: String) throws -> [[String: Any]] {
	let data = try responseData(in: output)
	return try #require(data["installed"] as? [[String: Any]])
}

private func fixtureSkill(
	id: Int,
	name: String
) throws -> RegistrySkill {
	let value = String(
		format: "00000000-0000-0000-0000-%012d",
		id
	)
	return RegistrySkill(
		id: RegistrySkill.ID(rawValue: value)!,
		name: name,
		source: try SkillSource(local: URL(fileURLWithPath: "/tmp/\(id)")),
		digest: .init(
			algorithm: "sha256",
			hash: String(
				repeating: "0",
				count: 64
			)
		),
		createdAt: Date(timeIntervalSince1970: 0),
		updatedAt: Date(timeIntervalSince1970: 0)
	)
}

private struct CLIFixture: @unchecked Sendable {
	let rootURL: URL
	let sourceURL: URL
	let exampleURL: URL
	let secondURL: URL?
	let registryURL: URL
	let homeURL: URL
	let linksURL: URL

	init(
		includingMentionedDependency: Bool = false,
		includingSecondRoot: Bool = false
	) throws {
		rootURL = FileManager.default.temporaryDirectory.appending(
			path: "skillrack-tests-\(UUID().uuidString.lowercased())",
			directoryHint: .isDirectory
		)
		sourceURL = rootURL.appending(
			path: "source",
			directoryHint: .isDirectory
		)
		registryURL = rootURL.appending(
			path: "registry",
			directoryHint: .isDirectory
		)
		homeURL = rootURL.appending(
			path: "home",
			directoryHint: .isDirectory
		)
		linksURL = rootURL.appending(
			path: "links",
			directoryHint: .isDirectory
		)
		try FileManager.default.createDirectory(
			at: sourceURL,
			withIntermediateDirectories: true
		)
		let exampleBody =
			includingMentionedDependency
			? "# Example\n\nAlways consult the `dependency` skill."
			: "# Example"
		exampleURL =
			includingMentionedDependency || includingSecondRoot
			? sourceURL.appending(path: "example", directoryHint: .isDirectory)
			: sourceURL
		secondURL =
			includingSecondRoot
			? sourceURL.appending(path: "second", directoryHint: .isDirectory)
			: nil
		try writeExample(
			description: "End-to-end fixture.",
			body: exampleBody
		)
		if includingSecondRoot {
			try writeSecond(
				description: "Second fixture.",
				body: "# Second"
			)
		}
		if includingMentionedDependency {
			let dependencyURL = sourceURL.appending(
				path: "dependency",
				directoryHint: .isDirectory
			)
			try FileManager.default.createDirectory(
				at: dependencyURL,
				withIntermediateDirectories: true
			)
			try Data(
				"""
				---
				name: dependency
				description: A required companion.
				---

				# Dependency
				""".utf8
			).write(to: dependencyURL.appending(path: "SKILL.md"))
		}
	}

	func writeExample(
		description: String,
		body: String
	) throws {
		try writeSkill(
			name: "example",
			description: description,
			body: body,
			to: exampleURL
		)
	}

	func writeSecond(
		description: String,
		body: String
	) throws {
		guard let secondURL else { throw CLIFixtureError.secondSkillUnavailable }
		try writeSkill(
			name: "second",
			description: description,
			body: body,
			to: secondURL
		)
	}

	private func writeSkill(
		name: String,
		description: String,
		body: String,
		to url: URL
	) throws {
		try FileManager.default.createDirectory(
			at: url,
			withIntermediateDirectories: true
		)
		try Data(
			"""
			---
			name: \(name)
			description: \(description)
			---

			\(body)
			""".utf8
		).write(to: url.appending(path: "SKILL.md"))
	}

	func remove() { try? FileManager.default.removeItem(at: rootURL) }

	func run(_ arguments: [String]) throws -> ProcessResult {
		let packageURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
		let candidates = [
			packageURL.appending(path: ".build/debug/skillrack"),
			packageURL.appending(path: ".build/out/Products/Debug/skillrack"),
		]
		guard
			let executableURL = candidates.first(where: {
				FileManager.default.isExecutableFile(atPath: $0.path)
			})
		else { throw CLIFixtureError.executableNotFound }

		let process = Process()
		let output = Pipe()
		let error = Pipe()
		process.executableURL = executableURL
		process.arguments = arguments
		process.environment = ProcessInfo.processInfo.environment.merging(
			[
				"SKILLRACK_ROOT": registryURL.path,
				"SKILLRACK_HOME": homeURL.path,
				"NO_COLOR": "1",
			],
			uniquingKeysWith: { _, newValue in newValue }
		)
		process.standardOutput = output
		process.standardError = error
		try process.run()
		process.waitUntilExit()
		return ProcessResult(
			status: process.terminationStatus,
			stdout: String(
				decoding: output.fileHandleForReading.readDataToEndOfFile(),
				as: UTF8.self
			),
			stderr: String(
				decoding: error.fileHandleForReading.readDataToEndOfFile(),
				as: UTF8.self
			)
		)
	}
}

private struct ProcessResult {
	let status: Int32
	let stdout: String
	let stderr: String
}

private enum CLIFixtureError: Error {
	case executableNotFound
	case secondSkillUnavailable
}
