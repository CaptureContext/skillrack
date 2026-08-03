import ArgumentParser
import Dependencies
import FileSystem
import SkillsManager
import SkillsRegistryManager

internal struct UnlinkCommand: AsyncParsableCommand {
	internal static let configuration: CommandConfiguration = .init(
		commandName: "unlink",
		abstract: "Remove recorded managed skill links."
	)

	@Argument(help: "Lowercase registry UUIDs or unique exact skill names.")
	internal var skills: [String] = []

	@Option(help: "Only links targeting this tool. Repeatable.")
	internal var tool: [Tool] = []

	@Option(
		name: .customLong("directory"),
		help: "Only links targeting this directory. Repeatable."
	)
	internal var directory: [String] = []

	@Option(help: "Only links with this alias.")
	internal var alias: String?

	@Flag(help: "Remove all links for the selected skills.")
	internal var all: Bool = false

	@Flag(
		name: .shortAndLong,
		help: "Confirm without prompting."
	)
	internal var yes: Bool = false

	@Flag(
		inversion: .prefixedNo,
		exclusivity: .chooseLast,
		help: "Print a versioned machine-readable JSON response."
	)
	internal var json: Bool?

	internal init() {}

	internal mutating func validate() throws {
		if all && (!tool.isEmpty || !directory.isEmpty || alias != nil) {
			throw ValidationError("--all cannot be combined with link filters.")
		}
	}

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

			let linkable = installed.filter { !$0.links.isEmpty }
			guard !linkable.isEmpty else {
				let reporter = await TerminalReporter()
				await reporter.info("No managed skill links exist.")
				return
			}

			guard
				let ids = try prompts.multiselect(
					"Select linked skills:",
					registrySkillPromptOptions(linkable)
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

		let directoryURLs = Set(directory.map {
			expandedAbsoluteFileURL(
				$0,
				currentDirectory: fileSystem.currentDirectoryPath,
				homeDirectory: fileSystem.homeDirectoryURL
			)
		})
		let tools = Set(tool)
		let hasFilters = !tools.isEmpty || !directoryURLs.isEmpty || alias != nil
		guard !machine || all || hasFilters
		else { throw ValidationError("Use --all or provide a link filter when using --json.") }

		var links = selected.flatMap(\.links)
		if !all && hasFilters {
			links = links.filter { link in
				let targetMatches: Bool
				if tools.isEmpty && directoryURLs.isEmpty {
					targetMatches = true

				} else {
					switch link.target {
					case let .tool(value): targetMatches = tools.contains(value)

					case let .directory(value):
						targetMatches = directoryURLs.contains(value.standardizedFileURL)
					}
				}
				return targetMatches && (alias == nil || link.alias == alias)
			}

		} else if !all {
			let options = links.map {
				TerminalPromptOption(
					value: linkKey($0),
					label: linkDescription($0),
					hint: $0.skillID.rawValue
				)
			}
			guard
				let values = try prompts.multiselect(
					"Select links to remove:",
					options
				)
			else {
				let reporter = await TerminalReporter()
				await reporter.warning("Cancelled.")
				return
			}

			let keys = Set(values)
			links = links.filter { keys.contains(linkKey($0)) }
		}

		links = uniqued(links)
		guard !links.isEmpty else {
			let reporter = await TerminalReporter()
			await reporter.info("No matching managed links exist.")
			return
		}

		guard !machine || yes
		else { throw ValidationError("--yes is required with --json when unlinking skills.") }
		if !yes {
			guard
				try prompts.confirm("Remove \(links.count) managed link(s)?") == true
			else {
				let reporter = await TerminalReporter()
				await reporter.warning("Cancelled.")
				return
			}
		}

		for link in links { try await registry.unlink(link) }
		if machine {
			try printMachineResponse(LinksOutput(links: links.map(SkillLinkOutput.init)))

		} else {
			let reporter = await TerminalReporter()
			for link in links { await reporter.success("Unlinked \(linkDescription(link)).") }
		}
	}

	private func linkKey(_ link: SkillLink) -> String {
		"\(link.skillID.rawValue)|\(linkDescription(link))"
	}
}
