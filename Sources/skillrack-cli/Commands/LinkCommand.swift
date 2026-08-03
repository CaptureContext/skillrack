import ArgumentParser
import Dependencies
import FileSystem
import SkillsManager
import SkillsRegistryManager

internal struct LinkCommand: AsyncParsableCommand {
	internal static let configuration: CommandConfiguration = .init(
		commandName: "link",
		abstract: "Link installed registry skills to tools or directories."
	)

	@Argument(help: "Lowercase registry UUIDs or unique exact skill names.")
	internal var skills: [String] = []

	@Option(help: "Tool to receive the selected skills. Repeatable.")
	internal var tool: [Tool] = []

	@Option(
		name: .customLong("directory"),
		help: "Directory to receive the selected skills. Repeatable."
	)
	internal var directory: [String] = []

	@Option(help: "Link name. Allowed only when one skill is selected.")
	internal var alias: String?

	@Flag(help: "Link transitive mentioned-skill dependencies without prompting.")
	internal var withDependencies: Bool = false

	@Flag(
		inversion: .prefixedNo,
		exclusivity: .chooseLast,
		help: "Print a versioned machine-readable JSON response."
	)
	internal var json: Bool?

	internal init() {}

	internal func run() async throws {
		@Dependency(\.fileSystem)
		var fileSystem

		@Dependency(\.skillsRegistryManager)
		var registry

		@Dependency(\.terminalPrompts)
		var prompts

		let machine = try machineOutputRequested(json)
		let installed = try await registry.list()

		let selected: [RegistrySkill]
		if skills.isEmpty {
			guard !machine
			else { throw ValidationError("At least one skill selector is required when using --json.") }

			guard !installed.isEmpty else {
				let reporter = await TerminalReporter()
				await reporter.info("No skills are installed.")
				return
			}

			guard
				let ids = try prompts.multiselect(
					"Select skills to link:",
					registrySkillPromptOptions(installed)
				)
			else {
				let reporter = await TerminalReporter()
				await reporter.warning("Cancelled.")
				return
			}

			selected = try resolveRegistrySkills(
				ids,
				from: installed
			)

		} else {
			selected = try resolveRegistrySkills(
				skills,
				from: installed
			)
		}

		guard alias == nil || selected.count == 1
		else { throw ValidationError("--alias is allowed only when exactly one skill is selected.") }

		var targets: [LinkTarget] = tool.map(LinkTarget.tool)
		targets += directory.map {
			.directory(
				expandedAbsoluteFileURL(
					$0,
					currentDirectory: fileSystem.currentDirectoryPath,
					homeDirectory: fileSystem.homeDirectoryURL
				)
			)
		}
		targets = uniqued(targets)
		if targets.isEmpty {
			guard !machine
			else { throw ValidationError("At least one --tool or --directory is required when using --json.") }

			let options = Tool.allCases.map {
				TerminalPromptOption(
					value: $0.rawValue,
					label: $0.rawValue,
					hint: nil
				)
			}
			guard
				let values = try prompts.multiselect(
					"Select target tools:",
					options
				)
			else {
				let reporter = await TerminalReporter()
				await reporter.warning("Cancelled.")
				return
			}

			targets = values.compactMap(Tool.init(rawValue:)).map(LinkTarget.tool)
		}

		let dependencySkills = try mentionedDependencySkills(
			of: selected,
			in: installed
		)
		let selectedIDs = Set(selected.map(\.id))
		let unresolvedDependencies = dependencySkills.filter { dependency in
			!selectedIDs.contains(dependency.id)
			&& !targets.allSatisfy { target in
				dependency.links.contains {
					$0.target == target && $0.alias == dependency.name
				}
			}
		}
		if !unresolvedDependencies.isEmpty && !withDependencies {
			if machine {
				throw ValidationError(
					"Mentioned-skill dependencies require explicit selectors or --with-dependencies: "
					+ unresolvedDependencies.map(\.name).joined(separator: ", ")
				)
			}
			for dependency in unresolvedDependencies {
				guard
					try prompts.confirm("Link required dependency \(dependency.name) too?") == true
				else {
					let reporter = await TerminalReporter()
					await reporter.warning("Cancelled before creating links.")
					return
				}
			}
		}

		let linking = uniquedByID(dependencySkills + selected)
		let existingLinks = Set(linking.flatMap(\.links))
		var resulting: [SkillLink] = []
		var created: [SkillLink] = []
		do {
			for skill in linking {
				for target in targets {
					let isSelectedRoot = selected.count == 1 && skill.id == selected[0].id
					let linkAlias: String? = isSelectedRoot ? alias : nil
					let link = try await registry.link(
						skill.id,
						to: target,
						alias: linkAlias
					)
					resulting.append(link)
					if !existingLinks.contains(link) { created.append(link) }
				}
			}
		} catch {
			for link in created.reversed() { try? await registry.unlink(link) }
			throw error
		}

		if machine {
			try printMachineResponse(LinksOutput(links: resulting.map(SkillLinkOutput.init)))

		} else {
			let reporter = await TerminalReporter()
			for link in resulting {
				await reporter.success("Linked \(linkDescription(link)).")
			}
		}
	}
}

private func mentionedDependencySkills(
	of roots: [RegistrySkill],
	in installed: [RegistrySkill]
) throws -> [RegistrySkill] {
	let skillsByID = Dictionary(uniqueKeysWithValues: installed.map { ($0.id, $0) })
	var visited = Set(roots.map(\.id))
	var ordered: [RegistrySkill] = []

	func visit(_ id: RegistrySkill.ID) throws {
		guard let skill = skillsByID[id] else {
			throw CLIError(
				code: "dependency_conflict",
				message: "Installed skill dependency \(id.rawValue) is missing."
			)
		}
		for dependency in skill.dependencies where dependency.kind == .mentioned {
			guard visited.insert(dependency.skillID).inserted else { continue }
			try visit(dependency.skillID)
			guard let resolved = skillsByID[dependency.skillID] else { continue }
			ordered.append(resolved)
		}
	}

	for root in roots { try visit(root.id) }
	return ordered
}

private func uniquedByID(_ skills: [RegistrySkill]) -> [RegistrySkill] {
	var seen: Set<RegistrySkill.ID> = []
	return skills.filter { seen.insert($0.id).inserted }
}
