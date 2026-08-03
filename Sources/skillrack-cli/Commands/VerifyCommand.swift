import ArgumentParser
import Dependencies
import SkillsRegistryManager

internal struct VerifyCommand: AsyncParsableCommand {
	internal static let configuration: CommandConfiguration = .init(
		commandName: "verify",
		abstract: "Verify registry content, dependencies, and managed links."
	)

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

		let machine = try machineOutputRequested(json)
		let report = try await registry.verify()
		let output = VerifyOutput(
			valid: report.isValid,
			issues: report.issues.map(VerificationIssueOutput.init)
		)

		if machine {
			try printMachineResponse(output)

		} else {
			let reporter = await TerminalReporter()
			if report.isValid {
				await reporter.success("The skills registry is valid.")

			} else {
				let names = Dictionary(
					uniqueKeysWithValues: try await registry.list().map { ($0.id, $0.name) }
				)
				for issue in report.issues {
					await reporter.warning(
						describe(
							issue,
							names: names
						)
					)
				}
			}
		}

		if !report.isValid {
			throw ReportedExit(code: .failure)
		}
	}

	private func describe(
		_ issue: RegistryVerificationReport.Issue,
		names: [RegistrySkill.ID: String]
	) -> String {
		func label(_ id: RegistrySkill.ID) -> String { names[id] ?? id.rawValue }
		switch issue {
		case let .missingContent(id):
			return "\(label(id)): content is missing"

		case let .digestMismatch(id):
			return "\(label(id)): content digest does not match"

		case let .missingDependency(id, dependencyID):
			return "\(label(id)): dependency \(label(dependencyID)) is missing"

		case let .brokenDependencyLink(id, path):
			return "\(label(id)): dependency link is broken at \(path)"

		case let .brokenToolLink(id, link):
			return "\(label(id)): managed link is broken at \(linkDescription(link))"
		}
	}
}
