import Foundation
import FileSystem

internal struct SkillsInstaller {
	internal let fileSystem: any FileSystem
	internal let skillsDirectoryURL: URL

	internal init(
		fileSystem: any FileSystem,
		skillsDirectoryURL: URL
	) {
		self.fileSystem = fileSystem
		self.skillsDirectoryURL = skillsDirectoryURL
	}

	internal func installSkill(
		_ skill: Skill,
		for tool: Tool
	) throws {
		_ = try LocalSkillsRepository(fileSystem: fileSystem)
			.saveSkill(
				skill,
				to: skillsDirectoryURL
			)

		let sourceURL = skillsDirectoryURL.appendingPathComponent(
			skill.name,
			isDirectory: true
		)
		let toolDirectoryURL = tool.skillsDirectoryURL(
			relativeTo: fileSystem.homeDirectoryURL
		)
		try fileSystem.createDirectory(
			at: toolDirectoryURL,
			withIntermediateDirectories: true
		)

		let installedURL = toolDirectoryURL.appendingPathComponent(
			skill.name,
			isDirectory: true
		)
		if fileSystem.fileExists(atPath: installedURL.path) {
			try fileSystem.removeItem(at: installedURL)
		}
		try fileSystem.createSymbolicLink(
			at: installedURL,
			withDestinationURL: sourceURL
		)
	}

	internal func uninstallSkill(
		_ skill: Skill,
		for tool: Tool
	) throws {
		try SkillValidator.validateName(skill.name)
		let installedURL = tool
			.skillsDirectoryURL(relativeTo: fileSystem.homeDirectoryURL)
			.appendingPathComponent(
				skill.name,
				isDirectory: true
			)

		if fileSystem.fileExists(atPath: installedURL.path) {
			try fileSystem.removeItem(at: installedURL)
		}
	}
}
