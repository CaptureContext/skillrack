import Foundation
import SkillsManager

internal struct RegistryStorage: @unchecked Sendable {
	private struct Paths {
		internal let rootURL: URL
		internal let skillsURL: URL
		internal let stagingURL: URL
		internal let trashURL: URL
		internal let lockURL: URL

		internal init(rootURL: URL) {
			self.rootURL = rootURL
			self.skillsURL = rootURL.appending(
				path: "skills",
				directoryHint: .isDirectory
			)
			self.stagingURL = rootURL.appending(
				path: ".staging",
				directoryHint: .isDirectory
			)
			self.trashURL = rootURL.appending(
				path: ".trash",
				directoryHint: .isDirectory
			)
			self.lockURL = rootURL.appending(
				path: "storage.lock",
				directoryHint: .notDirectory
			)
		}

		internal func recordURL(_ id: RegistrySkill.ID) -> URL {
			skillsURL.appending(
				path: id.rawValue,
				directoryHint: .isDirectory
			)
		}

		internal func metadataURL(_ id: RegistrySkill.ID) -> URL {
			recordURL(id).appending(
				path: "skill.json",
				directoryHint: .notDirectory
			)
		}

		internal func contentURL(_ id: RegistrySkill.ID) -> URL {
			recordURL(id).appending(
				path: "content",
				directoryHint: .isDirectory
			)
		}
	}

	private let configuration: SkillsRegistryConfiguration
	private let decoder: JSONDecoder
	private let encoder: JSONEncoder
	private let fileManager: FileManager
	private let lock: RegistryStorageLock
	private let paths: Paths

	internal init(
		configuration: SkillsRegistryConfiguration,
		fileManager: FileManager
	) {
		let paths = Paths(rootURL: configuration.rootURL)
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		self.configuration = configuration
		self.decoder = decoder
		self.encoder = encoder
		self.fileManager = fileManager
		self.paths = paths
		self.lock = RegistryStorageLock(
			rootURL: paths.rootURL,
			lockURL: paths.lockURL,
			fileManager: fileManager
		)
	}

	internal func list() throws -> [RegistrySkill] {
		try prepare()
		return try listUnlocked()
	}

	internal func get(_ id: RegistrySkill.ID) throws -> RegistrySkill {
		try prepare()
		guard fileManager.fileExists(atPath: paths.metadataURL(id).path) else {
			throw SkillsRegistryError.skillNotFound(id)
		}

		return try loadMetadata(id)
	}

	internal func install(
		_ draft: RegistrySkillDraft,
		at date: Date,
		using skillsManager: SkillsManager
	) async throws -> RegistrySkill {
		try prepare()
		let staged = try await stageContent(
			draft,
			using: skillsManager
		)
		defer { try? fileManager.removeItem(at: staged.url) }
		let metadata = RegistrySkill(
			id: draft.id,
			name: draft.skill.name,
			description: draft.skill.description,
			source: draft.source,
			dependencies: draft.dependencies,
			digest: staged.digest,
			createdAt: date,
			updatedAt: date
		)
		try write(metadata, to: staged.url.appending(path: "skill.json"))

		try lock.withLock {
			guard !fileManager.fileExists(atPath: paths.recordURL(draft.id).path) else {
				throw SkillsRegistryError.skillAlreadyInstalled(draft.id)
			}

			let existing = try listUnlocked().first(where: {
				$0.source.matches(draft.source)
			})
			if let existing {
				throw SkillsRegistryError.skillAlreadyInstalled(existing.id)
			}
			for dependency in draft.dependencies
			where !fileManager.fileExists(atPath: paths.contentURL(dependency.skillID).path) {
				throw SkillsRegistryError.dependencyNotInstalled(dependency.skillID)
			}
			try fileManager.moveItem(
				at: staged.url,
				to: paths.recordURL(draft.id)
			)
		}

		return metadata
	}

