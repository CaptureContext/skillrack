import Foundation

internal enum SkillDocumentFormatError: LocalizedError {
	case emptyKey
	case invalidKey(String)
	case invalidLine(String)
	case invalidQuotedScalar(String)
	case missingName
	case missingValue(String)
	case unsupportedNestedKey(String)

	internal var errorDescription: String? {
		switch self {
		case .emptyKey:
			"Frontmatter contains an empty key."
		case let .invalidKey(key):
			"Frontmatter key '\(key)' cannot be serialized."
		case let .invalidLine(line):
			"Invalid frontmatter line '\(line)'."
		case let .invalidQuotedScalar(value):
			"Invalid quoted frontmatter value \(value)."
		case .missingName:
			"Frontmatter is missing its name."
		case let .missingValue(key):
			"Frontmatter key '\(key)' has no scalar value."
		case let .unsupportedNestedKey(key):
			"Nested frontmatter key '\(key)' is only supported inside metadata."
		}
	}
}
