import Foundation

public enum GitCloneDestination: Equatable, Sendable {
	/// Generates a unique checkout directory whose lifetime is scoped to the operation.
	case temporaryDirectory

	/// Uses a caller-provided checkout directory that remains after the operation.
	case local(URL)
}

public enum GitCloneCollisionStrategy: Equatable, Sendable {
	/// Fails when the destination already exists.
	case error

	/// Removes the existing destination before cloning a fresh checkout.
	case clean

	/// Fast-forwards the existing checkout with `git pull --ff-only`.
	case pull

	/// Uses the existing checkout without fetching or changing it.
	case skip
}

public struct GitCloneOptions: OptionSet, Equatable, Sendable {
	public let rawValue: UInt8

	/// Captures subprocess output and disables interactive Git credential prompts.
	public static let machineSafe: Self = .init(rawValue: 1 << 4)

	public init(rawValue: UInt8) {
		self.rawValue = rawValue
	}

	/// Resolves combined strategies as `skip`, `pull`, `clean`, then `error`.
	internal var resolvedCollisionStrategy: GitCloneCollisionStrategy {
		if contains(.collisionStrategy(.skip)) {
			return .skip
		}
		if contains(.collisionStrategy(.pull)) {
			return .pull
		}
		if contains(.collisionStrategy(.clean)) {
			return .clean
		}
		return .error
	}

	public static func collisionStrategy(
		_ strategy: GitCloneCollisionStrategy
	) -> Self {
		switch strategy {
		case .error:
			[]
		case .clean:
			.init(rawValue: 1 << 1)
		case .pull:
			.init(rawValue: 1 << 2)
		case .skip:
			.init(rawValue: 1 << 3)
		}
	}
}

public struct GitCheckout: Equatable, Sendable {
	public enum Lifetime: Equatable, Sendable {
		case scoped
		case persistent
	}

	public let localURL: URL
	public let remoteURL: URL
	public let revision: String
	public let lifetime: Lifetime

	public init(
		localURL: URL,
		remoteURL: URL,
		revision: String,
		lifetime: Lifetime
	) {
		self.localURL = localURL
		self.remoteURL = remoteURL
		self.revision = revision
		self.lifetime = lifetime
	}
}

public enum GitClientError: Error, Equatable, Sendable {
	case localURLMustBeAbsolute(URL)
	case destinationAlreadyExists(URL)
	case couldNotRunGit(String)
	case commandFailed(arguments: [String], exitCode: Int32, message: String)
	case invalidCommandOutput(arguments: [String], output: String)
}

extension GitClientError: LocalizedError {
	public var errorDescription: String? {
		switch self {
		case let .localURLMustBeAbsolute(url):
			"Git checkout locations must be absolute file URLs: \(url.absoluteString)"

		case let .destinationAlreadyExists(url):
			"A file or directory already exists at \(url.path)."

		case let .couldNotRunGit(message):
			"Could not run git: \(message)"

		case let .commandFailed(arguments, exitCode, message):
			if message.isEmpty {
				"git \(arguments.joined(separator: " ")) failed with exit code \(exitCode)."
			} else {
				"git \(arguments.joined(separator: " ")) failed with exit code \(exitCode): \(message)"
			}

		case let .invalidCommandOutput(arguments, output):
			"git \(arguments.joined(separator: " ")) returned invalid output: \(output)"
		}
	}
}
