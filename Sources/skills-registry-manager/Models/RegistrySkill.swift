import Foundation
import SkillsManager

public struct RegistrySkill: Codable, Equatable, Sendable {
	public let schemaVersion: String
	public let id: ID
	public let name: String
	public var displayName: String?
	public var description: String?
	public var source: SkillSource
	public var dependencies: [Dependency]
	public var digest: Digest
	public var links: [SkillLink]
	public let createdAt: Date
	public var updatedAt: Date

	public init(
		schemaVersion: String = "1.0",
		id: ID,
		name: String,
		displayName: String? = nil,
		description: String? = nil,
		source: SkillSource,
		dependencies: [Dependency] = [],
		digest: Digest,
		links: [SkillLink] = [],
		createdAt: Date,
		updatedAt: Date
	) {
		self.schemaVersion = schemaVersion
		self.id = id
		self.name = name
		self.displayName = displayName
		self.description = description
		self.source = source
		self.dependencies = dependencies
		self.digest = digest
		self.links = links
		self.createdAt = createdAt
		self.updatedAt = updatedAt
	}

	private enum CodingKeys: String, CodingKey {
		case schemaVersion = "schema_version"
		case id
		case name
		case displayName = "display_name"
		case description
		case source
		case dependencies
		case digest
		case links
		case createdAt = "created_at"
		case updatedAt = "updated_at"
	}
}

extension RegistrySkill {
	public struct ID: RawRepresentable, Codable, Equatable, Hashable, Sendable {
		public let rawValue: String

		public init?(rawValue: String) {
			guard
				let uuid = UUID(uuidString: rawValue),
				uuid.uuidString.lowercased() == rawValue
			else { return nil }

			self.rawValue = rawValue
		}

		public init(_ uuid: UUID) {
			self.rawValue = uuid.uuidString.lowercased()
		}

		public init(from decoder: any Decoder) throws {
			let value = try decoder.singleValueContainer().decode(String.self)
			guard let id = Self(rawValue: value) else {
				throw DecodingError.dataCorruptedError(
					in: try decoder.singleValueContainer(),
					debugDescription: "Registry skill IDs must be lowercase UUIDs."
				)
			}

			self = id
		}

		public func encode(to encoder: any Encoder) throws {
			var container = encoder.singleValueContainer()
			try container.encode(rawValue)
		}
	}

	public struct Dependency: Codable, Equatable, Hashable, Sendable {
		public enum Kind: String, Codable, Sendable {
			case embedded
			case mentioned
		}

		public let skillID: ID
		public let path: String
		public let kind: Kind

		public init(
			skillID: ID,
			path: String,
			kind: Kind = .embedded
		) {
			self.skillID = skillID
			self.path = path
			self.kind = kind
		}

		private enum CodingKeys: String, CodingKey {
			case skillID = "skill_id"
			case path
			case kind
		}

		public init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			self.init(
				skillID: try container.decode(ID.self, forKey: .skillID),
				path: try container.decode(String.self, forKey: .path),
				kind: try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .embedded
			)
		}
	}

	public struct Digest: Codable, Equatable, Sendable {
		public let algorithm: String
		public let hash: String

		public init(
			algorithm: String,
			hash: String
		) {
			self.algorithm = algorithm
			self.hash = hash
		}
	}
}

public struct SkillSource: Codable, Equatable, Hashable, Sendable {
	public let remote: URL?
	public let local: URL?
	public let revision: String?
	public let path: String

	public init(
		remote: URL? = nil,
		local: URL? = nil,
		revision: String? = nil,
		path: String = ""
	) throws {
		guard remote != nil || local != nil
		else { throw SkillsRegistryError.sourceIsMissing }
		if let local, !local.isFileURL || !local.path.hasPrefix("/") {
			throw SkillsRegistryError.localSourceMustBeAbsolute(local)
		}

		try Self.validate(path: path)
		self.remote = remote.map(Self.normalize)
		self.local = local.map(Self.normalize)
		self.revision = revision
		self.path = path
	}

	public var identifier: URL {
		let root = local ?? remote!
		return path.isEmpty ? root : root.appending(path: path)
	}

	private enum CodingKeys: String, CodingKey {
		case remote
		case local
		case revision
		case path
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		try self.init(
			remote: container.decodeIfPresent(
				URL.self,
				forKey: .remote
			),
			local: container.decodeIfPresent(
				URL.self,
				forKey: .local
			),
			revision: container.decodeIfPresent(
				String.self,
				forKey: .revision
			),
			path: container.decodeIfPresent(
				String.self,
				forKey: .path
			) ?? ""
		)
	}

	public func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encodeIfPresent(
			remote,
			forKey: .remote
		)
		try container.encodeIfPresent(
			local,
			forKey: .local
		)
		try container.encodeIfPresent(
			revision,
			forKey: .revision
		)
		try container.encode(
			path,
			forKey: .path
		)
	}

	public func appending(relativePath: String) throws -> Self {
		guard !relativePath.isEmpty else { return self }
		let path = [path, relativePath]
			.filter { !$0.isEmpty }
			.joined(separator: "/")
		return try .init(
			remote: remote,
			local: local,
			revision: revision,
			path: path
		)
	}

	internal func matches(_ other: Self) -> Bool {
		let lhs = Set([remote, local].compactMap { $0?.absoluteString })
		let rhs = Set([other.remote, other.local].compactMap { $0?.absoluteString })
		return path == other.path && !lhs.isDisjoint(with: rhs)
	}

	private static func validate(path: String) throws {
		guard !path.hasPrefix("/")
		else { throw SkillsRegistryError.invalidSourcePath(path) }

		let components = path.split(
			separator: "/",
			omittingEmptySubsequences: false
		)
		let isValidPath =
			path.isEmpty
			|| components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
		guard isValidPath
		else { throw SkillsRegistryError.invalidSourcePath(path) }
	}

	private static func normalize(_ url: URL) -> URL {
		if url.isFileURL {
			return url.resolvingSymlinksInPath().standardizedFileURL
		}

		var components = URLComponents(
			url: url,
			resolvingAgainstBaseURL: false
		)
		let host = components?.host?.lowercased()
		components?.host = host
		components?.fragment = nil
		if var path = components?.path, path.count > 1, path.hasSuffix("/") {
			path.removeLast()
			components?.path = path
		}
		return components?.url ?? url
	}
}