	internal func update(
		_ draft: RegistrySkillDraft,
		at date: Date,
		using skillsManager: SkillsManager
	) async throws -> RegistrySkill {
		try prepare()
		let staged = try await stageContent(
			draft,
			using: skillsManager
		)
		defer { try? fileManager.removeItem(at: staged.url) }

		return try lock.withLock {
			let existing = try get(draft.id)
			guard existing.source.matches(draft.source) else {
				throw SkillsRegistryError.resolutionDoesNotMatchSource(draft.id)
			}
			for dependency in draft.dependencies
			where !fileManager.fileExists(atPath: paths.contentURL(dependency.skillID).path) {
				throw SkillsRegistryError.dependencyNotInstalled(dependency.skillID)
			}

			let metadata = RegistrySkill(
				id: existing.id,
				name: draft.skill.name,
				displayName: existing.displayName,
				description: draft.skill.description,
				source: draft.source,
				dependencies: draft.dependencies,
				digest: staged.digest,
				links: existing.links,
				createdAt: existing.createdAt,
				updatedAt: date
			)
			try write(metadata, to: staged.url.appending(path: "skill.json"))

			let recordURL = paths.recordURL(draft.id)
			let backupURL = paths.trashURL.appending(
				path: draft.id.rawValue + "-" + UUID().uuidString.lowercased(),
				directoryHint: .isDirectory
			)
			try fileManager.moveItem(
				at: recordURL,
				to: backupURL
			)
			do {
				try fileManager.moveItem(
					at: staged.url,
					to: recordURL
				)
			} catch {
				try? fileManager.moveItem(
					at: backupURL,
					to: recordURL
				)
				throw error
			}
			try? fileManager.removeItem(at: backupURL)
			return metadata
		}
	}

	internal func uninstall(_ id: RegistrySkill.ID) throws {
		try prepare()
		try lock.withLock {
			let skill = try get(id)
			guard skill.links.isEmpty else {
				throw SkillsRegistryError.skillHasLinks(id)
			}

			let dependents = try listUnlocked().filter { skill in
				skill.dependencies.contains { $0.skillID == id }
			}.map(\.id)
			guard dependents.isEmpty else {
				throw SkillsRegistryError.skillHasDependents(
					id,
					dependents
				)
			}

			let trashURL = paths.trashURL.appending(
				path: id.rawValue + "-" + UUID().uuidString.lowercased(),
				directoryHint: .isDirectory
			)
			try fileManager.moveItem(
				at: paths.recordURL(id),
				to: trashURL
			)
			try? fileManager.removeItem(at: trashURL)
		}
	}

	internal func link(
		_ skillID: RegistrySkill.ID,
		to requestedTarget: LinkTarget,
		alias requestedAlias: String?,
		at date: Date
	) throws -> SkillLink {
		try prepare()
		return try lock.withLock {
			var skill = try get(skillID)
			let alias = requestedAlias ?? skill.name
			try validateAlias(alias)
			let target = try normalized(requestedTarget)
			let link = SkillLink(
				skillID: skillID,
				target: target,
				alias: alias
			)
			let directoryURL = try directoryURL(for: target)
			let linkURL = directoryURL.appending(path: alias)
			let contentURL = paths.contentURL(skillID)

			try fileManager.createDirectory(
				at: directoryURL,
				withIntermediateDirectories: true
			)
			var createdLink = false
			if itemExists(at: linkURL) {
				guard
					symbolicLink(
						at: linkURL,
						pointsTo: contentURL
					)
				else {
					throw SkillsRegistryError.linkCollision(linkURL)
				}

			} else {
				try fileManager.createSymbolicLink(
					at: linkURL,
					withDestinationURL: contentURL
				)
				createdLink = true
			}

			if !skill.links.contains(link) {
				skill.links.append(link)
				skill.links.sort { lhs, rhs in
					String(describing: lhs.target) + lhs.alias
						< String(describing: rhs.target) + rhs.alias
				}
				skill.updatedAt = date
				do {
					try save(skill)
				} catch {
					if createdLink { try? fileManager.removeItem(at: linkURL) }
					throw error
				}
			}

			return link
		}
	}

	internal func unlink(_ link: SkillLink, at date: Date) throws {
		try prepare()
		try lock.withLock {
			try validateAlias(link.alias)
			var skill = try get(link.skillID)
			let target = try normalized(link.target)
			let normalizedLink = SkillLink(
				skillID: link.skillID,
				target: target,
				alias: link.alias
			)
			let linkURL = try directoryURL(for: target).appending(path: link.alias)
			guard symbolicLink(at: linkURL, pointsTo: paths.contentURL(link.skillID)) else {
				throw SkillsRegistryError.linkDoesNotBelongToRegistry(linkURL)
			}

			try fileManager.removeItem(at: linkURL)
			skill.links.removeAll { $0 == normalizedLink }
			skill.updatedAt = date
			do {
				try save(skill)
			} catch {
				try? fileManager.createSymbolicLink(
					at: linkURL,
					withDestinationURL: paths.contentURL(link.skillID)
				)
				throw error
			}
		}
	}

