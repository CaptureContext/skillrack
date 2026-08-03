import ArgumentParser
import Dependencies
import SkillsRegistryManager

internal struct ListCommand: AsyncParsableCommand {
	internal static let configuration: CommandConfiguration = .init(
		commandName: "list",
		abstract: "List installed registry skills."
	)

	@Flag(
		inversion: .prefixedNo,
		exclusivity: .chooseLast,
		help: "Print every plain-text field. Enabled by default."
	)
	internal var printAll: Bool = true

	@Flag(help: "Print canonical skill names.")
	internal var printName: Bool = false

	@Flag(
		name: .customLong("print-desc"),
		help: "Print skill descriptions."
	)
	internal var printDescription: Bool = false

	@Flag(help: "Print full registry IDs.")
	internal var printID: Bool = false

	@Flag(help: "Print canonical source locations.")
	internal var printSource: Bool = false

	@Flag(
		name: .customLong("print-deps"),
		help: "Print dependency counts."
	)
	internal var printDependencies: Bool = false

	@Flag(help: "Print managed-link counts.")
	internal var printLinks: Bool = false

	@Flag(
		inversion: .prefixedNo,
		exclusivity: .chooseLast,
		help: "Print a versioned machine-readable JSON response."
	)
	internal var json: Bool?

	internal init() {}

	internal mutating func validate() throws {
		guard printAll || hasSelectedField else {
			throw ValidationError(
				"--no-print-all requires at least one --print-* field."
			)
		}
	}

	internal func run() async throws {
		@Dependency(\.skillsRegistryManager)
		var registry

		let machine = try machineOutputRequested(json)
		let skills = try await registry.list()

		if machine {
			try printMachineResponse(ListOutput(skills: skills.map(RegistrySkillOutput.init)))
			return
		}

		guard !skills.isEmpty else {
			let reporter = await TerminalReporter()
			await reporter.info("No skills are installed.")
			return
		}

		for skill in skills {
			print(render(skill))
		}
	}

	private var hasSelectedField: Bool {
		printName
			|| printDescription
			|| printID
			|| printSource
			|| printDependencies
			|| printLinks
	}

	private func render(_ skill: RegistrySkill) -> String {
		var values: [String] = []
		if printAll || printName { values.append(skill.name) }
		if printAll || printDescription { values.append(skill.description ?? "") }
		if printAll || printID { values.append(skill.id.rawValue) }
		if printAll || printSource { values.append(sourceDescription(skill.source)) }
		if printAll || printDependencies { values.append(String(skill.dependencies.count)) }
		if printAll || printLinks { values.append(String(skill.links.count)) }
		return values.joined(separator: "\t")
	}
}
