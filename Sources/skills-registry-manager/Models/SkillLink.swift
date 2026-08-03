import Foundation
import SkillsManager

public enum LinkTarget: Codable, Equatable, Hashable, Sendable {
	case tool(Tool)
	case directory(URL)

	private enum CodingKeys: String, CodingKey {
		case kind
		case value
	}

	private enum Kind: String, Codable {
		case tool
		case directory
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		switch try container.decode(
			Kind.self,
			forKey: .kind
		) {
		case .tool:
			self = .tool(
				try container.decode(
					Tool.self,
					forKey: .value
				)
			)

		case .directory:
			let url = try container.decode(
				URL.self,
				forKey: .value
			)
			guard url.isFileURL, url.path.hasPrefix("/") else {
				throw DecodingError.dataCorruptedError(
					forKey: .value,
					in: container,
					debugDescription: "Link directories must be absolute file URLs."
				)
			}

			self = .directory(url.standardizedFileURL)
		}
	}

	public func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		switch self {
		case let .tool(tool):
			try container.encode(
				Kind.tool,
				forKey: .kind
			)
			try container.encode(
				tool,
				forKey: .value
			)

		case let .directory(url):
			try container.encode(
				Kind.directory,
				forKey: .kind
			)
			try container.encode(
				url,
				forKey: .value
			)
		}
	}
}

public struct SkillLink: Codable, Equatable, Hashable, Sendable {
	public let skillID: RegistrySkill.ID
	public let target: LinkTarget
	public let alias: String

	public init(
		skillID: RegistrySkill.ID,
		target: LinkTarget,
		alias: String
	) {
		self.skillID = skillID
		self.target = target
		self.alias = alias
	}

	private enum CodingKeys: String, CodingKey {
		case skillID = "skill_id"
		case target
		case alias
	}
}
