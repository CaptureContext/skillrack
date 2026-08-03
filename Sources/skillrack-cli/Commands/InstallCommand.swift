import ArgumentParser
import Dependencies
import FileSystem
import Foundation
import SkillsManager
import SkillsRegistryManager

private enum CloneCollisionArgument: String, CaseIterable, ExpressibleByArgument {
	case error
	case clean
	case pull
	case skip

	internal var strategy: GitCloneCollisionStrategy {
		switch self {
		case .error: .error
		case .clean: .clean
		case .pull: .pull
		case .skip: .skip
		}
	}
}

internal struct InstallCommand: AsyncParsableCommand {
	internal static let configuration: CommandConfiguration = .init(
		commandName: "install",
		abstract: "Detect and install local or Git-hosted skills into the registry."
	)

	@Argument(help: "Local path, file URL, or cloneable Git URL. Omit to enter interactively.")
	internal var source: String?

	@Option(
		name: .customLong("clone-to"),
		help: "Persistent directory for a remote checkout."
	)
	internal var cloneTo: String?

	@Option(
		name: .customLong("if-present"),
		help: "How to handle an existing --clone-to directory."
	)
	fileprivate var ifPresent: CloneCollisionArgument?

	@Option(
		name: .customLong("skill"),
		help: "Root skill name or exact relative path. Repeatable."
	)
	internal var skill: [String] = []

	@Flag(help: "Install every detected root skill.")
	internal var all: Bool = false

	@Flag(help: "Update matching installed skills in place instead of reusing them.")
	internal var force: Bool = false

	@Flag(
		name: .shortAndLong,
		help: "Confirm destructive clone replacement without prompting."
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
		if all && !skill.isEmpty {
			throw ValidationError("--skill and --all are mutually exclusive.")
		}
		if ifPresent != nil && cloneTo == nil {
			throw ValidationError("--if-present requires --clone-to.")
		}
	}

