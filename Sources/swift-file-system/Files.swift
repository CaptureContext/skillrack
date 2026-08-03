/**
 *  Files
 *
 *  Copyright (c) 2017-2019 John Sundell. Licensed under the MIT license, as follows:
 *
 *  Permission is hereby granted, free of charge, to any person obtaining a copy
 *  of this software and associated documentation files (the "Software"), to deal
 *  in the Software without restriction, including without limitation the rights
 *  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 *  copies of the Software, and to permit persons to whom the Software is
 *  furnished to do so, subject to the following conditions:
 *
 *  The above copyright notice and this permission notice shall be included in all
 *  copies or substantial portions of the Software.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 *  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 *  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 *  SOFTWARE.
 */

import Dependencies
import Foundation

// MARK: - Locations

/// Enum describing various kinds of locations that can be found on a file system.
public enum LocationKind {
	/// A file can be found at the location.
	case file

	/// A folder can be found at the location.
	case folder
}

/// Protocol adopted by types that represent locations on a file system.
public protocol Location: Equatable, CustomStringConvertible {
	/// The kind of location that is being represented (see `LocationKind`).
	static var kind: LocationKind { get }

	/// The underlying storage for the item at the represented location.
	/// You don't interact with this object as part of the internal API.
	var storage: Storage<Self> { get }

	/// Initialize an instance of this location with its underlying storage.
	/// You don't call this initializer as part of the internal API, instead
	/// use `init(path:)` on either `File` or `Folder`.
	init(storage: Storage<Self>)
}

extension Location {
	public static func ==(lhs: Self, rhs: Self) -> Bool {
		return lhs.storage.path == rhs.storage.path
	}

	public var description: String {
		let typeName = String(describing: type(of: self))
		return "\(typeName)(name: \(name), path: \(path))"
	}

	/// The path of this location, relative to the root of the file system.
	public var path: String {
		return storage.path
	}

	/// A URL representation of the location's `path`.
	public var url: URL {
		return URL(fileURLWithPath: path)
	}

	/// The name of the location, including any `extension`.
	public var name: String {
		return url.pathComponents.last!
	}

	/// The name of the location, excluding its `extension`.
	public var nameExcludingExtension: String {
		let components = name.split(separator: ".")
		guard components.count > 1 else { return name }
		return components.dropLast().joined()
	}

	/// The file extension of the item at the location.
	public var `extension`: String? {
		let components = name.split(separator: ".")
		guard components.count > 1 else { return nil }
		return String(components.last!)
	}

	/// The parent folder that this location is contained within.
	public var parent: Folder? {
		return storage.makeParentPath(for: path).flatMap {
			try? Folder(storage: Storage(
				path: $0
			))
		}
	}

	/// The date when the item at this location was created.
	/// Only returns `nil` in case the item has now been deleted.
	public var creationDate: Date? {
		return storage.attributes[.creationDate] as? Date
	}

	/// The date when the item at this location was last modified.
	/// Only returns `nil` in case the item has now been deleted.
	public var modificationDate: Date? {
		return storage.attributes[.modificationDate] as? Date
	}

	/// Initialize an instance of an existing location at a given path.
	/// - parameter path: The absolute path of the location.
	/// - throws: `LocationError` if the item couldn't be found.
	public init(uncheckedPath: String) {
		self.init(storage: Storage(
			uncheckedPath: uncheckedPath
		))
	}

	public func validatePath() throws (LocationError) {
		try storage.validatePath()
	}

	/// Initialize an instance of an existing location at a given path.
	/// - parameter path: The absolute path of the location.
	/// - throws: `LocationError` if the item couldn't be found.
	public init(path: String) throws (LocationError) {
		self.init(storage: Storage(
			uncheckedPath: path,
		))
		try storage.validatePath()
	}

	/// Initialize an instance of an existing location at a given path.
	/// - parameter path: The absolute path of the location.
	/// - throws: `LocationError` if the item couldn't be found.
	public init(path: String, create: Bool) throws (SomeFilesError) {
		try self.init(storage: Storage(
			path: path,
			create: create
		))
	}

	/// Return the path of this location relative to a parent folder.
	/// For example, if this item is located at `/users/john/documents`
	/// and `/users/john` is passed, then `documents` is returned. If the
	/// passed folder isn't an ancestor of this item, then the item's
	/// absolute `path` is returned instead.
	/// - parameter folder: The folder to compare this item's path against.
	public func path(relativeTo folder: Folder) -> String {
		guard path.hasPrefix(folder.path) else {
			return path
		}

		let index = path.index(path.startIndex, offsetBy: folder.path.count)
		return String(path[index...]).removingSuffix("/")
	}

