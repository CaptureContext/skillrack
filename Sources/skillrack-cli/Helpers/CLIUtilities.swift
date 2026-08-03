import ArgumentParser
import Foundation
import SkillsManager
import SkillsRegistryManager

internal let machineEncodingFailureResponse: String = """
{
  "api_version": 1,
  "error": {
    "code": "encoding_failed",
    "message": "Unable to encode the error response."
  },
  "ok": false
}
"""

internal func machineOutputRequested(_ localValue: Bool?) throws -> Bool {
	if let localValue { return localValue }
	return try globalMachineOutputRequested()
}

internal func globalMachineOutputRequested(
	arguments: [String] = Array(CommandLine.arguments.dropFirst()),
	environment: [String: String] = ProcessInfo.processInfo.environment
) throws -> Bool {
	var argumentValue: Bool?
	for argument in arguments {
		switch argument {
		case "--json": argumentValue = true
		case "--no-json": argumentValue = false
		default: break
		}
	}
	if let argumentValue { return argumentValue }
	return try environmentSwitch(
		named: "SKILLRACK_JSON",
		in: environment
	) ?? false
}

internal func machineOutputRequestedForError(
	arguments: [String] = Array(CommandLine.arguments.dropFirst()),
	environment: [String: String] = ProcessInfo.processInfo.environment
) -> Bool {
	let explicit = try? globalMachineOutputRequested(
		arguments: arguments,
		environment: environment
	)
	if let explicit { return explicit }
	return environment["SKILLRACK_JSON"] == "1"
}

internal func environmentSwitch(
	named name: String,
	in environment: [String: String]
) throws -> Bool? {
	guard let value = environment[name], !value.isEmpty else { return nil }
	switch value {
	case "1": return true
	case "-1", "0": return false
	default:
		throw ValidationError("Environment variable \(name) must be 1, -1, 0, or unset.")
	}
}

internal func encodedJSON<Value: Encodable>(_ value: Value) throws -> Data {
	let encoder = JSONEncoder()
	encoder.keyEncodingStrategy = .convertToSnakeCase
	encoder.dateEncodingStrategy = .iso8601
	encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
	return try encoder.encode(value)
}

internal func printMachineResponse<Value: Encodable>(_ value: Value) throws {
	try writeJSON(
		MachineResponse(data: value),
		to: .standardOutput
	)
}

internal func printMachineError(_ error: any Error) throws {
	try writeJSON(
		MachineErrorResponse(error: error),
		to: .standardError
	)
}

private func writeJSON<Value: Encodable>(
	_ value: Value,
	to fileHandle: FileHandle
) throws {
	var data = try encodedJSON(value)
	data.append(0x0A)
	try fileHandle.write(contentsOf: data)
}

internal func expandedAbsoluteFileURL(
	_ value: String,
	currentDirectory: String,
	homeDirectory: URL
) -> URL {
	let expanded: String
	if value == "~" {
		expanded = homeDirectory.path
	} else if value.hasPrefix("~/") {
		expanded = homeDirectory.appending(path: String(value.dropFirst(2))).path
	} else {
		expanded = value
	}
	if expanded.hasPrefix("/") {
		return URL(fileURLWithPath: expanded).standardizedFileURL
	}
	return URL(fileURLWithPath: currentDirectory)
		.appending(path: expanded)
		.standardizedFileURL
}

internal func uniqued<Value: Hashable>(_ values: [Value]) -> [Value] {
	var seen: Set<Value> = []
	return values.filter { seen.insert($0).inserted }
}

internal struct CLIError: Error, LocalizedError, Sendable {
	internal let code: String
	internal let message: String

	internal init(
		code: String,
		message: String
	) {
		self.code = code
		self.message = message
	}

	internal var errorDescription: String? { message }
}

internal func redactedMessage(for error: any Error) -> String {
	let raw = (error as? LocalizedError)?.errorDescription
		?? AppCommand.message(for: error)
	return redactCredentials(in: raw)
}

internal func redactCredentials(in value: String) -> String {
	guard
		let expression = try? NSRegularExpression(
			pattern: #"([A-Za-z][A-Za-z0-9+.-]*://)([^/@\s]+)@"#
		)
	else { return value }

	let range = NSRange(
		value.startIndex...,
		in: value
	)
	return expression.stringByReplacingMatches(
		in: value,
		range: range,
		withTemplate: "$1[redacted]@"
	)
}

internal func errorCode(for error: any Error) -> String {
	if let error = error as? CLIError { return error.code }
	if error is ValidationError { return "invalid_arguments" }
	if error is GitClientError { return "git_failed" }
	if let error = error as? SkillsManagerError {
		switch error {
		case .unsupportedURL: return "unsupported_source"
		case .invalidSkill, .invalidSkillName, .invalidAttachmentName: return "invalid_skill"
		case .destinationAlreadyExists: return "link_collision"
		case .remoteSkillIsReadOnly, .truncatedGitHubRepository: return "system_error"
		}
	}
	if let error = error as? SkillsRegistryError {
		switch error {
		case .skillNotFound: return "skill_not_found"
		case .skillAlreadyInstalled: return "skill_already_installed"
		case .dependencyCycle, .unresolvedDependency, .dependencyNotInstalled,
				 .skillHasDependents, .skillHasLinks:
			return "dependency_conflict"
		case .linkCollision, .linkDoesNotBelongToRegistry, .invalidAlias:
			return "link_collision"
		case .invalidStorage, .unsupportedSchemaVersion, .invalidRegistrySkillID:
			return "registry_invalid"
		case .resolutionDoesNotMatchSource:
			return "source_conflict"
		case .sourceIsMissing, .localSourceMustBeAbsolute, .invalidSourcePath,
				 .invalidDependencyPath:
			return "invalid_arguments"
		}
	}
	if error is POSIXError || error is CocoaError { return "system_error" }
	return "internal_error"
}

extension Tool: ExpressibleByArgument {}
