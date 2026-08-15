# Changelog

All notable public changes to FS User Stories are documented here.

## 0.1.0 Alpha 8 — 2026-08-14

### Changed

- Refined the native macOS toolbar so synchronization, project options, profile
  creation, and story creation are grouped by intent without a detached status
  control.
- The synchronization action now communicates working, successful, and failed
  states directly through the same toolbar control and its contextual help.
- The direct-download build is explicitly identified as a separate distribution
  channel while sharing the same Swift interface and Rust core as the Store build.

### Fixed

- Adding an acceptance criterion now scrolls the editor into view and places
  keyboard focus in the new multiline field.
- Quitting the application stops its embedded MCP core, and direct builds can
  safely recover the fixed local MCP endpoint from an older owned process.
- The bundled Rust core is built and validated as Apple Silicon arm64 to match
  the published macOS compatibility policy.

### Verified

- Rust and Swift tests cover MCP endpoint ownership, lifecycle behavior, GitHub
  sharing contracts, and distribution-channel metadata.

## 0.1.0 Alpha 7 — 2026-08-14

### Fixed

- Restored GitHub Device Flow authorization after the Rust-core migration by
  aligning the `verificationUrl`, `cloneUrl`, and `webUrl` protocol keys with
  their native Swift URL properties.
- Restored all affected sharing entry points: Create on GitHub, join by
  invitation, and open an existing private GitHub repository.
- Repository fields now accept common provider SSH shorthand such as
  `github.com:owner/repository.git` and normalize it to the canonical
  `git@github.com:owner/repository.git` form.

### Verified

- The real shared-project repository clones and loads through the Rust stored
  join command.
- Contract tests cover GitHub authorization, repository creation responses, and
  joined-project decoding across the Rust/Swift boundary.

## 0.1.0 Alpha 6 — 2026-08-14

### Changed

- Completed the portable-core migration: Rust now owns the authoritative
  business rules, SQLite persistence, Markdown transfer, managed attachments,
  Git/GitHub integration, synchronization policy, and MCP server/tools.
- Reduced Swift to the native macOS interface and platform adapters for
  SwiftUI/AppKit, Keychain, security-scoped file access, process lifecycle, and
  background timers.
- Project and story deletion now run as atomic stored-core operations, including
  cleanup of their managed attachment and repository directories.
- GitHub Device Flow, private-repository creation, collaborator invitations,
  provider URL recognition, and API error handling now execute in Rust.

### Fixed

- Prevented the stories column from being resized below a usable native macOS
  width.
- Added appearance-specific transparent menu-bar artwork for reliable contrast
  in both Light and Dark Mode.
- Removed the legacy Swift MCP and Git archive implementations so there is no
  alternate backend path or second project data representation.

### Verified

- 21 Rust tests and 7 Swift integration/UI-adapter tests pass.
- Rust formatting and Clippy with warnings denied pass.
- The bundled release core is rebuilt from the same reviewed source.

## 0.1.0 Alpha 5 — 2026-08-13

### Added

- Import and export stories as one readable Markdown document, with filters for
  all, Active, Completed, Draft, or a manual selection. Attachments remain local
  and are intentionally excluded from this alpha transfer format.
- First-run choices to create a project, use an invitation, or connect an
  existing shared repository.
- A visible per-project synchronization state in the macOS toolbar.
- Story ordering by newest first, oldest first, or title.

### Changed

- Git synchronization now runs through a resource-conscious background
  scheduler. Active projects refresh more frequently, inactive projects use a
  wider interval, local changes use bounded debounce, and retries back off after
  failures.
- Local SQLite writes remain immediate and independent from remote Git work.
- Concurrent stories use immutable UUID identity. If two Macs independently
  create the same human reference, both stories survive and duplicate display
  numbers are reassigned deterministically during merge.
- Story actions now follow native macOS menu placement: creation and transfer
  under File, editing and destructive actions under Edit.
- Dark Mode surfaces, toolbar materials, search, and list selection use semantic
  macOS colors instead of fixed bright fills.

### Verified

- Rust merge-core tests cover concurrent UUID identity and display-number
  disambiguation.
- Swift tests cover MCP behavior, synchronization scheduling, and Markdown
  transfer.

## 0.1.0 Alpha 4 — 2026-08-13

- Corrected packaged resource discovery so the bundled Rust core launches from
  the signed application.
- Published the first two-Mac team-testing build with Git sharing, local MCP,
  managed attachments, and SQLite persistence.
