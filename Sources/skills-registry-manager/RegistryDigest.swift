import CryptoKit
import Foundation

internal enum RegistryDigest {
	internal static func digest(
		at rootURL: URL,
		fileManager: FileManager
	) throws -> RegistrySkill.Digest {
		var hasher = SHA256()

		func update(_ data: Data) {
			var length = UInt64(data.count).bigEndian
			withUnsafeBytes(of: &length) { bytes in
				hasher.update(data: Data(bytes))
			}
			hasher.update(data: data)
		}

		func update(_ string: String) {
			update(Data(string.utf8))
		}

		func visit(
			_ url: URL,
			relativePath: String
		) throws {
			let values = try url.resourceValues(
				forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
			)
			if values.isSymbolicLink == true {
				update("link")
				update(relativePath)
				update(try fileManager.destinationOfSymbolicLink(atPath: url.path))
				return
			}

			if values.isDirectory == true {
				update("directory")
				update(relativePath)
				let children = try fileManager.contentsOfDirectory(
					at: url,
					includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
				).sorted { $0.lastPathComponent < $1.lastPathComponent }
				for child in children {
					let childPath = relativePath.isEmpty
					? child.lastPathComponent
					: relativePath + "/" + child.lastPathComponent
					try visit(
						child,
						relativePath: childPath
					)
				}
				return
			}

			update("file")
			update(relativePath)
			update(try Data(contentsOf: url))
		}

		try visit(
			rootURL,
			relativePath: ""
		)
		let hash = hasher.finalize().map {
			String(
				format: "%02x",
				$0
			)
		}.joined()
		return .init(
			algorithm: "sha256",
			hash: hash
		)
	}
}
