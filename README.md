# FS User Stories

**Fucking Simple User Stories**

FS User Stories is a local-first application for creating and organizing user
stories without the complexity of a full project management suite.

It aims to provide a focused experience for documenting requirements, acceptance
criteria, one notes field, and attachments. Data is stored locally and may be
shared through Git, without requiring an FS User Stories account.

## Project status

The macOS alpha is ready for team testing. It includes a native SwiftUI app,
SQLite persistence, managed attachments, a local MCP server, and a bundled Rust
core for Git synchronization.

## What the alpha does

The first alpha release will target macOS and run entirely locally. It will
include:

- A native interface for creating and managing user stories.
- SQLite persistence and managed local attachments.
- A cross-platform Rust core for portable project archives and Git transport.
- A loopback-only MCP server that allows local agents to read and edit stories.
- One managed local repository per project.
- Optional sharing through any compatible Git remote.

FS User Stories has no account system, telemetry, required cloud, subscriptions,
sprints, estimates, assignees, deadlines, or dashboards.

## Install the alpha

Download the latest DMG from the repository's
[Releases](https://github.com/gitlares/fs-user-stories/releases) page, open it,
and drag **FS User Stories** to **Applications**.

The alpha currently targets Apple Silicon Macs. A signed and notarized build is
required for normal Gatekeeper installation outside the Mac App Store.

## Sharing and synchronization

Every project receives a private managed repository inside the app's Application
Support directory. The UI deliberately hides commits and branches: users only
connect, share, join, and synchronize.

- A remote is optional and may be hosted by GitHub, GitLab, or another Git host.
- GitHub repositories can be created as private repositories from the app after
  device authorization. The OAuth token is stored only in macOS Keychain.
- SSH uses the user's existing local SSH agent. Public HTTPS remotes also work.
- Invitations contain the project identity and remote address, never credentials.
- Synchronization performs a three-way comparison per profile and story.
- Changes to different items merge automatically. Changes to the same item ask
  the user to choose **Keep Mine** or **Use Shared**.
- Attachments remain subject to the app limits and are copied into the project
  archive, so moving the original file does not break the story.
- Every remote uses the reserved `fs-user-stories` branch. FS User Stories never
  fetches, checks out, merges, pushes, force-pushes, or deletes `main`, `master`,
  or another code branch. This makes connecting an existing code repository safe,
  although a dedicated repository remains the clearest option.

Creating a hosted remote and granting team access remain provider operations;
FS User Stories does not pretend a QR code or invitation grants repository
permissions.

### GitHub account connection

The official alpha includes the public Client ID for the FS User Stories OAuth
App and never embeds a client secret. When a user chooses **Create on GitHub**,
GitHub opens in the browser, asks the user to authorize their own account, and
the app creates a private repository for that project.

The app requests GitHub's `repo` OAuth scope because GitHub requires it to create
and synchronize private repositories. The device flow opens GitHub in the user's
browser, and the resulting token is stored as a device-only Keychain item. It is
passed to the bundled core only through standard input for GitHub HTTPS requests
and is never persisted in SQLite, project JSON, invitations, logs, or Git.

## Architecture

- `Sources/FSUserStoriesApp`: native macOS UI, application orchestration, SQLite,
  attachment storage, and the local MCP transport.
- `Core`: Rust domain archive, invitation, conflict merge, and libgit2 transport.
- `.fs-user-stories`: portable per-project archive on the isolated
  `fs-user-stories` branch, with one JSON file per profile and story, plus copied
  attachments. SQLite is never added to the repository.

The bundled core is a self-contained executable. End users do not need Rust,
CMake, Git, Homebrew, or libgit2 installed.

## Building

Requirements for contributors:

- Xcode 26 or newer.
- Rust 1.97 or newer.
- CMake, only to compile the vendored libgit2 dependency.

Build the core, then the macOS app:

```sh
./Scripts/build-core.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
```

The repository currently carries the alpha Apple Silicon core binary used by
Swift Package Manager. Release automation must build and verify each supported
architecture before packaging.

Create an unsigned local alpha package with:

```sh
./Scripts/package-alpha.sh
```

This produces `Distribution/FS User Stories.app` and
`Distribution/FS-User-Stories-Alpha.dmg`. Signing and notarization are release
owner actions and are performed separately with
`Scripts/sign-and-notarize-alpha.sh`. See
[`docs/releasing-macos-alpha.md`](./docs/releasing-macos-alpha.md) for the human
release checklist.

## Principles

- Work offline without requiring an account.
- Keep users in control of their data.
- Avoid unnecessary processes and features.
- Use open and portable formats.
- Keep the project open source.
- Use only dependencies that permit commercial redistribution.

## Project language

English is the default language for source code, documentation, issues, and pull
requests. The app currently follows the user's system language in English and
Spanish.

## Documentation

The detailed implementation plan is available as a Spanish draft in
[`FS-User-Stories-Plan-de-Implementacion.md`](./FS-User-Stories-Plan-de-Implementacion.md).

## License

FS User Stories is distributed under the [MIT License](./LICENSE). The license
permits both free and paid distributions, including the official iOS app.
See [`THIRD_PARTY_NOTICES.md`](./THIRD_PARTY_NOTICES.md) for bundled dependency
licenses.
