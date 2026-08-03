import ConsoleKitTerminal
import Foundation

@MainActor
internal final class TerminalReporter {
	private let console: Terminal

	internal init() {
		let console = Terminal()
		if ProcessInfo.processInfo.environment["NO_COLOR"] != nil {
			console.stylizedOutputOverride = false
		}
		self.console = console
	}

	internal func info(_ message: String) { console.info(message) }
	internal func success(_ message: String) { console.success(message) }
	internal func warning(_ message: String) { console.warning(message) }
}
