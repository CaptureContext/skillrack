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

extension DependencyValues {
	private enum TerminalPromptsClientKey: DependencyKey {
		internal static var liveValue: TerminalPromptsClient {
			.init(
				select: { message, options in
					try requireInteractiveTerminal()
					do {
						return try Promptberry.select(
							message,
							options: promptOptions(options)
						)
					} catch is PromptCancelled { return nil }
				},
				multiselect: { message, options in
					try requireInteractiveTerminal()
					do {
						return try Promptberry.multiselect(
							message,
							options: promptOptions(options),
							required: true
						)
					} catch is PromptCancelled { return nil }
				},
				autocomplete: { message, options in
					try requireInteractiveTerminal()
					do {
						return try Promptberry.autocomplete(
							message,
							options: promptOptions(options)
						)
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
	_ options: [TerminalPromptOption]
) -> [SelectOption<String>] {
	options.map {
		.init(
			value: $0.value,
			label: $0.label,
			hint: $0.hint
		)
	}
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