	/// Rename this location, keeping its existing `extension` by default.
	/// - parameter newName: The new name to give the location.
	/// - parameter keepExtension: Whether the location's `extension` should
	///   remain unmodified (default: `true`).
	/// - throws: `LocationError` if the item couldn't be renamed.
	public func rename(to newName: String, keepExtension: Bool = true) throws (LocationError) -> Self {
		guard let parent = parent else {
			throw LocationError(path: path, reason: .cannotRenameRoot)
		}

		var newName = newName

		if keepExtension {
			`extension`.map {
				newName = newName.appendingSuffixIfNeeded(".\($0)")
			}
		}

		return try Self(storage: storage.move(
			to: parent.path + newName,
			errorReasonProvider: LocationErrorReason.renameFailed
		))
	}

	/// Move this location to a new parent folder
	/// - parameter newParent: The folder to move this item to.
	/// - throws: `LocationError` if the location couldn't be moved.
	@discardableResult
	public func move(to newParent: Folder) throws (LocationError) -> Self {
		try Self(storage: storage.move(
			to: newParent.path + name,
			errorReasonProvider: LocationErrorReason.moveFailed
		))
	}

	/// Copy the contents of this location to a given folder
	/// - parameter newParent: The folder to copy this item to.
	/// - throws: `LocationError` if the location couldn't be copied.
	/// - returns: The new, copied location.
	@discardableResult
	public func copy(to folder: Folder) throws (LocationError) -> Self {
		return try Self(storage: storage.copy(to: folder.path + name))
	}

	/// Delete this location. It will be permanently deleted. Use with caution.
	/// - throws: `LocationError` if the item couldn't be deleted.
	public func delete() throws (LocationError) {
		try storage.delete()
	}
}

// MARK: - Storage

/// Type used to store information about a given file system location. You don't
/// interact with this type as part of the internal API, instead you use the APIs
/// exposed by `Location`, `File`, and `Folder`.
public final class Storage<LocationType: Location> {
	private(set) public var path: String

	@Dependency(\.fileSystem)
	fileprivate var fileSystem

	public init(uncheckedPath: String) {
		self.path = uncheckedPath
	}

	public convenience init(
		path: String,
		create: Bool = false
	) throws (SomeFilesError) {
		self.init(uncheckedPath: path)

		if create {
			try SomeFilesError.catch(createIfNeeded)
		}
		try SomeFilesError.catch(validatePath)
	}

	public func createIfNeeded() throws (WriteError) {
		if !fileSystem.fileExists(atPath: path) {
			switch LocationType.kind {
			case .file:
				if !fileSystem.createFile(
					at: URL(fileURLWithPath: path),
					contents: nil
				) {
					throw WriteError(path: path, reason: .fileCreationFailed)
				}

			case .folder:
				do {
					try fileSystem.createDirectory(
						at: URL(fileURLWithPath: path, isDirectory: true),
						withIntermediateDirectories: true
					)
				} catch {
					throw WriteError(path: path, reason: .folderCreationFailed(error))
				}
			}
		}
	}

	public func validatePath() throws (LocationError) {
		switch LocationType.kind {
		case .file:
			guard !path.isEmpty else {
				throw LocationError(path: path, reason: .emptyFilePath)
			}

		case .folder:
			if path.isEmpty { path = fileSystem.currentDirectoryPath }
			if !path.hasSuffix("/") { path += "/" }
		}

		if path.hasPrefix("~") {
			let homePath = fileSystem.homeDirectoryURL.path
			path = homePath + path.dropFirst()
		}

		while let parentReferenceRange = path.range(of: "../") {
			let folderPath = String(path[..<parentReferenceRange.lowerBound])
			let parentPath = makeParentPath(for: folderPath) ?? "/"

			guard fileSystem.locationExists(at: parentPath, kind: .folder) else {
				throw LocationError(path: parentPath, reason: .missing)
			}

			path.replaceSubrange(..<parentReferenceRange.upperBound, with: parentPath)
		}

		guard fileSystem.locationExists(at: path, kind: LocationType.kind) else {
			throw LocationError(path: path, reason: .missing)
		}
	}
}

extension Storage {
	public var attributes: [FileAttributeKey : Any] {
		return (try? fileSystem.attributesOfItem(atPath: path)) ?? [:]
	}

	public func makeParentPath(for path: String) -> String? {
		guard path != "/" else { return nil }
		let url = URL(fileURLWithPath: path)
		let components = url.pathComponents.dropFirst().dropLast()
		guard !components.isEmpty else { return "/" }
		return "/" + components.joined(separator: "/") + "/"
	}

	@discardableResult
	public func move(
		to newPath: String,
		errorReasonProvider: (Error) -> LocationErrorReason
	) throws (LocationError) -> Storage {
		do {
			try fileSystem.moveItem(
				at: URL(fileURLWithPath: path),
				to: URL(fileURLWithPath: newPath)
			)

			switch LocationType.kind {
			case .file:
				path = newPath
			case .folder:
				path = newPath.appendingSuffixIfNeeded("/")
			}

			return try Storage(path: path)
		} catch {
			throw LocationError(path: path, reason: errorReasonProvider(error))
		}
	}