	internal func run() async throws {
		@Dependency(\.fileSystem)
		var fileSystem

		@Dependency(\.gitClient)
		var git

		@Dependency(\.skillsManager)
		var manager

		@Dependency(\.skillsRegistryManager)
		var registry

		@Dependency(\.terminalPrompts)
		var prompts

		let machine = try machineOutputRequested(json)
		let rawSource: String
		if let source {
			rawSource = source

		} else {
			guard !machine
			else { throw ValidationError("A skill source is required when using --json.") }

			guard
				let entered = try prompts.text(
					"Local path or remote Git URL:",
					"./my-skill"
				)
			else {
				let reporter = await TerminalReporter()
				await reporter.warning("Cancelled.")
				return
			}

			rawSource = entered
		}

		let parsedSource = try SourceArgument(
			rawSource,
			currentDirectory: fileSystem.currentDirectoryPath,
			homeDirectory: fileSystem.homeDirectoryURL
		)

		var checkout: GitCheckout?
		let localURL: URL
		switch parsedSource {
		case .local(let url):
			guard cloneTo == nil && ifPresent == nil
			else {
				throw ValidationError("--clone-to and --if-present are valid only for remote sources.")
			}
			guard !yes
			else { throw ValidationError("--yes is valid only when a remote clone may be cleaned.") }
			localURL = url

		case .remote(let remoteURL):
			let destination: GitCloneDestination
			var strategy: CloneCollisionArgument = ifPresent ?? .error
			if let cloneTo {
				let destinationURL = expandedAbsoluteFileURL(
					cloneTo,
					currentDirectory: fileSystem.currentDirectoryPath,
					homeDirectory: fileSystem.homeDirectoryURL
				)
				destination = .local(destinationURL)
				let shouldPromptForCollision =
					fileSystem.fileExists(atPath: destinationURL.path)
					&& ifPresent == nil
					&& !machine
				if shouldPromptForCollision {
					let options = CloneCollisionArgument.allCases.map {
						TerminalPromptOption(
							value: $0.rawValue,
							label: $0.rawValue,
							hint: cloneHint($0)
						)
					}
					guard
						let selected = try prompts.select(
							"Checkout already exists. Choose a collision strategy:",
							options
						),
						let chosen = CloneCollisionArgument(rawValue: selected)
					else {
						let reporter = await TerminalReporter()
						await reporter.warning("Cancelled.")
						return
					}
					strategy = chosen
				}

				let shouldCleanExistingCheckout =
					strategy == .clean
					&& fileSystem.fileExists(atPath: destinationURL.path)
				if shouldCleanExistingCheckout {
					guard !machine || yes else {
						throw ValidationError(
							"--yes is required with --json when --if-present clean removes a checkout."
						)
					}
					if !yes {
						guard
							try prompts.confirm("Delete and replace \(destinationURL.path)?") == true
						else {
							let reporter = await TerminalReporter()
							await reporter.warning("Cancelled.")
							return
						}
					}
				}

			} else {
				destination = .temporaryDirectory
			}

			if yes && (cloneTo == nil || strategy != .clean) {
				throw ValidationError(
					"--yes is meaningful only with a potentially destructive clean clone.")
			}

			var options = GitCloneOptions.collisionStrategy(strategy.strategy)
			if machine { options.insert(.machineSafe) }

			let value = try await git.clone(
				remoteURL,
				to: destination,
				options: options
			)
			checkout = value
			localURL = value.localURL
		}

		do {
			let detected = try await manager.detectSkills(localURL)
			guard !detected.roots.isEmpty else {
				throw CLIError(
					code: "invalid_skill",
					message: "No root skills were detected at \(localURL.path)."
				)
			}

			guard
				let selected = try selectRoots(
					from: detected,
					machine: machine,
					prompts: prompts
				)
			else {
				let cleanupWarning = cleanup(
					checkout,
					fileSystem: fileSystem
				)
				let reporter = await TerminalReporter()
				await reporter.warning("Cancelled.")
				if let cleanupWarning { await reporter.warning(cleanupWarning) }
				return
			}

			let provenance: SkillSource
			if let checkout {
				provenance = try SkillSource(
					remote: checkout.remoteURL,
					local: checkout.lifetime == .persistent ? checkout.localURL : nil,
					revision: checkout.revision
				)

			} else {
				provenance = try SkillSource(local: detected.rootURL)
			}

			let state = InstallResolutionState()
			let outcome = try await registry.resolve(
				DetectedSkills(
					rootURL: detected.rootURL,
					roots: selected,
					skills: detected.skills,
					references: detected.references
				),
				source: provenance
			) { context in
				switch try await context.verify() {
				case .available:
					return .install(context.skill.skill)

				case .alreadyInstalled(let existing):
					if force {
						return .update(
							existing.id,
							context.skill.skill
						)
					}
					await state.record(existing)
					return .useExisting(existing.id)

				case .conflictingSources(let existing):
					if machine {
						let ids = existing.map(\.id.rawValue).joined(separator: ", ")
						throw CLIError(
							code: "source_conflict",
							message: "Multiple registry records match \(context.skill.relativePath): \(ids)"
						)
					}

					var options = registrySkillPromptOptions(existing)
					options.append(
						.init(
							value: "__abort__",
							label: "Abort installation",
							hint: nil
						)
					)
					guard
						let choice = try prompts.select(
							"Choose the existing record for \(context.skill.skill.name):",
							options
						),
						choice != "__abort__",
						let selected = existing.first(where: { $0.id.rawValue == choice })
					else { return .abort }

					if force {
						return .update(
							selected.id,
							context.skill.skill
						)
					}

					await state.record(selected)
					return .useExisting(selected.id)
				}
			}

			guard case .resolved(let plan) = outcome else {
				let cleanupWarning = cleanup(
					checkout,
					fileSystem: fileSystem
				)
				let reporter = await TerminalReporter()
				await reporter.warning("Cancelled.")
				if let cleanupWarning { await reporter.warning(cleanupWarning) }
				return
			}

			let installations = plan.skills.filter { $0.operation == .install }
			let updates = plan.skills.filter { $0.operation == .update }
			var installed: [RegistrySkill] = []
			do {
				for draft in installations {
					installed.append(try await registry.install(draft))
				}
			} catch {
				var rollbackMessages: [String] = []
				for record in installed.reversed() {
					do {
						try await registry.uninstall(record.id)
					} catch {
						rollbackMessages.append(redactedMessage(for: error))
					}
				}
				if rollbackMessages.isEmpty { throw error }
				throw CLIError(
					code: errorCode(for: error),
					message:
						"\(redactedMessage(for: error)) Rollback warnings: \(rollbackMessages.joined(separator: "; "))"
				)
			}
			var updated: [RegistrySkill] = []
			for draft in updates {
				updated.append(try await registry.update(draft))
			}

			let reused = await state.records()
			var roots: [RegistrySkill] = []
			for id in plan.roots { roots.append(try await registry.get(id)) }
			var warnings: [String] = []
			let cleanupWarning = cleanup(
				checkout,
				fileSystem: fileSystem
			)
			if let cleanupWarning { warnings.append(cleanupWarning) }

			let output = InstallOutput(
				roots: roots.map(RegistrySkillOutput.init),
				installed: installed.map(RegistrySkillOutput.init),
				updated: updated.map(RegistrySkillOutput.init),
				reused: reused.map(RegistrySkillOutput.init),
				source: SkillSourceOutput(provenance),
				checkoutRevision: checkout?.revision,
				persistentCheckoutPath: checkout?.lifetime == .persistent ? checkout?.localURL.path : nil,
				warnings: warnings
			)

			if machine {
				try printMachineResponse(output)

			} else {
				let reporter = await TerminalReporter()
				if !installed.isEmpty {
					await reporter.success("Installed: \(installed.map(\.name).joined(separator: ", ")).")
				}

				if !updated.isEmpty {
					await reporter.success("Updated: \(updated.map(\.name).joined(separator: ", ")).")
				}

				if !reused.isEmpty {
					await reporter.info("Reused: \(reused.map(\.name).joined(separator: ", ")).")
				}

				await reporter.info("Selected roots: \(roots.map(\.name).joined(separator: ", ")).")

				if let path = output.persistentCheckoutPath {
					await reporter.info("Preserved checkout: \(path)")
				} else if checkout != nil {
					await reporter.info("Removed temporary checkout.")
				}

				for warning in warnings { await reporter.warning(warning) }
			}
		} catch {
			let cleanupWarning = cleanup(
				checkout,
				fileSystem: fileSystem
			)
			if let cleanupWarning {
				throw CLIError(
					code: errorCode(for: error),
					message: "\(redactedMessage(for: error)) Cleanup warning: \(cleanupWarning)"
				)
			}

			throw error
		}
	}