	internal func verify() throws -> RegistryVerificationReport {
		let skills = try list()
		let installedIDs = Set(skills.map(\.id))
		var issues: [RegistryVerificationReport.Issue] = []
		for skill in skills {
			let contentURL = paths.contentURL(skill.id)
			guard fileManager.fileExists(atPath: contentURL.path) else {
				issues.append(.missingContent(skill.id))
				continue
			}

			let digest = try RegistryDigest.digest(
				at: contentURL,
				fileManager: fileManager
			)
			if digest != skill.digest {
				issues.append(.digestMismatch(skill.id))
			}
			for dependency in skill.dependencies {
				if !installedIDs.contains(dependency.skillID) {
					issues.append(
						.missingDependency(
							skill.id,
							dependency.skillID
						)
					)
					continue
				}
				guard dependency.kind == .embedded else { continue }
				let linkURL = contentURL.appending(path: dependency.path)
				let isValidDependencyLink = symbolicLink(
					at: linkURL,
					pointsTo: paths.contentURL(dependency.skillID)
				)
				if !isValidDependencyLink {
					issues.append(
						.brokenDependencyLink(
							skill.id,
							dependency.path
						)
					)
				}
			}
			for link in skill.links {
				let linkURL = try directoryURL(for: link.target).appending(path: link.alias)
				if !symbolicLink(
					at: linkURL,
					pointsTo: contentURL
				) {
					issues.append(
						.brokenToolLink(
							skill.id,
							link
						)
					)
				}
			}
		}
		return .init(issues: issues)
	}
}

extension RegistryStorage {
	fileprivate struct StagedContent {
		fileprivate let url: URL
		fileprivate let digest: RegistrySkill.Digest
	}

	fileprivate func stageContent(
		_ draft: RegistrySkillDraft,
		using skillsManager: SkillsManager
	) async throws -> StagedContent {
		let stageURL = paths.stagingURL.appending(
			path: draft.id.rawValue + "-" + UUID().uuidString.lowercased(),
			directoryHint: .isDirectory
		)
		let payloadsURL = stageURL.appending(
			path: "payloads",
			directoryHint: .isDirectory
		)
		let stagedContentURL = stageURL.appending(
			path: "content",
			directoryHint: .isDirectory
		)

		do {
			try fileManager.createDirectory(
				at: stageURL,
				withIntermediateDirectories: true,
				attributes: [.posixPermissions: 0o700]
			)
			_ = try await skillsManager.saveSkill(
				draft.skill,
				payloadsURL
			)
			let materializedURL = payloadsURL.appending(
				path: draft.skill.name,
				directoryHint: .isDirectory
			)
			try fileManager.moveItem(
				at: materializedURL,
				to: stagedContentURL
			)
			try? fileManager.removeItem(at: payloadsURL)

			for dependency in draft.dependencies where dependency.kind == .embedded {
				try validateDependencyPath(dependency.path)
				let stagedLinkURL = stagedContentURL.appending(path: dependency.path)
				let finalLinkURL = paths.contentURL(draft.id).appending(path: dependency.path)
				let finalTargetURL = paths.contentURL(dependency.skillID)
				if itemExists(at: stagedLinkURL) {
					try fileManager.removeItem(at: stagedLinkURL)
				}
				try fileManager.createDirectory(
					at: stagedLinkURL.deletingLastPathComponent(),
					withIntermediateDirectories: true
				)
				try fileManager.createSymbolicLink(
					atPath: stagedLinkURL.path,
					withDestinationPath: relativePath(
						from: finalLinkURL.deletingLastPathComponent(),
						to: finalTargetURL
					)
				)
			}

			return StagedContent(
				url: stageURL,
				digest: try RegistryDigest.digest(
					at: stagedContentURL,
					fileManager: fileManager
				)
			)
		} catch {
			try? fileManager.removeItem(at: stageURL)
			throw error
		}
	}

	fileprivate func prepare() throws {
		for url in [paths.rootURL, paths.skillsURL, paths.stagingURL, paths.trashURL] {
			try fileManager.createDirectory(
				at: url,
				withIntermediateDirectories: true,
				attributes: [.posixPermissions: 0o700]
			)
		}
	}