	@discardableResult
	public func copy(to newPath: String) throws (LocationError) -> Storage {
		do {
			try fileSystem.copyItem(
				at: URL(fileURLWithPath: path),
				to: URL(fileURLWithPath: newPath)
			)
			return try Storage(path: newPath)
		} catch {
			throw LocationError(path: path, reason: .copyFailed(error))
		}
	}

	public func delete() throws (LocationError) {
		do {
			try fileSystem.removeItem(at: URL(fileURLWithPath: path))
		} catch {
			throw LocationError(path: path, reason: .deleteFailed(error))
		}
	}
}

extension Storage where LocationType == Folder {
	public func makeChildSequence<T: Location>() -> Folder.ChildSequence<T> {
		return Folder.ChildSequence(
			folder: Folder(storage: self),
			fileSystem: fileSystem,
			isRecursive: false,
			includeHidden: false
		)
	}

	public func subfolder(at folderPath: String) throws (LocationError) -> Folder {
		let folderPath = path + folderPath.removingPrefix("/")
		let storage = Storage<Folder>(uncheckedPath: folderPath)
		try storage.validatePath()
		return Folder(storage: storage)
	}

	public func file(at filePath: String) throws (LocationError) -> File {
		let filePath = path + filePath.removingPrefix("/")
		let storage = Storage<File>(uncheckedPath: filePath)
		try storage.validatePath()
		return File(storage: storage)
	}

	public func createSubfolder(at folderPath: String) throws (WriteError) -> Folder {
		let folderPath = path + folderPath.removingPrefix("/")

		guard folderPath != path else {
			throw WriteError(path: folderPath, reason: .emptyPath)
		}

		do {
			try fileSystem.createDirectory(
				at: URL(fileURLWithPath: folderPath, isDirectory: true),
				withIntermediateDirectories: true
			)

			let storage = try Storage(path: folderPath)
			return Folder(storage: storage)
		} catch {
			throw WriteError(path: folderPath, reason: .folderCreationFailed(error))
		}
	}

	public func createFile(at filePath: String, contents: Data?) throws (WriteError) -> File {
		let filePath = path + filePath.removingPrefix("/")

		guard let parentPath = makeParentPath(for: filePath) else {
			throw WriteError(path: filePath, reason: .emptyPath)
		}

		if parentPath != path {
			do {
				try fileSystem.createDirectory(
					at: URL(fileURLWithPath: parentPath, isDirectory: true),
					withIntermediateDirectories: true
				)
			} catch {
				throw WriteError(path: parentPath, reason: .folderCreationFailed(error))
			}
		}

		guard fileSystem.createFile(
			at: URL(fileURLWithPath: filePath),
			contents: contents
		),
			let storage = try? Storage<File>(path: filePath)
		else {
			throw WriteError(path: filePath, reason: .fileCreationFailed)
		}

		return File(storage: storage)
	}
}

// MARK: - Files

/// Type that represents a file on disk. You can either reference an existing
/// file by initializing an instance with a `path`, or you can create new files
/// using the various `createFile...` APIs available on `Folder`.
public struct File: Location {
	public let storage: Storage<File>

	public init(storage: Storage<File>) {
		self.storage = storage
	}
}

extension File {
	public static var kind: LocationKind {
		return .file
	}

	/// Write a new set of binary data into the file, replacing its current contents.
	/// - parameter data: The binary data to write.
	/// - throws: `WriteError` in case the operation couldn't be completed.
	public func write(_ data: Data) throws (WriteError) {
		do {
			try storage.fileSystem.write(data, to: url)
		} catch {
			throw WriteError(path: path, reason: .writeFailed(error))
		}
	}

	/// Write a new string into the file, replacing its current contents.
	/// - parameter string: The string to write.
	/// - parameter encoding: The encoding of the string (default: `UTF8`).
	/// - throws: `WriteError` in case the operation couldn't be completed.
	public func write(_ string: String, encoding: String.Encoding = .utf8) throws (WriteError) {
		guard let data = string.data(using: encoding) else {
			throw WriteError(path: path, reason: .stringEncodingFailed(string))
		}

		return try write(data)
	}

	/// Append a set of binary data to the file's existing contents.
	/// - parameter data: The binary data to append.
	/// - throws: `WriteError` in case the operation couldn't be completed.
	public func append(_ data: Data) throws (WriteError) {
		do {
			try storage.fileSystem.append(data, to: url)
		} catch {
			throw WriteError(path: path, reason: .writeFailed(error))
		}
	}

