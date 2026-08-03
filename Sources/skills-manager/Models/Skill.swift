import Foundation

public struct Skill: Equatable, Sendable {
	public var name: String
	public var description: String?
	public var properties: [String: String]
	public var body: String
	public var attachments: [Attachment]

	public init(
		name: String,
		description: String?,
		properties: [String: String] = [:],
		body: String = "",
		attachments: [Attachment] = []
	) {
		self.name = name
		self.description = description
		self.properties = properties
		self.body = body
		self.attachments = attachments
	}
}

extension Skill {
	public struct Descriptor: Equatable, Hashable, Sendable {
		public let url: URL
		public let name: String
		public let description: String?

		public init(
			url: URL,
			name: String,
			description: String?
		) {
			self.url = url
			self.name = name
			self.description = description
		}
	}

	public struct Attachment: Equatable, Sendable {
		public let name: String
		public let content: Content

		public init(
			name: String,
			content: Content
		) {
			self.name = name
			self.content = content
		}

		public enum Content: Equatable, Sendable {
			case data(Data)
			case group([Attachment])
		}

		public static func file(
			name: String,
			data: Data
		) -> Self {
			.init(
				name: name,
				content: .data(data)
			)
		}

		public static func group(
			name: String,
			contents: [Self]
		) -> Self {
			.init(
				name: name,
				content: .group(contents)
			)
		}
	}
}
