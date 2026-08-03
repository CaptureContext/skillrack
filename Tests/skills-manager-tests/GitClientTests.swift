import Foundation
import Testing

@testable import SkillsManager

@Suite
struct GitClientTests {
	@Test
	func clonesIntoPersistentDirectoryAndReadsProvenance() async throws {
		let fixture = try GitFixture()
		defer { fixture.remove() }

		let destinationURL = fixture.rootURL.appending(path: "checkout")
		let client = GitClient.live
		let checkout = try await client.clone(
			fixture.repositoryURL,
			to: .local(destinationURL),
			options: []
		)
		let sourceRevision = try fixture.revision()

		#expect(checkout.localURL.path == destinationURL.standardizedFileURL.path)
		#expect(checkout.remoteURL == fixture.repositoryURL)
		#expect(checkout.lifetime == .persistent)
		#expect(checkout.revision == sourceRevision)
		#expect(
			FileManager.default.fileExists(
				atPath: destinationURL.appending(path: "SKILL.md").path
			)
		)
		#expect(
			try await client.remoteURL(destinationURL)?.standardizedFileURL
				== fixture.repositoryURL.standardizedFileURL
		)
		#expect(try await client.revision(destinationURL) == checkout.revision)
	}

	@Test
	func createsMachineSafeScopedCheckoutWhenDestinationIsTemporary() async throws {
		let fixture = try GitFixture()
		defer { fixture.remove() }

		let checkout = try await GitClient.live.clone(
			fixture.repositoryURL,
			to: .temporaryDirectory,
			options: [.machineSafe]
		)
		defer { try? FileManager.default.removeItem(at: checkout.localURL) }

		#expect(checkout.lifetime == .scoped)
		#expect(checkout.localURL.lastPathComponent.hasPrefix("skillrack-git-"))
		#expect(FileManager.default.fileExists(atPath: checkout.localURL.path))
	}

	@Test
	func errorsWhenPersistentDestinationAlreadyExistsByDefault() async throws {
		let fixture = try GitFixture()
		defer { fixture.remove() }

		let destinationURL = fixture.rootURL.appending(path: "checkout")
		try FileManager.default.createDirectory(
			at: destinationURL,
			withIntermediateDirectories: true
		)

		await #expect(
			throws: GitClientError.destinationAlreadyExists(
				destinationURL.standardizedFileURL
			)
		) {
			try await GitClient.live.clone(
				fixture.repositoryURL,
				to: .local(destinationURL),
				options: []
			)
		}
	}

	@Test
	func cleanCollisionStrategyReplacesExistingDestination() async throws {
		let fixture = try GitFixture()
		defer { fixture.remove() }

		let destinationURL = fixture.rootURL.appending(path: "checkout")
		try FileManager.default.createDirectory(
			at: destinationURL,
			withIntermediateDirectories: true
		)
		let markerURL = destinationURL.appending(path: "marker")
		try Data().write(to: markerURL)

		let checkout = try await GitClient.live.clone(
			fixture.repositoryURL,
			to: .local(destinationURL),
			options: [.collisionStrategy(.clean)]
		)

		#expect(checkout.lifetime == .persistent)
		#expect(!FileManager.default.fileExists(atPath: markerURL.path))
		#expect(
			FileManager.default.fileExists(
				atPath: destinationURL.appending(path: "SKILL.md").path
			)
		)
	}

	@Test
	func skipCollisionStrategyUsesExistingCheckout() async throws {
		let fixture = try GitFixture()
		defer { fixture.remove() }

		let destinationURL = fixture.rootURL.appending(path: "checkout")
		let client = GitClient.live
		_ = try await client.clone(
			fixture.repositoryURL,
			to: .local(destinationURL),
			options: []
		)
		let markerURL = destinationURL.appending(path: "marker")
		try Data().write(to: markerURL)

		let checkout = try await client.clone(
			fixture.repositoryURL,
			to: .local(destinationURL),
			options: [.collisionStrategy(.skip)]
		)
		let sourceRevision = try fixture.revision()

		#expect(checkout.revision == sourceRevision)
		#expect(FileManager.default.fileExists(atPath: markerURL.path))
	}

	@Test
	func pullCollisionStrategyFastForwardsExistingCheckout() async throws {
		let fixture = try GitFixture()
		defer { fixture.remove() }

		let destinationURL = fixture.rootURL.appending(path: "checkout")
		let client = GitClient.live
		_ = try await client.clone(
			fixture.repositoryURL,
			to: .local(destinationURL),
			options: []
		)

		let addedURL = fixture.repositoryURL.appending(path: "added.txt")
		try Data("new".utf8).write(to: addedURL)
		try fixture.commit("Add attachment")

		let checkout = try await client.clone(
			fixture.repositoryURL,
			to: .local(destinationURL),
			options: [.collisionStrategy(.pull), .machineSafe]
		)
		let sourceRevision = try fixture.revision()

		#expect(checkout.revision == sourceRevision)
		#expect(
			FileManager.default.fileExists(
				atPath: destinationURL.appending(path: "added.txt").path
			)
		)
	}

	@Test
	func collisionStrategyUsesDocumentedPriority() {
		let options: GitCloneOptions = [
			.collisionStrategy(.clean),
			.collisionStrategy(.pull),
			.collisionStrategy(.skip),
		]

		#expect(options.resolvedCollisionStrategy == .skip)
		#expect(GitCloneOptions().resolvedCollisionStrategy == .error)
	}
}

private struct GitFixture {
	let rootURL: URL
	let repositoryURL: URL

	init() throws {
		rootURL = FileManager.default.temporaryDirectory.appending(
			path: "git-client-tests-\(UUID().uuidString.lowercased())",
			directoryHint: .isDirectory
		)
		repositoryURL = rootURL.appending(
			path: "source",
			directoryHint: .isDirectory
		)

		try FileManager.default.createDirectory(
			at: rootURL,
			withIntermediateDirectories: true
		)
		try runGit(["init", "--initial-branch", "main", repositoryURL.path])
		try runGit(["-C", repositoryURL.path, "config", "user.name", "Skills CLI Tests"])
		try runGit([
			"-C",
			repositoryURL.path,
			"config",
			"user.email",
			"skillrack-tests@example.com",
		])

		try Data(
			"""
			---
			name: example
			description: Example skill.
			---
			""".utf8
		).write(to: repositoryURL.appending(path: "SKILL.md"))
		try commit("Initial commit")
	}

	func commit(_ message: String) throws {
		try runGit(["-C", repositoryURL.path, "add", "."])
		try runGit(["-C", repositoryURL.path, "commit", "--quiet", "-m", message])
	}

	func revision() throws -> String {
		try runGit(["-C", repositoryURL.path, "rev-parse", "HEAD"])
	}

	func remove() {
		try? FileManager.default.removeItem(at: rootURL)
	}
}

@discardableResult
private func runGit(_ arguments: [String]) throws -> String {
	let process = Process()
	let output = Pipe()
	process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
	process.arguments = ["git"] + arguments
	process.standardOutput = output
	process.standardError = output

	try process.run()
	process.waitUntilExit()
	let message = String(
		decoding: output.fileHandleForReading.readDataToEndOfFile(),
		as: UTF8.self
	).trimmingCharacters(in: .whitespacesAndNewlines)

	guard process.terminationStatus == 0 else {
		throw GitFixtureError.commandFailed(
			arguments: arguments,
			exitCode: process.terminationStatus,
			message: message
		)
	}
	return message
}

private enum GitFixtureError: Error {
	case commandFailed(arguments: [String], exitCode: Int32, message: String)
}