	/// Append a string to the file's existing contents.
	/// - parameter string: The string to append.
	/// - parameter encoding: The encoding of the string (default: `UTF8`).
	/// - throws: `WriteError` in case the operation couldn't be completed.
	public func append(_ string: String, encoding: String.Encoding = .utf8) throws (WriteError) {
		guard let data = string.data(using: encoding) else {
			throw WriteError(path: path, reason: .stringEncodingFailed(string))
		}

		return try append(data)
	}

	/// Read the contents of the file as binary data.
	/// - throws: `ReadError` if the file couldn't be read.
	public func read() throws (ReadError) -> Data {
		do { return try storage.fileSystem.data(at: url) }
		catch { throw ReadError(path: path, reason: .readFailed(error)) }
	}

	/// Read the contents of the file as a string.
	/// - parameter encoding: The encoding to decode the file's data using (default: `UTF8`).
	/// - throws: `ReadError` if the file couldn't be read, or if a string couldn't
	///   be decoded from the file's contents.
	public func readAsString(encodedAs encoding: String.Encoding = .utf8) throws (ReadError) -> String {
		guard let string = try String(data: read(), encoding: encoding) else {
			throw ReadError(path: path, reason: .stringDecodingFailed)
		}

		return string
	}

	/// Read the contents of the file as an integer.
	/// - throws: `ReadError` if the file couldn't be read, or if the file's
	///   contents couldn't be converted into an integer.
	public func readAsInt() throws (ReadError) -> Int {
		let string = try readAsString()

		guard let int = Int(string) else {
			throw ReadError(path: path, reason: .notAnInt(string))
		}

		return int
	}
}

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
extension File {
	/// Open the file.
	public func open() {
		storage.fileSystem.open(url)
	}
}
#endif

// MARK: - Folders

/// Type that represents a folder on disk. You can either reference an existing
/// folder by initializing an instance with a `path`, or you can create new
/// subfolders using this type's various `createSubfolder...` APIs.
public struct Folder: Location {
	public let storage: Storage<Folder>

	public init(storage: Storage<Folder>) {
		self.storage = storage
	}
}

extension Folder {
	/// A sequence of child locations contained within a given folder.
	/// You obtain an instance of this type by accessing either `files`
	/// or `subfolders` on a `Folder` instance.
	public struct ChildSequence<Child: Location>: Sequence {
		fileprivate let folder: Folder
		fileprivate let fileSystem: any FileSystem
		fileprivate var isRecursive: Bool
		fileprivate var includeHidden: Bool

		public func makeIterator() -> ChildIterator<Child> {
			return ChildIterator(
				folder: folder,
				isRecursive: isRecursive,
				includeHidden: includeHidden,
				reverseTopLevelTraversal: false
			)
		}
	}

	/// The type of iterator used by `ChildSequence`. You don't interact
	/// with this type directly. See `ChildSequence` for more information.
	public struct ChildIterator<Child: Location>: IteratorProtocol {
		private let folder: Folder
		private let isRecursive: Bool
		private let includeHidden: Bool
		private let reverseTopLevelTraversal: Bool
		private lazy var itemNames = loadItemNames()
		private var index = 0
		private var nestedIterators = [ChildIterator<Child>]()

		@Dependency(\.fileSystem)
		private var fileSystem

		fileprivate init(
			folder: Folder,
			isRecursive: Bool,
			includeHidden: Bool,
			reverseTopLevelTraversal: Bool
		) {
			self.folder = folder
			self.isRecursive = isRecursive
			self.includeHidden = includeHidden
			self.reverseTopLevelTraversal = reverseTopLevelTraversal
		}

		public mutating func next() -> Child? {
			guard index < itemNames.count else {
				guard var nested = nestedIterators.first else {
					return nil
				}

				guard let child = nested.next() else {
					nestedIterators.removeFirst()
					return next()
				}

				nestedIterators[0] = nested
				return child
			}

			let name = itemNames[index]
			index += 1

			if !includeHidden {
				guard !name.hasPrefix(".") else { return next() }
			}

			let childPath = folder.path + name.removingPrefix("/")
			let childStorage = try? Storage<Child>(
				path: childPath
			)
			let child = childStorage.map(Child.init)

			if isRecursive {
				let childFolder = (child as? Folder) ?? (try? Folder(
					storage: Storage(path: childPath)
				))

				if let childFolder = childFolder {
					let nested = ChildIterator(
						folder: childFolder,
						isRecursive: true,
						includeHidden: includeHidden,
						reverseTopLevelTraversal: false
					)

					nestedIterators.append(nested)
				}
			}

			return child ?? next()
		}

		private mutating func loadItemNames() -> [String] {
			let contents = try? fileSystem.contentsOfDirectory(at: folder.url)
			let names = contents?.map(\.lastPathComponent).sorted() ?? []
			return reverseTopLevelTraversal ? names.reversed() : names
		}
	}
}

