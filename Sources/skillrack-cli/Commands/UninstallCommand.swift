import ArgumentParser
import Dependencies
import SkillsRegistryManager

internal struct UninstallCommand: AsyncParsableCommand {
	internal static let configuration: CommandConfiguration = .init(
		commandName: "uninstall",
		abstract: "Remove installed skills from the registry. This operation is sequential."
	)

	@Argument(help: "Lowercase registry UUIDs or unique exact skill names.")
	internal var skills: [String] = []

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

	internal func run() async throws {
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
					"Select skills to uninstall:",
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

		guard !machine || yes
		else { throw ValidationError("--yes is required with --json when uninstalling skills.") }

		if !yes {
			let names = selected.map(\.name).joined(separator: ", ")
			guard
				try prompts.confirm("Uninstall \(names)?") == true
			else {
				let reporter = await TerminalReporter()
				await reporter.warning("Cancelled.")
				return
			}
		}

		var removed: [RegistrySkill] = []
		for skill in selected {
			try await registry.uninstall(skill.id)
			removed.append(skill)
		}
		let output = UninstallOutput(
			uninstalled: removed.map {
				.init(
					id: $0.id.rawValue,
					name: $0.name
				)
			}
		)

		if machine {
			try printMachineResponse(output)

		} else {
			let reporter = await TerminalReporter()
			await reporter.success(
				"Uninstalled \(removed.map(\.name).joined(separator: ", "))."
			)
		}
	}
}
