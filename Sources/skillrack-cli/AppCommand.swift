import ArgumentParser
import Foundation

#if canImport(Darwin)
	import Darwin
#else
	import Glibc
#endif

@main
internal struct AppCommand: AsyncParsableCommand {
	internal static let version: String = "0.1.1"

	@Flag(
		inversion: .prefixedNo,
		exclusivity: .chooseLast,
		help: "Print versioned machine-readable JSON. Defaults from SKILLRACK_JSON."
	)
	internal var json: Bool?

	internal static let configuration: CommandConfiguration = .init(
		commandName: "skillrack",
		abstract: "Install, link, and inspect shared agent skills.",
		version: version,
		subcommands: [
			InstallCommand.self,
			ListCommand.self,
			ShowCommand.self,
			PathCommand.self,
			UninstallCommand.self,
			LinkCommand.self,
			UnlinkCommand.self,
			VerifyCommand.self,
			VersionCommand.self,
		]
	)

	internal init() {}

	internal static func main() async {
		do {
			let command = try await Self.asyncParseAsRoot()
			try await execute(command)
		} catch let exit as ReportedExit {
			platformExit(exit.code.rawValue)
		} catch {
			guard machineOutputRequestedForError(), !(error is CleanExit)
			else { exit(withError: error) }

			do {
				try printMachineError(error)
			} catch {
				FileHandle.standardError.write(
					Data("\(machineEncodingFailureResponse)\n".utf8)
				)
			}
			platformExit(exitCode(for: error).rawValue)
		}
	}

	private static func execute(_ parsed: any ParsableCommand) async throws {
		var command = parsed
		if var asyncCommand = command as? any AsyncParsableCommand {
			try await asyncCommand.run()
		} else {
			try command.run()
		}
	}
}

internal struct VersionCommand: ParsableCommand {
	internal static let configuration: CommandConfiguration = .init(
		commandName: "version",
		abstract: "Show the SkillRack version."
	)

	@Flag(
		inversion: .prefixedNo,
		exclusivity: .chooseLast,
		help: "Print a versioned machine-readable JSON response."
	)
	internal var json: Bool?

	internal init() {}

	internal func run() throws {
		if try machineOutputRequested(json) {
			try printMachineResponse(VersionOutput(version: AppCommand.version))
		} else {
			print(AppCommand.version)
		}
	}
}

internal struct ReportedExit: Error {
	internal let code: ExitCode

	internal init(code: ExitCode) {
		self.code = code
	}
}

private func platformExit(_ code: Int32) -> Never {
	exit(code)
}
