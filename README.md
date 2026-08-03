# SkillRack

[![CI](https://github.com/capturecontext/skillrack/actions/workflows/ci.yml/badge.svg)](https://github.com/capturecontext/skillrack/actions/workflows/ci.yml) [![Swift 6.1](https://img.shields.io/badge/Swift-6.1-ED523F.svg?style=flat)](https://swift.org/download/) ![Platforms](https://img.shields.io/badge/platforms-macOS_15_or_later-ED523F.svg?style=flat) [![@capture_context](https://img.shields.io/badge/contact-@capture__context-1DA1F2.svg?style=flat&logo=twitter)](https://twitter.com/capture_context)

**One managed registry for the agent skills you use everywhere.**

`skillrack` installs local or Git-hosted agent skills into a central registry
and links those managed copies to supported coding tools or custom directories.
Each record keeps its source provenance, dependencies, content digest, and
managed links so the registry remains inspectable and verifiable.

- Install one skill or a complete collection from disk or Git.
- Resolve nested skills and install shared dependencies once.
- Link the same managed skill into several tools without copying it.
- Inspect source metadata, dependencies, digests, and link destinations.
- Verify registry content and managed links for drift or damage.
- Automate every command through versioned JSON output.

## Table of contents

- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Installation](#installation)
  - [Brew](#brew)
  - [Download a release](#download-a-release)
  - [Build from source](#build-from-source)
- [Quick start](#quick-start)
- [Installing skills](#installing-skills)
- [Linking skills](#linking-skills)
- [Managing the registry](#managing-the-registry)
- [Supported tools](#supported-tools)
- [Machine-readable output](#machine-readable-output)
- [Uninstalling](#uninstalling)
- [Data and safety](#data-and-safety)
- [Development](#development)
- [Publishing a release](#publishing-a-release)
- [License](#license)

## How it works

SkillRack keeps canonical skill contents under its application-support
directory. Installation detects every `SKILL.md`, resolves nested skills and
simple textual dependencies, copies their contents into the registry, and
records a digest of each installed result. A skill mentions another detected
skill when its description or Markdown files contain either `/<skill-name>` or
`<skill-name> skill`; Markdown backticks around the name are ignored.

Linking creates symbolic links from a supported tool's skills directory, or a
custom directory, to those registry copies. Link metadata belongs to the
registry, so `unlink` only removes links that SkillRack owns. An installed skill
cannot be removed while it still has managed links or is required by another
installed skill.

Reinstalling the same canonical source is idempotent by default. Pass `--force`
to refresh matching records in place while preserving their registry IDs and
managed links. Use `skillrack show` to inspect an individual record and
`skillrack verify` to check content digests, dependencies, and links together.

## Requirements

- macOS 15 or later
- Swift 6.1 or later only when building from source
- Git when installing from a remote repository

## Installation

### Brew

```sh
brew install capturecontext/tap/skillrack
```

### Download a release

Download these files from the
[latest GitHub release](https://github.com/capturecontext/skillrack/releases/latest):

- `skillrack-universal-apple-darwin`
- `skillrack-universal-apple-darwin.sha256`

The universal executable runs natively on both Apple Silicon and Intel Macs.
Smaller architecture-specific `aarch64` and `x86_64` artifacts are available
from the same release.

Verify and install the universal executable:

```sh
cd ~/Downloads
shasum -a 256 --check skillrack-universal-apple-darwin.sha256
install -d "$HOME/.local/bin"
install -m 755 skillrack-universal-apple-darwin "$HOME/.local/bin/skillrack"
"$HOME/.local/bin/skillrack" version
```

If `skillrack` is not found, add this line to `~/.zshrc` and start a new shell:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

Release executables are signed with a Developer ID Application certificate,
use the hardened runtime and a secure timestamp, and are notarized by Apple.

### Build from source

Clone the repository with a Swift 6.1 toolchain available, then run:

```sh
make test
make install
```

`make install` builds a release executable and installs it to
`~/.local/bin/skillrack`. Set `PREFIX` to choose a different installation
prefix.

## Quick start

Install a local skill and link it into Codex and Claude:

```sh
skillrack install ./my-skill
skillrack link my-skill --tool codex --tool claude
```

Install every root skill detected in a collection:

```sh
skillrack install ./skill-collection --all
```

Inspect and verify the result:

```sh
skillrack list
skillrack show my-skill
skillrack path my-skill
skillrack verify
```

Use a lowercase registry UUID instead of a name whenever an exact skill name is
not unique.

## Installing skills

The source can be a local path, a file URL, or a cloneable Git URL:

```sh
skillrack install ./my-skill
skillrack install file:///Users/me/Developer/skills --all
skillrack install https://github.com/example/skills.git --all
```

Remote sources use a temporary checkout by default and remove it after a
successful installation. Preserve the checkout at a chosen location when you
want to reuse it:

```sh
skillrack install https://github.com/example/skills.git \
  --clone-to ~/Developer/example-skills \
  --if-present pull \
  --all
```

`--if-present` accepts `error`, `clean`, `pull`, or `skip`. Cleaning an existing
checkout is destructive and requires confirmation. Pass `--yes` for explicit
non-interactive approval.

Choose particular root skills by name or exact relative path:

```sh
skillrack install ./skill-collection --skill swift-style --skill tools/git
```

Refresh every installed skill that still matches a local collection:

```sh
skillrack install ./skill-collection --all --force
```

The update replaces registry contents, descriptions, dependency records,
digests, and source revisions in place. Registry IDs, creation dates, display
names, and managed links are preserved. Newly detected dependencies or root
skills are installed normally. Skills removed from the source, or moved to a
different relative path, are not deleted automatically.

For a preserved remote checkout, pull and refresh the collection together:

```sh
skillrack install https://github.com/example/skills.git \
  --clone-to ~/Developer/example-skills \
  --if-present pull \
  --all \
  --force
```

Omit the source or selection flags in an interactive terminal to use guided
selection.

## Linking skills

Link one or more installed skills to supported tools:

```sh
skillrack link swift-style git-workflows --tool codex --tool claude
```

When a selected skill mentions installed skill dependencies that were not
selected explicitly, interactive use confirms each dependency before creating
any links. Pass `--with-dependencies` to link all transitive mentioned-skill
dependencies automatically. Machine-readable mode requires either explicit
dependency selectors or this flag.

```sh
skillrack link wayfinder --tool codex --tool claude --with-dependencies
```

Custom directories are supported alongside built-in tools:

```sh
skillrack link swift-style --directory ~/.custom-agent/skills
```

Use `--alias` to choose the link name when exactly one skill is selected:

```sh
skillrack link swift-style --tool codex --alias swift
```

Remove selected managed links, or every link for a skill:

```sh
skillrack unlink swift-style --tool codex --yes
skillrack unlink swift-style --all --yes
```

SkillRack refuses to replace unrelated files or symbolic links at a requested
destination.

## Managing the registry

| Task | Command |
| --- | --- |
| List installed skills | `skillrack list` |
| Show one record | `skillrack show <skill>` |
| Print an installed skill directory | `skillrack path <skill>` |
| Install from a source | `skillrack install <source>` |
| Add managed links | `skillrack link <skills ...>` |
| Remove managed links | `skillrack unlink <skills ...>` |
| Verify the registry | `skillrack verify` |
| Remove installed skills | `skillrack uninstall <skills ...>` |
| Show the executable version | `skillrack version` |

Plain-text `list` output contains six tab-separated fields by default: name,
description, full registry ID, source, dependency count, and managed-link
count. Use `--no-print-all` with one or more projection flags when only certain
fields are needed:

```sh
skillrack list --no-print-all --print-name
skillrack list --no-print-all --print-desc
skillrack list --no-print-all --print-name --print-desc
skillrack list --no-print-all --print-source --print-links
```

Available projections are `--print-name`, `--print-desc`, `--print-id`,
`--print-source`, `--print-deps`, and `--print-links`. `--print-all` is enabled
by default. These flags affect plain-text output; `--json` continues to return
complete structured records.

`uninstall` is intentionally sequential. A skill must have no managed links
and no installed dependents before its registry record can be removed.

## Supported tools

| `skillrack link --tool` | Link directory |
| --- | --- |
| `agents` (generic) | `~/.agents/skills` |
| [`amp`](https://ampcode.com/manual#agent-skills) | `~/.agents/skills` |
| [`antigravity`](https://antigravity.google/docs/skills) | `~/.gemini/antigravity/skills` |
| [`claude`](https://code.claude.com/docs/en/skills) | `~/.claude/skills` |
| [`codex`](https://developers.openai.com/codex/skills/) | `~/.codex/skills` |
| [`copilot`](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills) | `~/.copilot/skills` |
| [`cursor`](https://cursor.com/docs/context/skills) | `~/.cursor/skills` |
| [`droid`](https://docs.factory.ai/cli/configuration/skills) | `~/.factory/skills` |
| [`gemini`](https://geminicli.com/docs/cli/skills/) | `~/.gemini/skills` |
| [`kimi`](https://moonshotai.github.io/kimi-cli/en/customization/skills) | `~/.kimi/skills` |
| [`kiro`](https://kiro.dev/docs/cli/custom-agents/configuration-reference/#skill-resources) | `~/.kiro/skills` |
| [`opencode`](https://opencode.ai/docs/skills/) | `~/.config/opencode/skills` |
| [`pi`](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#skills) | `~/.pi/agent/skills` |
| [`xcode:claude`](https://developer.apple.com/documentation/Xcode/setting-up-coding-intelligence#Customize-the-Codex-and-Claude-Agent-environments) | `~/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig/skills` |
| [`xcode:codex`](https://developer.apple.com/documentation/Xcode/setting-up-coding-intelligence#Customize-the-Codex-and-Claude-Agent-environments) | `~/Library/Developer/Xcode/CodingAssistant/codex/skills` |
| `xcode:gemini` | `~/Library/Developer/Xcode/CodingAssistant/gemini/.gemini/skills` |

## Machine-readable output

Every command supports `--json` and `--no-json`. Set `SKILLRACK_JSON=1` to make
JSON the default; an explicit command-line flag takes precedence.

```sh
skillrack --json list
SKILLRACK_JSON=1 skillrack show swift-style
skillrack verify --json
```

Successful responses are written to stdout and errors to stderr using a
versioned envelope:

```json
{
  "api_version": 1,
  "data": {},
  "ok": true
}
```

JSON mode never prompts. Destructive operations require explicit selectors and
`--yes`, and a remote install using `--if-present clean` requires `--yes` when
it would replace an existing checkout.

## Uninstalling

Remove managed links before uninstalling their registry records:

```sh
skillrack unlink my-skill --all --yes
skillrack uninstall my-skill --yes
```

If installed with Make, remove the executable with the same prefix:

```sh
make uninstall
```

For a Homebrew installation, use:

```sh
brew uninstall skillrack
```

None of these commands deletes the complete registry support directory.

## Data and safety

SkillRack stores managed contents and metadata in:

```text
~/Library/Application Support/skillrack/
├── storage.lock
└── skills/
    └── <registry-uuid>/
        ├── skill.json
        └── content/
```

Temporary `.staging` and `.trash` directories may also appear while registry
operations are in progress. `skill.json` contains source provenance,
dependencies, the content digest, timestamps, and managed links.

Set `SKILLRACK_ROOT` to an absolute path to relocate the registry. Set
`SKILLRACK_HOME` to an absolute path to change the home directory used when
resolving built-in tool destinations. These environment variables are useful
for isolated automation and tests; avoid pointing them at unrelated data.

Skill contents can execute instructions through the agent that consumes them.
Review sources before installing, especially from repositories you do not
control.

## Development

Common development commands are:

```sh
make build
make test
make release
make universal
```

`make release` creates an architecture-specific executable and checksum under
`dist/`. `make universal` cross-builds Apple Silicon and Intel slices, combines
them with `lipo`, and writes a universal executable plus checksum.

The package targets macOS 15 and uses Swift 6 language mode. Run
`skillrack help <command>` or `skillrack <command> --help` for the complete CLI
reference.

## Publishing a release

Release versions use plain semantic versions such as `0.1.0` without a `v`
prefix. Update the embedded version in
`Sources/skillrack-cli/AppCommand.swift`, run `make test`, and push the
release-ready commit to `main`. Then run the `Release` workflow from GitHub
Actions and enter that version.

The workflow pins the release to the selected `main` commit, verifies the
embedded version, resolves one dependency graph for both architectures, and
builds and tests on Apple Silicon and Intel runners. It signs and notarizes the
final executables, verifies their SHA-256 checksums, publishes the GitHub
release, and dispatches the matching Homebrew formula update.

Published artifacts are:

- `skillrack-aarch64-apple-darwin`
- `skillrack-x86_64-apple-darwin`
- `skillrack-universal-apple-darwin`

Each executable has an adjacent `.sha256` file. The release also includes the
exact `Package.resolved` used by both builds; it remains ignored during normal
development.

## License

SkillRack is available under the [MIT License](LICENSE).
