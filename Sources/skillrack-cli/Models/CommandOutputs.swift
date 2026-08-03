import Foundation
import SkillsRegistryManager

internal struct VersionOutput: Encodable {
	internal let version: String

	internal init(version: String) {
		self.version = version
	}
}

internal struct SkillSourceOutput: Encodable {
	internal let remote: String?
	internal let local: String?
	internal let revision: String?
	internal let path: String

	internal init(_ source: SkillSource) {
		self.remote = source.remote?.absoluteString
		self.local = source.local?.path
		self.revision = source.revision
		self.path = source.path
	}
}

internal struct SkillDependencyOutput: Encodable {
	internal let skillID: String
	internal let path: String
	internal let kind: String

	internal init(_ dependency: RegistrySkill.Dependency) {
		self.skillID = dependency.skillID.rawValue
		self.path = dependency.path
		self.kind = dependency.kind.rawValue
	}
}

internal struct SkillLinkOutput: Encodable, Equatable {
	internal let skillID: String
	internal let targetKind: String
	internal let target: String
	internal let alias: String

	internal init(_ link: SkillLink) {
		self.skillID = link.skillID.rawValue
		self.alias = link.alias
		switch link.target {
		case .tool(let tool):
			self.targetKind = "tool"
			self.target = tool.rawValue

		case .directory(let url):
			self.targetKind = "directory"
			self.target = url.path
		}
	}
}

internal struct SkillDigestOutput: Encodable {
	internal let algorithm: String
	internal let hash: String

	internal init(_ digest: RegistrySkill.Digest) {
		self.algorithm = digest.algorithm
		self.hash = digest.hash
	}
}

internal struct RegistrySkillOutput: Encodable {
	internal let id: String
	internal let name: String
	internal let displayName: String?
	internal let description: String?
	internal let source: SkillSourceOutput
	internal let dependencies: [SkillDependencyOutput]
	internal let digest: SkillDigestOutput
	internal let links: [SkillLinkOutput]
	internal let createdAt: Date
	internal let updatedAt: Date

	internal init(_ skill: RegistrySkill) {
		self.id = skill.id.rawValue
		self.name = skill.name
		self.displayName = skill.displayName
		self.description = skill.description
		self.source = SkillSourceOutput(skill.source)
		self.dependencies = skill.dependencies.map(SkillDependencyOutput.init)
		self.digest = SkillDigestOutput(skill.digest)
		self.links = skill.links.map(SkillLinkOutput.init)
		self.createdAt = skill.createdAt
		self.updatedAt = skill.updatedAt
	}
}

internal struct ListOutput: Encodable {
	internal let skills: [RegistrySkillOutput]

	internal init(skills: [RegistrySkillOutput]) {
		self.skills = skills
	}
}

internal struct InstallOutput: Encodable {
	internal let roots: [RegistrySkillOutput]
	internal let installed: [RegistrySkillOutput]
	internal let updated: [RegistrySkillOutput]
	internal let reused: [RegistrySkillOutput]
	internal let source: SkillSourceOutput
	internal let checkoutRevision: String?
	internal let persistentCheckoutPath: String?
	internal let warnings: [String]

	internal init(
		roots: [RegistrySkillOutput],
		installed: [RegistrySkillOutput],
		updated: [RegistrySkillOutput],
		reused: [RegistrySkillOutput],
		source: SkillSourceOutput,
		checkoutRevision: String?,
		persistentCheckoutPath: String?,
		warnings: [String]
	) {
		self.roots = roots
		self.installed = installed
		self.updated = updated
		self.reused = reused
		self.source = source
		self.checkoutRevision = checkoutRevision
		self.persistentCheckoutPath = persistentCheckoutPath
		self.warnings = warnings
	}
}

internal struct UninstalledSkillOutput: Encodable {
	internal let id: String
	internal let name: String

	internal init(
		id: String,
		name: String
	) {
		self.id = id
		self.name = name
	}
}

internal struct UninstallOutput: Encodable {
	internal let uninstalled: [UninstalledSkillOutput]

	internal init(uninstalled: [UninstalledSkillOutput]) {
		self.uninstalled = uninstalled
	}
}

internal struct LinksOutput: Encodable {
	internal let links: [SkillLinkOutput]

	internal init(links: [SkillLinkOutput]) {
		self.links = links
	}
}

internal struct SkillPathOutput: Encodable {
	internal let id: String
	internal let name: String
	internal let path: String

	internal init(
		id: String,
		name: String,
		path: String
	) {
		self.id = id
		self.name = name
		self.path = path
	}
}

internal struct VerificationIssueOutput: Encodable {
	internal let kind: String
	internal let skillID: String
	internal let relatedSkillID: String?
	internal let path: String?
	internal let link: SkillLinkOutput?

	internal init(_ issue: RegistryVerificationReport.Issue) {
		switch issue {
		case .missingContent(let id):
			self.kind = "missing_content"
			self.skillID = id.rawValue
			self.relatedSkillID = nil
			self.path = nil
			self.link = nil

		case .digestMismatch(let id):
			self.kind = "digest_mismatch"
			self.skillID = id.rawValue
			self.relatedSkillID = nil
			self.path = nil
			self.link = nil

		case .missingDependency(let id, let dependencyID):
			self.kind = "missing_dependency"
			self.skillID = id.rawValue
			self.relatedSkillID = dependencyID.rawValue
			self.path = nil
			self.link = nil

		case .brokenDependencyLink(let id, let dependencyPath):
			self.kind = "broken_dependency_link"
			self.skillID = id.rawValue
			self.relatedSkillID = nil
			self.path = dependencyPath
			self.link = nil

		case .brokenToolLink(let id, let skillLink):
			self.kind = "broken_tool_link"
			self.skillID = id.rawValue
			self.relatedSkillID = nil
			self.path = nil
			self.link = SkillLinkOutput(skillLink)
		}
	}
}

internal struct VerifyOutput: Encodable {
	internal let valid: Bool
	internal let issues: [VerificationIssueOutput]

	internal init(
		valid: Bool,
		issues: [VerificationIssueOutput]
	) {
		self.valid = valid
		self.issues = issues
	}
}

internal func sourceDescription(_ source: SkillSource) -> String {
	let root = source.remote?.absoluteString ?? source.local?.path ?? "unknown"
	return source.path.isEmpty ? root : "\(root)#\(source.path)"
}

internal func linkDescription(_ link: SkillLink) -> String {
	switch link.target {
	case .tool(let tool): return "\(tool.rawValue):\(link.alias)"
	case .directory(let url): return "\(url.path)/\(link.alias)"
	}
}
