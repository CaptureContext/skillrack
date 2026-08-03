import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct GitClient: Sendable {
	/// Clones a repository or handles an existing checkout according to `options`.
	public var clone: @Sendable (
		_: URL,
		_ to: GitCloneDestination,
		_ options: GitCloneOptions
	) async throws -> GitCheckout

	/// Returns the `origin` remote configured for a local repository, if present.
	public var remoteURL: @Sendable (_ repositoryURL: URL) async throws -> URL?

	/// Returns the full object name of `HEAD` for a local repository.
	public var revision: @Sendable (_ repositoryURL: URL) async throws -> String
}

extension GitClient {
	public static var live: Self {
		let service = LiveGitClient()

		return Self(
			clone: { remoteURL, destination, options in
				try await service.clone(
					remoteURL,
					to: destination,
					options: options
				)
			},
			remoteURL: { repositoryURL in
				try await service.remoteURL(in: repositoryURL)
			},
			revision: { repositoryURL in
				try await service.revision(in: repositoryURL)
			}
		)
	}
}

extension DependencyValues {
	private enum GitClientKey: DependencyKey {
		internal static var liveValue: GitClient { .live }
		internal static var testValue: GitClient { liveValue }
	}

	public var gitClient: GitClient {
		get { self[GitClientKey.self] }
		set { self[GitClientKey.self] = newValue }
	}
}

private struct LiveGitClient: Sendable {
	internal func clone(
		_ remoteURL: URL,
		to destination: GitCloneDestination,
		options: GitCloneOptions
	) async throws -> GitCheckout {
		let (localURL, lifetime) = try resolve(destination)
		let fileManager = FileManager.default

		if fileManager.fileExists(atPath: localURL.path) {
			switch options.resolvedCollisionStrategy {
			case .error:
				throw GitClientError.destinationAlreadyExists(localURL)

			case .clean:
				try fileManager.removeItem(at: localURL)

			case .pull:
				try await GitCommand.run(
					["-C", localURL.path, "pull", "--ff-only"],
					machineSafe: options.contains(.machineSafe)
				)
				return try await checkout(
					at: localURL,
					remoteURL: remoteURL,
					lifetime: lifetime
				)

			case .skip:
				return try await checkout(
					at: localURL,
					remoteURL: remoteURL,
					lifetime: lifetime
				)
			}
		}

		try fileManager.createDirectory(
			at: localURL.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)

		do {
			try await GitCommand.run(
				[
					"clone",
					remoteURL.absoluteString,
					localURL.path,
				],
				machineSafe: options.contains(.machineSafe)
			)
			return try await checkout(
				at: localURL,
				remoteURL: remoteURL,
				lifetime: lifetime
			)
		} catch {
			let shouldRemoveCheckout = lifetime == .scoped
			&& fileManager.fileExists(atPath: localURL.path)
			if shouldRemoveCheckout {
				try? fileManager.removeItem(at: localURL)
			}
			throw error
		}
	}

	internal func remoteURL(in repositoryURL: URL) async throws -> URL? {
		let repositoryURL = try validatedLocalURL(repositoryURL)
		do {
			let output = try await GitCommand.capture([
				"-C",
				repositoryURL.path,
				"config",
				"--get",
				"remote.origin.url",
			])
			guard !output.isEmpty else { return nil }

			if output.hasPrefix("/") {
				return URL(fileURLWithPath: output)
			}
			guard let remoteURL = URL(string: output) else {
				throw GitClientError.invalidCommandOutput(
					arguments: ["config", "--get", "remote.origin.url"],
					output: output
				)
			}

			return remoteURL
		} catch let error as GitClientError {
			if case let .commandFailed(_, exitCode, _) = error, exitCode == 1 {
				return nil
			}
			throw error
		}
	}

	internal func revision(in repositoryURL: URL) async throws -> String {
		let repositoryURL = try validatedLocalURL(repositoryURL)
		let arguments = ["-C", repositoryURL.path, "rev-parse", "HEAD"]
		let output = try await GitCommand.capture(arguments)
		guard !output.isEmpty else {
			throw GitClientError.invalidCommandOutput(
				arguments: arguments,
				output: output
			)
		}

		return output
	}

	private func checkout(
		at localURL: URL,
		remoteURL: URL,
		lifetime: GitCheckout.Lifetime
	) async throws -> GitCheckout {
		let revision = try await revision(in: localURL)
		return .init(
			localURL: localURL,
			remoteURL: remoteURL,
			revision: revision,
			lifetime: lifetime
		)
	}