extension Folder.ChildSequence: CustomStringConvertible {
	public var description: String {
		return lazy.map({ $0.description }).joined(separator: "\n")
	}
}

extension Folder.ChildSequence {
	/// Return a new instance of this sequence that'll traverse the folder's
	/// contents recursively, in a breadth-first manner. Complexity: `O(1)`.
	public var recursive: Folder.ChildSequence<Child> {
		var sequence = self
		sequence.isRecursive = true
		return sequence
	}

	/// Return a new instance of this sequence that'll include all hidden
	/// (dot) files when traversing the folder's contents. Complexity: `O(1)`.
	public var includingHidden: Folder.ChildSequence<Child> {
		var sequence = self
		sequence.includeHidden = true
		return sequence
	}

	/// Count the number of locations contained within this sequence.
	/// Complexity: `O(N)`.
	public func count() -> Int {
		return reduce(0) { count, _ in count + 1 }
	}

	/// Gather the names of all of the locations contained within this sequence.
	/// Complexity: `O(N)`.
	public func names() -> [String] {
		return map { $0.name }
	}

	/// Return the last location contained within this sequence.
	/// Complexity: `O(N)`.
	public func last() -> Child? {
		var iterator = Iterator(
			folder: folder,
			isRecursive: isRecursive,
			includeHidden: includeHidden,
			reverseTopLevelTraversal: !isRecursive
		)

		guard isRecursive else { return iterator.next() }

		var child: Child?

		while let nextChild = iterator.next() {
			child = nextChild
		}

		return child
	}

	/// Return the first location contained within this sequence.
	/// Complexity: `O(1)`.
	public var first: Child? {
		var iterator = makeIterator()
		return iterator.next()
	}

	/// Move all locations within this sequence to a new parent folder.
	/// - parameter folder: The folder to move all locations to.
	/// - throws: `LocationError` if the move couldn't be completed.
	public func move(to folder: Folder) throws (LocationError) {
		for child in self {
			try child.move(to: folder)
		}
	}

	/// Delete all of the locations within this sequence. All items will
	/// be permanently deleted. Use with caution.
	/// - throws: `LocationError` if an item couldn't be deleted. Note that
	///   all items deleted up to that point won't be recovered.
	public func delete() throws (LocationError) {
		for child in self {
			try child.delete()
		}
	}
}

extension Folder {
	public static var kind: LocationKind {
		return .folder
	}

	/// The folder that the program is currently operating in.
	public static var current: Folder {
		return try! Folder(path: "")
	}

	/// The root folder of the file system.
	public static var root: Folder {
		return try! Folder(path: "/")
	}

	/// The current user's Home folder.
	public static var home: Folder {
		return try! Folder(path: "~")
	}

	/// The system's temporary folder.
	public static var temporary: Folder {
		@Dependency(\.fileSystem)
		var fileSystem

		return try! Folder(storage: Storage(
			path: fileSystem.temporaryDirectoryURL.path
		))
	}

	/// A sequence containing all of this folder's subfolders. Initially
	/// non-recursive, use `recursive` on the returned sequence to change that.
	public var subfolders: ChildSequence<Folder> {
		return storage.makeChildSequence()
	}

	/// A sequence containing all of this folder's files. Initially
	/// non-recursive, use `recursive` on the returned sequence to change that.
	public var files: ChildSequence<File> {
		return storage.makeChildSequence()
	}

	/// Return a subfolder at a given path within this folder.
	/// - parameter path: A relative path within this folder.
	/// - throws: `LocationError` if the subfolder couldn't be found.
	public func subfolder(at path: String) throws (LocationError) -> Folder {
		return try storage.subfolder(at: path)
	}

	/// Return a subfolder with a given name.
	/// - parameter name: The name of the subfolder to return.
	/// - throws: `LocationError` if the subfolder couldn't be found.
	public func subfolder(named name: String) throws (LocationError) -> Folder {
		return try storage.subfolder(at: name)
	}

	/// Return whether this folder contains a subfolder at a given path.
	/// - parameter path: The relative path of the subfolder to look for.
	public func containsSubfolder(at path: String) -> Bool {
		return (try? subfolder(at: path)) != nil
	}

	/// Return whether this folder contains a subfolder with a given name.
	/// - parameter name: The name of the subfolder to look for.
	public func containsSubfolder(named name: String) -> Bool {
		return (try? subfolder(named: name)) != nil
	}

	/// Create a new subfolder at a given path within this folder. In case
	/// the intermediate folders between this folder and the new one don't
	/// exist, those will be created as well. This method throws an error
	/// if a folder already exists at the given path.
	/// - parameter path: The relative path of the subfolder to create.
	/// - throws: `WriteError` if the operation couldn't be completed.
	@discardableResult
	public func createSubfolder(at path: String) throws (WriteError) -> Folder {
		return try storage.createSubfolder(at: path)
	}

