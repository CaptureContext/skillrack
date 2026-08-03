import ArgumentParser
import Dependencies
import SkillsRegistryManager

internal struct PathCommand: AsyncParsableCommand {
	internal static let configuration: CommandConfiguration = .init(
		commandName: "path",
		abstract: "Print the directory of an installed registry skill."
	)

	@Argument(help: "Lowercase registry UUID or unique exact skill name.")
	internal var skill: String?

	@Flag(
		inversion: .prefixedNo,
		exclusivity: .chooseLast,
		help: "Print a versioned machine-readable JSON response."
	)
	internal var json: Bool?

	internal init() {}

	internal func run() async throws {
		@Dependency(\.skillsRegistryConfiguration)
		var configuration

		@Dependency(\.skillsRegistryManager)
		var registry

		@Dependency(\.terminalPrompts)
		var prompts

		let machine = try machineOutputRequested(json)
		let skills = try await registry.list()

		let selector: String
		if let skill {
			selector = skill

		} else if machine {
			throw ValidationError("A skill selector is required when using --json.")

		} else {
			guard !skills.isEmpty else {
				let reporter = await TerminalReporter()
				await reporter.info("No skills are installed.")
				return
			}

			guard
				let selected = try prompts.autocomplete(
					"Select a skill:",
					registrySkillPromptOptions(skills)
				)
			else {
				let reporter = await TerminalReporter()
				await reporter.warning("Cancelled.")
				return
			}

			selector = selected
		}

		let selected = try resolveRegistrySkill(selector, from: skills)
		let path = configuration.contentURL(for: selected.id).path
		if machine {
			try printMachineResponse(
				SkillPathOutput(
					id: selected.id.rawValue,
					name: selected.name,
					path: path
				)
			)

		} else {
			print(path)
		}
	}
}