	private func resolve(
		_ destination: GitCloneDestination
	) throws -> (URL, GitCheckout.Lifetime) {
		switch destination {
		case .temporaryDirectory:
			return (
				FileManager.default.temporaryDirectory
					.appending(
						path: "skillrack-git-\(UUID().uuidString.lowercased())",
						directoryHint: .isDirectory
					),
				.scoped
			)

		case let .local(url):
			return (try validatedLocalURL(url), .persistent)
		}
	}

	private func validatedLocalURL(_ url: URL) throws -> URL {
		guard url.isFileURL, url.path.hasPrefix("/") else {
			throw GitClientError.localURLMustBeAbsolute(url)
		}

		return url.standardizedFileURL
	}
}

private enum GitCommand {
	internal static func run(
		_ arguments: [String],
		machineSafe: Bool = false
	) async throws {
		let result = try await execute(
			arguments,
			captureOutput: machineSafe,
			disableTerminalPrompts: machineSafe
		)
		guard result.exitCode == 0 else {
			throw GitClientError.commandFailed(
				arguments: arguments,
				exitCode: result.exitCode,
				message: result.error
			)
		}
	}

	internal static func capture(_ arguments: [String]) async throws -> String {
		let result = try await execute(
			arguments,
			captureOutput: true,
			disableTerminalPrompts: false
		)
		guard result.exitCode == 0 else {
			throw GitClientError.commandFailed(
				arguments: arguments,
				exitCode: result.exitCode,
				message: result.error
			)
		}

		return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private static func execute(
		_ arguments: [String],
		captureOutput: Bool,
		disableTerminalPrompts: Bool
	) async throws -> Result {
		try await Task.detached {
			let process = Process()
			process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
			process.arguments = ["git"] + arguments
			if disableTerminalPrompts {
				process.environment = ProcessInfo.processInfo.environment.merging(
					["GIT_TERMINAL_PROMPT": "0"],
					uniquingKeysWith: { _, newValue in newValue }
				)
			}

			let captureDirectory = FileManager.default.temporaryDirectory.appending(
				path: "skillrack-git-output-\(UUID().uuidString.lowercased())",
				directoryHint: .isDirectory
			)
			let outputURL = captureDirectory.appending(path: "stdout")
			let errorURL = captureDirectory.appending(path: "stderr")
			var outputHandle: FileHandle?
			var errorHandle: FileHandle?
			if captureOutput {
				do {
					try FileManager.default.createDirectory(
						at: captureDirectory,
						withIntermediateDirectories: true
					)
					let createdOutput = FileManager.default.createFile(
						atPath: outputURL.path,
						contents: nil
					)
					let createdError = FileManager.default.createFile(
						atPath: errorURL.path,
						contents: nil
					)
					guard
						createdOutput,
						createdError
					else {
						throw CocoaError(.fileWriteUnknown)
					}

					let standardOutput = try FileHandle(forWritingTo: outputURL)
					let standardError = try FileHandle(forWritingTo: errorURL)
					outputHandle = standardOutput
					errorHandle = standardError
					process.standardOutput = standardOutput
					process.standardError = standardError
				} catch {
					try? FileManager.default.removeItem(at: captureDirectory)
					throw GitClientError.couldNotRunGit(String(describing: error))
				}
			}
			defer {
				try? outputHandle?.close()
				try? errorHandle?.close()
				if captureOutput { try? FileManager.default.removeItem(at: captureDirectory) }
			}

			do {
				try process.run()
				process.waitUntilExit()
			} catch {
				throw GitClientError.couldNotRunGit(String(describing: error))
			}
			try? outputHandle?.close()
			try? errorHandle?.close()

			let output = captureOutput
			? String(
				decoding: (try? Data(contentsOf: outputURL)) ?? Data(),
				as: UTF8.self
			)
			: ""
			let error = captureOutput
			? String(
				decoding: (try? Data(contentsOf: errorURL)) ?? Data(),
				as: UTF8.self
			)
				.trimmingCharacters(in: .whitespacesAndNewlines)
			: ""

			return Result(
				exitCode: process.terminationStatus,
				output: output,
				error: error
			)
		}.value
	}

	private struct Result: Sendable {
		internal let exitCode: Int32
		internal let output: String
		internal let error: String

		internal init(
			exitCode: Int32,
			output: String,
			error: String
		) {
			self.exitCode = exitCode
			self.output = output
			self.error = error
		}
	}
}
