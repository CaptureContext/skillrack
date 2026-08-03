import Foundation

public enum Tool: String, CaseIterable, Codable, Hashable, Sendable {
	case agents
	case amp
	case antigravity
	case claude
	case codex
	case copilot
	case cursor
	case droid
	case gemini
	case kiro
	case kimi
	case opencode
	case pi
	case xcodeClaude = "xcode:claude"
	case xcodeCodex = "xcode:codex"
	case xcodeGemini = "xcode:gemini"
}

extension Tool {
	public func skillsDirectoryURL(
		relativeTo homeDirectoryURL: URL
	) -> URL {
		switch self {
		case .agents, .amp:
			homeDirectoryURL.appending(path: ".agents/skills")

		case .antigravity:
			homeDirectoryURL.appending(path: ".gemini/antigravity/skills")

		case .droid:
			homeDirectoryURL.appending(path: ".factory/skills")

		case .opencode:
			homeDirectoryURL.appending(path: ".config/opencode/skills")

		case .pi:
			homeDirectoryURL.appending(path: ".pi/agent/skills")

		case .xcodeClaude:
				homeDirectoryURL.appending(
				path: "Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig/skills"
			)

		case .xcodeCodex:
				homeDirectoryURL.appending(
				path: "Library/Developer/Xcode/CodingAssistant/codex/skills"
			)

		case .xcodeGemini:
				homeDirectoryURL.appending(
				path: "Library/Developer/Xcode/CodingAssistant/gemini/.gemini/skills"
			)

		default:
			homeDirectoryURL.appending(path: ".\(rawValue)/skills")
		}
	}
}
