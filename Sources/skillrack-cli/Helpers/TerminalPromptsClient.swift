import ArgumentParser
import Dependencies
import Foundation
import Promptberry

#if canImport(Darwin)
	import Darwin
#else
	import Glibc
#endif

internal struct TerminalPromptOption: Equatable, Sendable {
	internal let value: String
	internal let label: String
	internal let hint: String?

	internal init(
		value: String,
		label: String,
		hint: String?
	) {
		self.value = value
		self.label = label
		self.hint = hint
	}
}

internal struct TerminalPromptsClient: Sendable {
	internal var select: @Sendable (String, [TerminalPromptOption]) throws -> String?
	internal var multiselect: @Sendable (String, [TerminalPromptOption]) throws -> [String]?
	internal var autocomplete: @Sendable (String, [TerminalPromptOption]) throws -> String?
	internal var confirm: @Sendable (String) throws -> Bool?
	internal var text: @Sendable (String, String) throws -> String?

	internal init(
		select: @escaping @Sendable (String, [TerminalPromptOption]) throws -> String?,
		multiselect: @escaping @Sendable (String, [TerminalPromptOption]) throws -> [String]?,
		autocomplete: @escaping @Sendable (String, [TerminalPromptOption]) throws -> String?,
		confirm: @escaping @Sendable (String) throws -> Bool?,
		text: @escaping @Sendable (String, String) throws -> String?
	) {
		self.select = select
		self.multiselect = multiselect
		self.autocomplete = autocomplete
		self.confirm = confirm
		self.text = text
	}
}

// Promptberry clears logical lines, so wrapped option rows leave pieces of the previous frame behind.
private let promptOptionPrefixColumnCount: Int = 10
private let disableTerminalAutoWrap: String = "\u{1B}[?7l"
private let enableTerminalAutoWrap: String = "\u{1B}[?7h"

extension DependencyValues {
	private enum TerminalPromptsClientKey: DependencyKey {
		internal static var liveValue: TerminalPromptsClient {
			.init(
				select: { message, options in
					try requireInteractiveTerminal()
					do {
						return try withStablePromptRendering {
							try Promptberry.select(
								message,
								options: promptOptions(
									options,
									terminalWidth: Terminal.shared.width
								)
							)
						}
					} catch is PromptCancelled { return nil }
				},
				multiselect: { message, options in
					try requireInteractiveTerminal()
					do {
						return try withStablePromptRendering {
							try Promptberry.multiselect(
								message,
								options: promptOptions(
									options,
									terminalWidth: Terminal.shared.width
								),
								required: true
							)
						}
					} catch is PromptCancelled { return nil }
				},
				autocomplete: { message, options in
					try requireInteractiveTerminal()
					do {
						return try withStablePromptRendering {
							try Promptberry.autocomplete(
								message,
								options: promptOptions(
									options,
									terminalWidth: Terminal.shared.width
								)
							)
						}
					} catch is PromptCancelled { return nil }
				},
				confirm: { message in
					try requireInteractiveTerminal()
					do {
						return try Promptberry.confirm(
							message,
							initialValue: false
						)
					} catch is PromptCancelled { return nil }
				},
				text: { message, placeholder in
					try requireInteractiveTerminal()
					do {
						return try Promptberry.text(
							message,
							placeholder: placeholder,
							validate: {
								$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
								? "A value is required."
								: nil
							}
						)
					} catch is PromptCancelled { return nil }
				}
			)
		}
	}

	internal var terminalPrompts: TerminalPromptsClient {
		get { self[TerminalPromptsClientKey.self] }
		set { self[TerminalPromptsClientKey.self] = newValue }
	}
}

private func promptOptions(
	_ options: [TerminalPromptOption],
	terminalWidth: Int
) -> [SelectOption<String>] {
	options.map {
		let option = fittedPromptOption(
			$0,
			terminalWidth: terminalWidth
		)
		return .init(
			value: option.value,
			label: option.label,
			hint: option.hint
		)
	}
}

internal func fittedPromptOption(
	_ option: TerminalPromptOption,
	terminalWidth: Int
) -> TerminalPromptOption {
	let availableCount = max(
		1,
		terminalWidth - promptOptionPrefixColumnCount
	)
	let label = truncatedPromptText(
		option.label,
		maximumCount: availableCount
	)

	guard label == option.label, let hint = option.hint else {
		return .init(
			value: option.value,
			label: label,
			hint: nil
		)
	}

	let availableHintCount = availableCount - label.count - 2
	guard availableHintCount > 0 else {
		return .init(
			value: option.value,
			label: label,
			hint: nil
		)
	}

	return .init(
		value: option.value,
		label: label,
		hint: truncatedPromptText(
			hint,
			maximumCount: availableHintCount
		)
	)
}

private func truncatedPromptText(
	_ text: String,
	maximumCount: Int
) -> String {
	guard text.count > maximumCount else { return text }
	guard maximumCount > 1 else { return String(text.prefix(maximumCount)) }
	return String(text.prefix(maximumCount - 1)) + "…"
}

private func withStablePromptRendering<Value>(
	_ operation: () throws -> Value
) rethrows -> Value {
	let terminal = Terminal.shared
	terminal.write(disableTerminalAutoWrap)
	defer { terminal.write(enableTerminalAutoWrap) }
	return try operation()
}

internal func interactiveTerminalAvailable() -> Bool {
	isatty(STDIN_FILENO) != 0 && isatty(STDOUT_FILENO) != 0
}

private func requireInteractiveTerminal() throws {
	guard interactiveTerminalAvailable() else {
		throw ValidationError(
			"Interactive input requires a terminal. Provide the required values explicitly."
		)
	}
}
