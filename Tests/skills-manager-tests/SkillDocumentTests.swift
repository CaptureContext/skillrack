import Foundation
import Testing

@testable import SkillsManager

@Suite
struct SkillDocumentTests {
	@Test
	func parsesFocusedFrontmatterAndOpaqueBody() throws {
		let url = URL(fileURLWithPath: "/skills/example/SKILL.md")
		let document = try SkillDocument(
			data: Data(
				"""
				---
				name: example-skill
				description: "Use tools: safely"
				license: MIT
				allowed-tools: "Bash(git:*)"
				metadata:
				  author: CaptureContext
				  version: '1.0'
				---

				# Example
				""".utf8
			),
			url: url
		)

		#expect(document.name == "example-skill")
		#expect(document.description == "Use tools: safely")
		#expect(
			document.properties == [
				"allowed-tools": "Bash(git:*)",
				"license": "MIT",
				"metadata.author": "CaptureContext",
				"metadata.version": "1.0",
			]
		)
		#expect(document.body == "# Example\n")
	}

	@Test
	func parserPrinterProducesCanonicalRoundTrip() throws {
		let original = SkillDocument(
			skill: Skill(
				name: "example-skill",
				description: "Use tools: safely",
				properties: [
					"license": "MIT",
					"allowed-tools": "Bash(git:*)",
					"metadata.version": "1.0",
					"metadata.author": "CaptureContext",
				],
				body: "# Example"
			)
		)

		let data = try original.data()
		#expect(
			String(decoding: data, as: UTF8.self) ==
				"""
				---
				name: example-skill
				description: "Use tools: safely"
				allowed-tools: "Bash(git:*)"
				license: MIT
				metadata:
				  author: CaptureContext
				  version: 1.0
				---

				# Example

				"""
		)

		let parsed = try SkillDocument(
			data: data,
			url: URL(fileURLWithPath: "/skills/example/SKILL.md")
		)
		#expect(parsed.name == original.name)
		#expect(parsed.description == original.description)
		#expect(parsed.properties == original.properties)
		#expect(parsed.body == "# Example\n")
	}
}
