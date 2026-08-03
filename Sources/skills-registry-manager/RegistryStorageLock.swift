import Darwin
import Foundation

internal final class RegistryStorageLock: @unchecked Sendable {
	private let fileManager: FileManager
	private let lockURL: URL
	private let rootURL: URL

	internal init(
		rootURL: URL,
		lockURL: URL,
		fileManager: FileManager
	) {
		self.rootURL = rootURL
		self.lockURL = lockURL
		self.fileManager = fileManager
	}

	internal func withLock<Value>(_ operation: () throws -> Value) throws -> Value {
		try fileManager.createDirectory(
			at: rootURL,
			withIntermediateDirectories: true,
			attributes: [.posixPermissions: 0o700]
		)
		let descriptor = Darwin.open(
			lockURL.path,
			O_CREAT | O_RDWR,
			S_IRUSR | S_IWUSR
		)
		guard descriptor >= 0 else {
			throw CocoaError(.fileWriteUnknown)
		}
		defer { Darwin.close(descriptor) }

		guard Darwin.lockf(descriptor, F_LOCK, 0) == 0 else {
			throw CocoaError(.fileLocking)
		}
		defer { Darwin.lockf(descriptor, F_ULOCK, 0) }

		return try operation()
	}
}
