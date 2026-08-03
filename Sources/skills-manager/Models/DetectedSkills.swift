import Foundation

public struct DetectedSkills: Equatable, Sendable {
	public let rootURL: URL
	public let roots: [DetectedSkill.ID]
	public let skills: [DetectedSkill.ID: DetectedSkill]
	public let references: [Reference]

	public init(
		rootURL: URL,
		roots: [DetectedSkill.ID],
		skills: [DetectedSkill.ID: DetectedSkill],
		references: [Reference]
	) {
		self.rootURL = rootURL
		self.roots = roots
		self.skills = skills
		self.references = references
	}

	public func dependencies(
		of skillID: DetectedSkill.ID
	) -> [Reference] {
		references
			.filter { $0.parent == skillID }
			.sorted { lhs, rhs in
				if lhs.path == rhs.path {
					return lhs.dependency.rawValue < rhs.dependency.rawValue
				}
				return lhs.path < rhs.path
			}
	}
}

extension DetectedSkills {
	public struct Reference: Equatable, Hashable, Sendable {
		public enum Kind: String, Equatable, Hashable, Sendable {
			case embedded
			case mentioned
		}

		public let parent: DetectedSkill.ID
		public let dependency: DetectedSkill.ID
		public let path: String
		public let kind: Kind

		public init(
			parent: DetectedSkill.ID,
			dependency: DetectedSkill.ID,
			path: String,
			kind: Kind = .embedded
		) {
			self.parent = parent
			self.dependency = dependency
			self.path = path
			self.kind = kind
		}
	}
}

public struct DetectedSkill: Equatable, Sendable {
	public let id: ID
	public let url: URL
	public let relativePath: String
	public let skill: Skill

	public init(
		id: ID,
		url: URL,
		relativePath: String,
		skill: Skill
	) {
		self.id = id
		self.url = url
		self.relativePath = relativePath
		self.skill = skill
	}
}

extension DetectedSkill {
	public struct ID: RawRepresentable, Codable, Equatable, Hashable, Sendable {
		public let rawValue: String

		public init(rawValue: String) {
			self.rawValue = rawValue
		}

		public init(url: URL) {
			self.rawValue = url
				.resolvingSymlinksInPath()
				.standardizedFileURL
				.absoluteString
		}
	}
}