	/// Create a new subfolder with a given name. This method throws an error
	/// if a subfolder with the given name already exists.
	/// - parameter name: The name of the subfolder to create.
	/// - throws: `WriteError` if the operation couldn't be completed.
	@discardableResult
	public func createSubfolder(named name: String) throws (WriteError) -> Folder {
		return try storage.createSubfolder(at: name)
	}

	/// Create a new subfolder at a given path within this folder. In case
	/// the intermediate folders between this folder and the new one don't
	/// exist, those will be created as well. If a folder already exists at
	/// the given path, then it will be returned without modification.
	/// - parameter path: The relative path of the subfolder.
	/// - throws: `WriteError` if a new folder couldn't be created.
	@discardableResult
	public func createSubfolderIfNeeded(at path: String) throws (WriteError) -> Folder {
		if let subfolder = try? subfolder(at: path) { return subfolder }
		return try createSubfolder(at: path)
	}

	/// Create a new subfolder with a given name. If a subfolder with the given
	/// name already exists, then it will be returned without modification.
	/// - parameter name: The name of the subfolder.
	/// - throws: `WriteError` if a new folder couldn't be created.
	@discardableResult
	public func createSubfolderIfNeeded(withName name: String) throws (WriteError) -> Folder {
		if let subfolder = try? subfolder(named: name) { return subfolder }
		return try createSubfolder(named: name)
	}

	/// Return a file at a given path within this folder.
	/// - parameter path: A relative path within this folder.
	/// - throws: `LocationError` if the file couldn't be found.
	public func file(at path: String) throws (LocationError) -> File {
		return try storage.file(at: path)
	}

	/// Return a file within this folder with a given name.
	/// - parameter name: The name of the file to return.
	/// - throws: `LocationError` if the file couldn't be found.
	public func file(named name: String) throws (LocationError) -> File {
		return try storage.file(at: name)
	}

	/// Return whether this folder contains a file at a given path.
	/// - parameter path: The relative path of the file to look for.
	func containsFile(at path: String) -> Bool {
		return (try? file(at: path)) != nil
	}

	/// Return whether this folder contains a file with a given name.
	/// - parameter name: The name of the file to look for.
	public func containsFile(named name: String) -> Bool {
		return (try? file(named: name)) != nil
	}

	/// Create a new file at a given path within this folder. In case
	/// the intermediate folders between this folder and the new file don't
	/// exist, those will be created as well. This method throws an error
	/// if a file already exists at the given path.
	/// - parameter path: The relative path of the file to create.
	/// - parameter contents: The initial `Data` that the file should contain.
	/// - throws: `WriteError` if the operation couldn't be completed.
	@discardableResult
	public func createFile(at path: String, contents: Data? = nil) throws (WriteError) -> File {
		return try storage.createFile(at: path, contents: contents)
	}

	/// Create a new file with a given name. This method throws an error
	/// if a file with the given name already exists.
	/// - parameter name: The name of the file to create.
	/// - parameter contents: The initial `Data` that the file should contain.
	/// - throws: `WriteError` if the operation couldn't be completed.
	@discardableResult
	public func createFile(named fileName: String, contents: Data? = nil) throws (WriteError) -> File {
		return try storage.createFile(at: fileName, contents: contents)
	}

	/// Create a new file at a given path within this folder. In case
	/// the intermediate folders between this folder and the new file don't
	/// exist, those will be created as well. If a file already exists at
	/// the given path, then it will be returned without modification.
	/// - parameter path: The relative path of the file.
	/// - parameter contents: The initial `Data` that any newly created file
	///   should contain. Will only be evaluated if needed.
	/// - throws: `WriteError` if a new file couldn't be created.
	@discardableResult
	public func createFileIfNeeded(
		at path: String,
		contents: @autoclosure () -> Data? = nil
	) throws (WriteError) -> File {
		if let existing = try? file(at: path) { return existing }
		return try createFile(at: path, contents: contents())
	}

	/// Create a new file with a given name. If a file with the given
	/// name already exists, then it will be returned without modification.
	/// - parameter name: The name of the file.
	/// - parameter contents: The initial `Data` that any newly created file
	///   should contain. Will only be evaluated if needed.
	/// - throws: `WriteError` if a new file couldn't be created.
	@discardableResult
	public func createFileIfNeeded(
		withName name: String,
		contents: @autoclosure () -> Data? = nil
	) throws -> File {
		return try (try? file(named: name)) ?? createFile(named: name, contents: contents())
	}

	/// Return whether this folder contains a given location as a direct child.
	/// - parameter location: The location to find.
	public func contains<T: Location>(_ location: T) -> Bool {
		switch T.kind {
		case .file: return containsFile(named: location.name)
		case .folder: return containsSubfolder(named: location.name)
		}
	}

