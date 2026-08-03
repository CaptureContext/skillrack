import Foundation

internal struct MachineResponse<Value: Encodable>: Encodable {
	internal let apiVersion: Int
	internal let ok: Bool
	internal let data: Value

	internal init(
		data: Value,
		apiVersion: Int = 1,
		ok: Bool = true
	) {
		self.apiVersion = apiVersion
		self.ok = ok
		self.data = data
	}
}

internal struct MachineErrorResponse: Encodable {
	internal struct Details: Encodable {
		internal let code: String
		internal let message: String

		internal init(
			code: String,
			message: String
		) {
			self.code = code
			self.message = message
		}
	}

	internal let apiVersion: Int
	internal let ok: Bool
	internal let error: Details

	internal init(error: any Error) {
		self.init(
			error: .init(
				code: errorCode(for: error),
				message: redactedMessage(for: error)
			)
		)
	}

	internal init(
		error: Details,
		apiVersion: Int = 1,
		ok: Bool = false
	) {
		self.apiVersion = apiVersion
		self.ok = ok
		self.error = error
	}
}
