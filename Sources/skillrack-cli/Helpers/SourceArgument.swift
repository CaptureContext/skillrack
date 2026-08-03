import ArgumentParser
import Foundation

internal enum SourceArgument: Equatable, Sendable {
	case local(URL)
	case remote(URL)

	internal init(
		_ rawValue: String,
		currentDirectory: String,
		homeDirectory: URL
	) throws {
		let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !value.isEmpty else {
			throw ValidationError("A skill source is required.")
		}

		if value == "~" || value.hasPrefix("~/") {
			self = .local(
				expandedAbsoluteFileURL(
					value,
					currentDirectory: currentDirectory,
					homeDirectory: homeDirectory
				)
			)
			return
		}

		guard let components = URLComponents(string: value) else {
			throw CLIError(
				code: "unsupported_source",
				message: "Invalid skill source: \(value)"
			)
		}

		guard let scheme = components.scheme?.lowercased() else {
			guard !value.contains(":") else {
				throw CLIError(
					code: "unsupported_source",
					message: "SCP-like Git sources are not supported. Use an ssh:// URL."
				)
			}
			self = .local(
				expandedAbsoluteFileURL(
					value,
					currentDirectory: currentDirectory,
					homeDirectory: homeDirectory
				)
			)
			return
		}

		guard let url = components.url, url.scheme != nil else {
			throw CLIError(
				code: "unsupported_source",
				message: "Invalid skill source: \(value)"
			)
		}

		if scheme == "file" {
			guard url.isFileURL, url.path.hasPrefix("/") else {
				throw CLIError(
					code: "unsupported_source",
					message: "Local file URLs must be absolute."
				)
			}

			self = .local(url.standardizedFileURL)
			return
		}
		guard ["https", "http", "ssh", "git"].contains(scheme), url.host != nil else {
			throw CLIError(
				code: "unsupported_source",
				message: "Unsupported skill source URL scheme '\(scheme)'."
			)
		}

		self = .remote(url)
	}
}
