import Foundation
import Parsing

internal struct SkillDocumentParser: ParserPrinter {
	internal struct Envelope {
		internal var frontmatter: Substring
		internal var body: Substring

		internal init(
			frontmatter: Substring,
			body: Substring
		) {
			self.frontmatter = frontmatter
			self.body = body
		}
	}

	internal let url: URL
	internal let fallbackName: String?

	internal init(
		url: URL,
		fallbackName: String?
	) {
		self.url = url
		self.fallbackName = fallbackName
	}

	internal func parse(_ input: inout Substring) throws -> SkillDocument {
		do {
			let envelope = try Self.envelopeParser.parse(&input)
			var frontmatterInput = envelope.frontmatter
			var properties = try SkillFrontmatterParser()
				.parse(&frontmatterInput)

			let parsedName = properties.removeValue(forKey: "name")
			guard let name = parsedName ?? fallbackName, !name.isEmpty else {
				throw SkillDocumentFormatError.missingName
			}

			var body = envelope.body
			if body.first?.isNewline == true {
				body.removeFirst()
			}

			return SkillDocument(
				name: name,
				description: properties.removeValue(forKey: "description"),
				properties: properties,
				body: String(body)
			)
		} catch let error as SkillsManagerError {
			throw error
		} catch {
			throw SkillsManagerError.invalidSkill(
				url,
				reason: Self.reason(for: error)
			)
		}
	}

	internal func print(
		_ output: SkillDocument,
		into input: inout Substring
	) throws {
		let frontmatter = try SkillFrontmatterPrinter().print(output)
		var body = output.body
		if !body.isEmpty {
			if !body.hasSuffix("\n") {
				body.append("\n")
			}
			body.insert(
				"\n",
				at: body.startIndex
			)
		}

		try Self.envelopeParser.print(
			Envelope(
				frontmatter: frontmatter[...],
				body: body[...]
			),
			into: &input
		)
	}

	private static var envelopeParser: some ParserPrinter<
		Substring,
		Envelope
	> {
		ParsePrint(
			input: Substring.self,
			.memberwise(Envelope.init(frontmatter:body:))
		) {
			"---\n"
			PrefixUpTo("\n---\n")
			"\n---\n"
			Prefix { _ in true }
		}
	}

	private static func reason(for error: Error) -> String {
		let description = (error as? LocalizedError)?.errorDescription
		if let description { return description }
		return "Invalid SKILL.md frontmatter: \(error)"
	}
}
