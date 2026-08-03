import ArgumentParser
import Dependencies
import SkillsRegistryManager

internal struct ShowCommand: AsyncParsableCommand {
	internal static let configuration: CommandConfiguration = .init(
		commandName: "show",
		abstract: "Show one installed registry skill."
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

		let selected = try resolveRegistrySkill(
			selector,
			from: skills
		)
		if machine {
			try printMachineResponse(RegistrySkillOutput(selected))
			return
		}

		let reporter = await TerminalReporter()
		await reporter.info("ID: \(selected.id.rawValue)")
		await reporter.info("Name: \(selected.name)")
		if let displayName = selected.displayName {
			await reporter.info("Display name: \(displayName)")
		}
		if let description = selected.description {
			await reporter.info("Description: \(description)")
		}
		await reporter.info("Source: \(sourceDescription(selected.source))")
		if let revision = selected.source.revision {
			await reporter.info("Revision: \(revision)")
		}
		await reporter.info("Digest: \(selected.digest.algorithm):\(selected.digest.hash)")
		await reporter.info("Created: \(selected.createdAt.formatted(.iso8601))")
		await reporter.info("Updated: \(selected.updatedAt.formatted(.iso8601))")
		let dependencies =
			selected.dependencies.isEmpty
			? "none"
			: selected.dependencies.map { "\($0.path) -> \($0.skillID.rawValue)" }.joined(separator: ", ")
		await reporter.info("Dependencies: \(dependencies)")

		let links =
			selected.links.isEmpty
			? "none"
			: selected.links.map(linkDescription).joined(separator: ", ")
		await reporter.info("Links: \(links)")
	}
}
