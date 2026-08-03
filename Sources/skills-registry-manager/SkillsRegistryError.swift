import Foundation

public enum SkillsRegistryError: Error, Equatable, Sendable {
	case sourceIsMissing
	case localSourceMustBeAbsolute(URL)
	case invalidSourcePath(String)
	case invalidRegistrySkillID(String)
	case invalidAlias(String)
	case invalidDependencyPath(String)
	case dependencyCycle([String])
	case unresolvedDependency(String)
	case resolutionDoesNotMatchSource(RegistrySkill.ID)
	case skillAlreadyInstalled(RegistrySkill.ID)
	case skillNotFound(RegistrySkill.ID)
	case dependencyNotInstalled(RegistrySkill.ID)
	case skillHasDependents(RegistrySkill.ID, [RegistrySkill.ID])
	case skillHasLinks(RegistrySkill.ID)
	case linkCollision(URL)
	case linkDoesNotBelongToRegistry(URL)
	case unsupportedSchemaVersion(String)
	case invalidStorage(String)
}

extension SkillsRegistryError: LocalizedError {
	public var errorDescription: String? {
		switch self {
		case .sourceIsMissing:
			"A skill source must have at least one remote or local URL."
		case let .localSourceMustBeAbsolute(url):
			"Local skill source must be an absolute file URL: \(url.absoluteString)"
		case let .invalidSourcePath(path):
			"Skill source path must be normalized and relative: \(path)"
		case let .invalidRegistrySkillID(value):
			"Registry skill ID is not a lowercase UUID: \(value)"
		case let .invalidAlias(alias):
			"Invalid skill link alias: \(alias)"
		case let .invalidDependencyPath(path):
			"Invalid skill dependency path: \(path)"
		case let .dependencyCycle(ids):
			"Skill dependency cycle: \(ids.joined(separator: " -> "))"
		case let .unresolvedDependency(id):
			"Skill dependency was not resolved: \(id)"
		case let .resolutionDoesNotMatchSource(id):
			"Registry skill \(id.rawValue) does not match the detected source."
		case let .skillAlreadyInstalled(id):
			"Skill source is already installed as \(id.rawValue)."
		case let .skillNotFound(id):
			"Registry skill was not found: \(id.rawValue)"
		case let .dependencyNotInstalled(id):
			"Registry dependency is not installed: \(id.rawValue)"
		case let .skillHasDependents(id, dependents):
			"Skill \(id.rawValue) is required by: \(dependents.map(\.rawValue).joined(separator: ", "))"
		case let .skillHasLinks(id):
			"Skill \(id.rawValue) still has tool links."
		case let .linkCollision(url):
			"A file or directory already exists at \(url.path)."
		case let .linkDoesNotBelongToRegistry(url):
			"The link at \(url.path) is missing or points outside the registry."
		case let .unsupportedSchemaVersion(version):
			"Unsupported skills registry schema version: \(version)"
		case let .invalidStorage(reason):
			"Invalid skills registry storage: \(reason)"
		}
	}
}