	/// Move the contents of this folder to a new parent
	/// - parameter folder: The new parent folder to move this folder's contents to.
	/// - parameter includeHidden: Whether hidden files should be included (default: `false`).
	/// - throws: `LocationError` if the operation couldn't be completed.
	public func moveContents(to folder: Folder, includeHidden: Bool = false) throws {
		var files = self.files
		files.includeHidden = includeHidden
		try files.move(to: folder)

		var folders = subfolders
		folders.includeHidden = includeHidden
		try folders.move(to: folder)
	}

	/// Empty this folder, permanently deleting all of its contents. Use with caution.
	/// - parameter includeHidden: Whether hidden files should also be deleted (default: `false`).
	/// - throws: `LocationError` if the operation couldn't be completed.
	public func empty(includingHidden includeHidden: Bool = false) throws {
		var files = self.files
		files.includeHidden = includeHidden
		try files.delete()

		var folders = subfolders
		folders.includeHidden = includeHidden
		try folders.delete()
	}

	public func isEmpty(includingHidden includeHidden: Bool = false) -> Bool {
		var files = self.files
		files.includeHidden = includeHidden

		if files.first != nil {
			return false
		}

		var folders = subfolders
		folders.includeHidden = includeHidden
		return folders.first == nil
	}
}

#if os(iOS) || os(tvOS) || os(macOS)
extension Folder {
	/// Resolve a folder that matches a search path within a given domain.
	/// - parameter searchPath: The directory path to search for.
	/// - parameter domain: The domain to search in.
	/// - parameter fileManager: Which file manager to search using.
	/// - throws: `LocationError` if no folder could be resolved.
	public static func matching(
		_ searchPath: FileManager.SearchPathDirectory,
		in domain: FileManager.SearchPathDomainMask = .userDomainMask,
		resolvedBy fileManager: FileManager? = nil
	) throws -> Folder {
		@Dependency(\.fileSystem)
		var dependencyFileSystem

		let fileSystem: any FileSystem
		if let fileManager {
			fileSystem = _FileSystem(manager: fileManager)
		} else {
			fileSystem = dependencyFileSystem
		}

		return try matching(
			searchPath,
			in: domain,
			resolvedBy: fileSystem
		)
	}

	/// Resolve a folder that matches a search path using a given file system.
	/// - parameter searchPath: The directory path to search for.
	/// - parameter domain: The domain to search in.
	/// - parameter fileSystem: Which file system to search using.
	/// - throws: `LocationError` if no folder could be resolved.
	public static func matching(
		_ searchPath: FileManager.SearchPathDirectory,
		in domain: FileManager.SearchPathDomainMask = .userDomainMask,
		resolvedBy fileSystem: any FileSystem
	) throws -> Folder {
		let urls = fileSystem.urls(for: searchPath, in: domain)

		guard let match = urls.first else {
			throw LocationError(
				path: "",
				reason: .unresolvedSearchPath(searchPath, domain: domain)
			)
		}

		return try Folder(storage: Storage(
			path: match.relativePath
		))
	}

	/// The current user's Documents folder
	public static var documents: Folder? {
		return try? .matching(.documentDirectory)
	}

	/// The current user's Library folder
	public static var library: Folder? {
		return try? .matching(.libraryDirectory)
	}
}
#endif

// MARK: - Errors

/// Error type thrown by all of Files' throwing APIs.
public struct FilesError<Reason: Sendable>: Error {
	/// The absolute path that the error occured at.
	private(set) public var path: String

	/// The reason that the error occured.
	private(set) public var reason: Reason

	/// Initialize an instance with a path and a reason.
	/// - parameter path: The absolute path that the error occured at.
	/// - parameter reason: The reason that the error occured.
	init(path: String, reason: Reason) {
		self.path = path
		self.reason = reason
	}
}

extension FilesError: CustomStringConvertible {
	public var description: String {
		return """
		Files encountered an error at '\(path)'.
		Reason: \(reason)
		"""
	}
}

public enum FilesErrorReason: Sendable {
	case read(ReadErrorReason)
	case write(WriteErrorReason)
	case location(LocationErrorReason)
}

/// Enum listing reasons that a read operation could fail.
public enum ReadErrorReason: Sendable {
	/// A file couldn't be read because of an underlying system error.
	case readFailed(Error)

	/// Failed to decode a given set of data into a string.
	case stringDecodingFailed

	/// Encountered a string that doesn't contain an integer.
	case notAnInt(String)
}

/// Enum listing reasons that a write operation could fail.
public enum WriteErrorReason: Sendable {
	/// An empty path was given when writing or creating a location.
	case emptyPath

	/// A folder couldn't be created because of an underlying system error.
	case folderCreationFailed(Error)

