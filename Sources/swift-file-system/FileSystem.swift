import Dependencies
import Foundation
import ZIPFoundation

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif

public protocol FileSystem: Sendable {
	var homeDirectoryURL: URL { get }
	var currentDirectoryPath: String { get }
	var temporaryDirectoryURL: URL { get }

	func removeItem(at url: URL) throws
	func fileExists(atPath path: String) -> Bool
	func isDirectory(atPath path: String) -> Bool
	func createFile(at url: URL, contents: Data?) -> Bool
	func write(_ data: Data, to url: URL) throws
	func append(_ data: Data, to url: URL) throws
	func data(at url: URL) throws -> Data
	func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any]
	func open(_ url: URL)

	func createDirectory(
		at url: URL,
		withIntermediateDirectories createIntermediates: Bool
	) throws

	func createSymbolicLink(
		at url: URL,
		withDestinationURL destinationURL: URL
	) throws

	func moveItem(
		at sourceURL: URL,
		to destinationURL: URL
	) throws

	func copyItem(
		at sourceURL: URL,
		to destinationURL: URL
	) throws

	func contentsOfDirectory(
		at url: URL
	) throws -> [URL]

	func urls(
		for directory: FileManager.SearchPathDirectory,
		in domainMask: FileManager.SearchPathDomainMask
	) -> [URL]

	func unzipItem(
		at sourceURL: URL,
		to destinationURL: URL
	) throws
}

internal struct _FileSystem: FileSystem, @unchecked Sendable {
	internal let manager: FileManager

	internal init(manager: FileManager) {
		self.manager = manager
	}

	internal var homeDirectoryURL: URL { manager.homeDirectoryForCurrentUser }
	internal var currentDirectoryPath: String { manager.currentDirectoryPath }
	internal var temporaryDirectoryURL: URL { URL.temporaryDirectory }

	internal func removeItem(at url: URL) throws {
		try manager.removeItem(at: url)
	}

	internal func fileExists(atPath path: String) -> Bool {
		manager.fileExists(atPath: path)
	}

	internal func isDirectory(atPath path: String) -> Bool {
		var isDirectory = ObjCBool(false)
		guard manager.fileExists(atPath: path, isDirectory: &isDirectory) else {
			return false
		}

		return isDirectory.boolValue
	}

	internal func createFile(at url: URL, contents: Data?) -> Bool {
		manager.createFile(atPath: url.path, contents: contents)
	}

	internal func write(_ data: Data, to url: URL) throws {
		try data.write(to: url)
	}

	internal func append(_ data: Data, to url: URL) throws {
		let handle = try FileHandle(forWritingTo: url)
		defer { try? handle.close() }
		try handle.seekToEnd()
		try handle.write(contentsOf: data)
	}

	internal func data(at url: URL) throws -> Data {
		try Data(contentsOf: url)
	}

	internal func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
		try manager.attributesOfItem(atPath: path)
	}

	internal func open(_ url: URL) {
		#if canImport(AppKit) && !targetEnvironment(macCatalyst)
		NSWorkspace.shared.open(url)
		#endif
	}

	internal func createDirectory(
		at url: URL,
		withIntermediateDirectories createIntermediates: Bool
	) throws {
		try manager.createDirectory(
			at: url,
			withIntermediateDirectories: createIntermediates,
			attributes: nil
		)
	}

	internal func createSymbolicLink(
		at url: URL,
		withDestinationURL destinationURL: URL
	) throws {
		try manager.createSymbolicLink(
			at: url,
			withDestinationURL: destinationURL
		)
	}

	internal func moveItem(
		at sourceURL: URL,
		to destinationURL: URL
	) throws {
		try manager.moveItem(
			at: sourceURL,
			to: destinationURL
		)
	}

	internal func copyItem(
		at sourceURL: URL,
		to destinationURL: URL
	) throws {
		try manager.copyItem(
			at: sourceURL,
			to: destinationURL
		)
	}

	internal func contentsOfDirectory(
		at url: URL
	) throws -> [URL] {
		try manager.contentsOfDirectory(
			at: url,
			includingPropertiesForKeys: nil,
			options: []
		)
	}

	internal func urls(
		for directory: FileManager.SearchPathDirectory,
		in domainMask: FileManager.SearchPathDomainMask
	) -> [URL] {
		manager.urls(for: directory, in: domainMask)
	}

	internal func unzipItem(
		at sourceURL: URL,
		to destinationURL: URL
	) throws {
		try manager.unzipItem(
			at: sourceURL,
			to: destinationURL,
			skipCRC32: false,
			allowUncontainedSymlinks: false,
			progress: nil,
			pathEncoding: nil
		)
	}
}

extension DependencyValues {
	private enum FileSystemKey: DependencyKey {
		internal static var liveValue: any FileSystem { _FileSystem(manager: .default) }
	}

	public var fileSystem: any FileSystem {
		get { self[FileSystemKey.self] }
		set { self[FileSystemKey.self] = newValue }
	}
}
