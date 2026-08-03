import Foundation

public enum SkillsManagerError: Error, Equatable, Sendable {
	case unsupportedURL(URL)
	case invalidSkill(URL, reason: String)
	case invalidSkillName(String)
	case invalidAttachmentName(String)
	case destinationAlreadyExists(URL)
	case remoteSkillIsReadOnly(URL)
	case truncatedGitHubRepository(URL)
}

extension SkillsManagerError: LocalizedError {
	public var errorDescription: String? {
		switch self {
		case let .unsupportedURL(url):
			"Unsupported skills URL: \(url.absoluteString)"
		case let .invalidSkill(url, reason):
			"Invalid skill at \(url.absoluteString): \(reason)"
		case let .invalidSkillName(name):
			"Invalid skill name '\(name)'. Use 1–64 lowercase letters, numbers, and single hyphens."
		case let .invalidAttachmentName(name):
			"Invalid skill attachment name '\(name)'."
		case let .destinationAlreadyExists(url):
			"A file or directory already exists at \(url.path)."
		case let .remoteSkillIsReadOnly(url):
			"Remote skill \(url.absoluteString) is read-only."
		case let .truncatedGitHubRepository(url):
			"GitHub truncated the repository tree for \(url.absoluteString)."
		}
	}
}