	fileprivate func listUnlocked() throws -> [RegistrySkill] {
		guard fileManager.fileExists(atPath: paths.skillsURL.path) else { return [] }

		return try fileManager.contentsOfDirectory(
			at: paths.skillsURL,
			includingPropertiesForKeys: [.isDirectoryKey],
			options: [.skipsHiddenFiles]
		)
		.compactMap { url -> RegistrySkill.ID? in
			guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
				return nil
			}

			guard let id = RegistrySkill.ID(rawValue: url.lastPathComponent) else {
				throw SkillsRegistryError.invalidRegistrySkillID(url.lastPathComponent)
			}

			return id
		}
		.map(loadMetadata)
		.sorted { lhs, rhs in
			if lhs.name == rhs.name { return lhs.id.rawValue < rhs.id.rawValue }
			return lhs.name < rhs.name
		}
	}

	fileprivate func loadMetadata(_ id: RegistrySkill.ID) throws -> RegistrySkill {
		let metadata = try decoder.decode(
			RegistrySkill.self,
			from: Data(contentsOf: paths.metadataURL(id))
		)
		guard metadata.schemaVersion == "1.0" else {
			throw SkillsRegistryError.unsupportedSchemaVersion(metadata.schemaVersion)
		}
		guard metadata.id == id else {
			throw SkillsRegistryError.invalidStorage(
				"Directory \(id.rawValue) contains metadata for \(metadata.id.rawValue)."
			)
		}
		guard
			metadata.digest.algorithm == "sha256",
			metadata.digest.hash.count == 64,
			metadata.digest.hash.allSatisfy({ $0.isHexDigit && !$0.isUppercase })
		else {
			throw SkillsRegistryError.invalidStorage(
				"Skill \(id.rawValue) has an invalid SHA-256 digest."
			)
		}

		var dependencyPaths: Set<String> = []
		for dependency in metadata.dependencies {
			try validateDependencyPath(dependency.path)
			guard dependencyPaths.insert(dependency.path).inserted else {
				throw SkillsRegistryError.invalidStorage(
					"Skill \(id.rawValue) repeats dependency path \(dependency.path)."
				)
			}
		}
		for link in metadata.links {
			guard link.skillID == id else {
				throw SkillsRegistryError.invalidStorage(
					"Skill \(id.rawValue) contains a link owned by \(link.skillID.rawValue)."
				)
			}

			try validateAlias(link.alias)
			_ = try normalized(link.target)
		}
		return metadata
	}

	fileprivate func save(_ skill: RegistrySkill) throws {
		try write(skill, to: paths.metadataURL(skill.id))
	}

	fileprivate func write(_ skill: RegistrySkill, to url: URL) throws {
		try encoder.encode(skill).write(
			to: url,
			options: [.atomic]
		)
	}

	fileprivate func validateAlias(_ alias: String) throws {
		let pattern: Regex<Substring> = /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/
		guard
			(1...64).contains(alias.count),
			alias.wholeMatch(of: pattern) != nil
		else {
			throw SkillsRegistryError.invalidAlias(alias)
		}
	}

	fileprivate func validateDependencyPath(_ path: String) throws {
		let components = path.split(
			separator: "/",
			omittingEmptySubsequences: false
		)
		guard
			!path.isEmpty,
			!path.hasPrefix("/"),
			components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
		else {
			throw SkillsRegistryError.invalidDependencyPath(path)
		}
	}

	fileprivate func normalized(_ target: LinkTarget) throws -> LinkTarget {
		switch target {
		case .tool:
			return target

		case .directory(let url):
			guard url.isFileURL, url.path.hasPrefix("/") else {
				throw SkillsRegistryError.localSourceMustBeAbsolute(url)
			}
			return .directory(url.standardizedFileURL)
		}
	}

	fileprivate func directoryURL(for target: LinkTarget) throws -> URL {
		switch target {
		case .tool(let tool):
			return tool.skillsDirectoryURL(
				relativeTo: configuration.homeDirectoryURL
			).standardizedFileURL

		case .directory(let url):
			guard url.isFileURL, url.path.hasPrefix("/") else {
				throw SkillsRegistryError.localSourceMustBeAbsolute(url)
			}
			return url.standardizedFileURL
		}
	}

	fileprivate func itemExists(at url: URL) -> Bool {
		fileManager.fileExists(atPath: url.path)
			|| (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
	}

	fileprivate func symbolicLink(at linkURL: URL, pointsTo targetURL: URL) -> Bool {
		guard
			let destination = try? fileManager.destinationOfSymbolicLink(
				atPath: linkURL.path
			)
		else { return false }
		let resolved: URL
		if destination.hasPrefix("/") {
			resolved = URL(fileURLWithPath: destination)
		} else {
			resolved = linkURL.deletingLastPathComponent().appending(path: destination)
		}
		return resolved.standardizedFileURL.resolvingSymlinksInPath()
			== targetURL.standardizedFileURL.resolvingSymlinksInPath()
	}

	fileprivate func relativePath(from sourceURL: URL, to destinationURL: URL) -> String {
		let source = sourceURL.standardizedFileURL.pathComponents
		let destination = destinationURL.standardizedFileURL.pathComponents
		var commonCount = 0
		while commonCount < source.count,
			commonCount < destination.count,
			source[commonCount] == destination[commonCount]
		{
			commonCount += 1
		}
		let components =
			Array(
				repeating: "..",
				count: source.count - commonCount
			)
			+ Array(destination[commonCount...])
		return components.joined(separator: "/")
	}
}
