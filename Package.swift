// swift-tools-version: 6.1

import PackageDescription

let package = Package(
	name: "skillrack",
	platforms: [
		.macOS(.v15)
	],
	products: [
		.executable(
			name: "skillrack",
			targets: ["skillrack"]
		),
		.library(
			name: "SkillsManager",
			targets: ["SkillsManager"]
		),
		.library(
			name: "SkillsRegistryManager",
			targets: ["SkillsRegistryManager"]
		),
	],
	dependencies: [
		.package(
			url: "https://github.com/apple/swift-argument-parser.git",
			.upToNextMajor(from: "1.8.2")
		),
		.package(
			url: "https://github.com/vapor/console-kit.git",
			.upToNextMajor(from: "4.16.0")
		),
		.package(
			url: "https://github.com/pointfreeco/swift-dependencies.git",
			.upToNextMajor(from: "1.0.0")
		),
		.package(
			url: "https://github.com/pointfreeco/swift-parsing.git",
			.upToNextMinor(from: "0.15.0")
		),
		.package(
			url: "https://github.com/weichsel/zipfoundation.git",
			.upToNextMinor(from: "0.9.20")
		),
		.package(
			url: "https://github.com/onmyway133/Promptberry.git",
			.upToNextMajor(from: "1.0.0")
		),
	],
	targets: [
		.executableTarget(
			name: "skillrack",
			dependencies: [
				.target(
					name: "SkillsManager",
					condition: nil
				),
				.target(
					name: "SkillsRegistryManager",
					condition: nil
				),
				.target(
					name: "FileSystem",
					condition: nil
				),
				.product(
					name: "ArgumentParser",
					package: "swift-argument-parser"
				),
				.product(
					name: "ConsoleKitTerminal",
					package: "console-kit"
				),
				.product(
					name: "Dependencies",
					package: "swift-dependencies"
				),
				.product(
					name: "Promptberry",
					package: "Promptberry"
				),
			],
			path: "Sources/skillrack-cli"
		),
		.target(
			name: "SkillsManager",
			dependencies: [
				.target(
					name: "FileSystem",
					condition: nil
				),
				.product(
					name: "Dependencies",
					package: "swift-dependencies"
				),
				.product(
					name: "DependenciesMacros",
					package: "swift-dependencies"
				),
				.product(
					name: "Parsing",
					package: "swift-parsing"
				),
			],
			path: "Sources/skills-manager"
		),
		.target(
			name: "FileSystem",
			dependencies: [
				.product(
					name: "Dependencies",
					package: "swift-dependencies"
				),
				.product(
					name: "ZIPFoundation",
					package: "ZIPFoundation"
				),
			],
			path: "Sources/swift-file-system"
		),
		.target(
			name: "SkillsRegistryManager",
			dependencies: [
				.target(
					name: "SkillsManager",
					condition: nil
				),
				.product(
					name: "Dependencies",
					package: "swift-dependencies"
				),
			],
			path: "Sources/skills-registry-manager"
		),
		.testTarget(
			name: "SkillsManagerTests",
			dependencies: [
				.target(
					name: "SkillsManager",
					condition: nil
				),
				.target(
					name: "FileSystem",
					condition: nil
				),
				.product(
					name: "Dependencies",
					package: "swift-dependencies"
				),
			],
			path: "Tests/skills-manager-tests"
		),
		.testTarget(
			name: "skillrack-tests",
			dependencies: [
				.target(
					name: "skillrack",
					condition: nil
				),
				.target(
					name: "SkillsManager",
					condition: nil
				),
				.target(
					name: "SkillsRegistryManager",
					condition: nil
				),
			],
			path: "Tests/skillrack-cli-tests"
		),
		.testTarget(
			name: "SkillsRegistryManagerTests",
			dependencies: [
				.target(
					name: "FileSystem",
					condition: nil
				),
				.target(
					name: "SkillsManager",
					condition: nil
				),
				.target(
					name: "SkillsRegistryManager",
					condition: nil
				),
				.product(
					name: "Dependencies",
					package: "swift-dependencies"
				),
			],
			path: "Tests/skills-registry-manager-tests"
		),
	],
	swiftLanguageModes: [.v6]
)