	private func selectRoots(
		from detected: DetectedSkills,
		machine: Bool,
		prompts: TerminalPromptsClient
	) throws -> [DetectedSkill.ID]? {
		let roots = detected.roots.compactMap { detected.skills[$0] }.sorted {
			$0.relativePath < $1.relativePath
		}
		if all { return roots.map(\.id) }
		if !skill.isEmpty {
			return try uniqued(
				skill.map {
					try resolveRoot(
						$0,
						roots: roots
					)
				}
			)
		}
		if roots.count == 1 { return [roots[0].id] }
		guard !machine
		else {
			throw ValidationError("Multiple root skills were detected. Use --skill or --all with --json.")
		}

		let options = roots.map {
			TerminalPromptOption(
				value: $0.relativePath,
				label: $0.skill.name,
				hint: [$0.relativePath, $0.skill.description].compactMap { $0 }.joined(separator: " · ")
			)
		}
		guard
			let paths = try prompts.multiselect(
				"Select root skills to install:",
				options
			)
		else { return nil }

		return try paths.map {
			try resolveRoot(
				$0,
				roots: roots
			)
		}
	}

	private func resolveRoot(
		_ selector: String,
		roots: [DetectedSkill]
	) throws -> DetectedSkill.ID {
		if let exact = roots.first(where: { $0.relativePath == selector }) { return exact.id }
		let named = roots.filter { $0.skill.name == selector }
		guard !named.isEmpty else {
			throw CLIError(
				code: "skill_not_found",
				message: "Detected root skill was not found: \(selector)"
			)
		}

		guard named.count == 1 else {
			let paths = named.map(\.relativePath).joined(separator: ", ")
			throw CLIError(
				code: "skill_not_found",
				message: "Detected skill name '\(selector)' is ambiguous. Paths: \(paths)"
			)
		}

		return named[0].id
	}

	private func cleanup(
		_ checkout: GitCheckout?,
		fileSystem: any FileSystem
	) -> String? {
		guard let checkout, checkout.lifetime == .scoped else { return nil }
		guard fileSystem.fileExists(atPath: checkout.localURL.path) else { return nil }
		do {
			try fileSystem.removeItem(at: checkout.localURL)
			return nil
		} catch {
			return
				"Unable to remove temporary checkout at \(checkout.localURL.path): \(redactedMessage(for: error))"
		}
	}
}

private actor InstallResolutionState {
	private var values: [RegistrySkill] = []
	private var ids: Set<RegistrySkill.ID> = []

	internal func record(_ skill: RegistrySkill) {
		if ids.insert(skill.id).inserted { values.append(skill) }
	}

	internal func records() -> [RegistrySkill] { values }
}

private func cloneHint(_ strategy: CloneCollisionArgument) -> String {
	switch strategy {
	case .error: "Fail without changing the directory"
	case .clean: "Delete it and clone again"
	case .pull: "Fast-forward the existing checkout"
	case .skip: "Use the existing checkout unchanged"
	}
}