	/// A file couldn't be created.
	case fileCreationFailed

	/// A file couldn't be written to because of an underlying system error.
	case writeFailed(Error)

	/// Failed to encode a string into binary data.
	case stringEncodingFailed(String)
}

/// Enum listing reasons that a location manipulation could fail.
public enum LocationErrorReason: Sendable {
	/// The location couldn't be found.
	case missing

	/// An empty path was given when refering to a file.
	case emptyFilePath

	/// The user attempted to rename the file system's root folder.
	case cannotRenameRoot

	/// A rename operation failed with an underlying system error.
	case renameFailed(Error)

	/// A move operation failed with an underlying system error.
	case moveFailed(Error)

	/// A copy operation failed with an underlying system error.
	case copyFailed(Error)

	/// A delete operation failed with an underlying system error.
	case deleteFailed(Error)

	/// A search path couldn't be resolved within a given domain.
	case unresolvedSearchPath(
		FileManager.SearchPathDirectory,
		domain: FileManager.SearchPathDomainMask
	)
}

/// Error thrown by read operations - such as when reading a file's contents.
public typealias ReadError = FilesError<ReadErrorReason>

/// Error thrown by write operations - such as file/folder creation.
public typealias WriteError = FilesError<WriteErrorReason>

/// Error thrown by location operations - such as find, move, copy and delete.
public typealias LocationError = FilesError<LocationErrorReason>

/// Error thrown by location operations - such as find, move, copy and delete.
public typealias SomeFilesError = FilesError<FilesErrorReason>

extension SomeFilesError {
	@discardableResult
	static func `catch`<T>(_ catchError: () throws (ReadError) -> T) throws (SomeFilesError) -> T {
		do {
			return try catchError()
		} catch {
			throw Self(error)
		}
	}

	@discardableResult
	static func `catch`<T>(_ catchError: () throws (WriteError) -> T) throws (SomeFilesError) -> T {
		do {
			return try catchError()
		} catch {
			throw Self(error)
		}
	}

	@discardableResult
	static func `catch`<T>(_ catchError: () throws (LocationError) -> T) throws (SomeFilesError) -> T {
		do {
			return try catchError()
		} catch {
			throw Self(error)
		}
	}

	init(_ error: ReadError) {
		self.init(path: error.path, reason: .read(error.reason))
	}

	init(_ error: WriteError) {
		self.init(path: error.path, reason: .write(error.reason))
	}

	init(_ error: LocationError) {
		self.init(path: error.path, reason: .location(error.reason))
	}
}

// MARK: - Private system extensions

private extension FileSystem {
	func locationExists(at path: String, kind: LocationKind) -> Bool {
		guard fileExists(atPath: path) else {
			return false
		}

		switch kind {
		case .file: return !isDirectory(atPath: path)
		case .folder: return isDirectory(atPath: path)
		}
	}
}

private extension String {
	func removingPrefix(_ prefix: String) -> String {
		guard hasPrefix(prefix) else { return self }
		return String(dropFirst(prefix.count))
	}

	func removingSuffix(_ suffix: String) -> String {
		guard hasSuffix(suffix) else { return self }
		return String(dropLast(suffix.count))
	}

	func appendingSuffixIfNeeded(_ suffix: String) -> String {
		guard !hasSuffix(suffix) else { return self }
		return appending(suffix)
	}
}

// MARK: - Extensions

public protocol _Location {
	static var kind: LocationKind { get }
	var description: String { get }
	var path: String { get }
	var url: URL { get }
	var name: String { get }
	var nameExcludingExtension: String { get }
	var `extension`: String? { get }
	var parent: Folder? { get }
	var creationDate: Date? { get }
	var modificationDate: Date? { get }
	func path(relativeTo folder: Folder) -> String
	func rename(to newName: String, keepExtension: Bool) throws (LocationError) -> Self
	func move(to newParent: Folder) throws (LocationError) -> Self
	func delete() throws
}

extension File: _Location {}
extension Folder: _Location {}

public enum FSObject {
	case file(File)
	case folder(Folder)

	public var location: _Location {
		switch self {
		case let .file(location): return location
		case let .folder(location): return location
		}
	}
}

extension Folder {
	public func compactMapContents<T>(
		recursive: Bool = false,
		_ f: (FSObject) throws -> T?
	) rethrows -> [T] {
		let partialResult: [T] = try withoutActuallyEscaping(f) { f in
			try subfolders
				.sorted(by: { $0.name < $1.name })
				.compactMap { try f(.folder($0)) }
			+ files
				.sorted(by: { $0.name < $1.name })
				.compactMap { try f(.file($0)) }
		}

		return recursive
		? try partialResult + subfolders.flatMap { try $0.compactMapContents(recursive: recursive, f) }
		: partialResult
	}
}
