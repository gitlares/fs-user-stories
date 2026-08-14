# Changelog

All notable public changes to FS User Stories are documented here.

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
