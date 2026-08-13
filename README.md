# FS User Stories

<p align="center">
  <img src="Design/AppIcon-master.png" alt="FS User Stories icon" width="128">
</p>

<h3 align="center">Fucking Simple User Stories</h3>

<p align="center">
  Your stories, on your computer. Share with Git. Nothing else.
</p>

<p align="center">
  <a href="https://gitlares.github.io/fs-user-stories/">Website</a> ·
  <a href="https://github.com/gitlares/fs-user-stories/releases">Download</a> ·
  <a href="https://github.com/gitlares/fs-user-stories/issues">Issues</a> ·
  <a href="./LICENSE">MIT License</a>
</p>

FS User Stories is a native, local-first macOS application for writing clear
requirements without turning them into a project-management system. It keeps the
product deliberately small: projects, profiles, stories, acceptance criteria,
one notes field, and attachments.

There are no FS User Stories accounts, no telemetry, no required cloud, no
subscriptions, no sprints, no estimates, no assignees, no deadlines, and no
dashboards. The app works offline, exposes a local MCP server for compatible
agents, and uses Git only when the user chooses to share a project.

> FS User Stories does not manage your team, your dates, or your company. It only
> makes clear what needs to be built.

## Alpha 1

The first team-testing alpha is already a functional product, not a static UI
prototype. It includes a signed and notarized Apple Silicon application with the
following capabilities.

### Native macOS experience

- SwiftUI interface designed around current macOS patterns and system materials.
- English and Spanish localization, selected from the user's system language.
- Large-window startup, standard keyboard commands, list navigation, contextual
  actions, and menu-bar access.
- A menu-bar companion that keeps projects and active stories accessible when the
  main window is closed, with a separate command to quit completely.
- Native confirmation dialogs for destructive operations.
- Search, collapsible Draft, Active, and Completed sections, status filtering,
  and profile filtering.

### Projects, profiles, and stories

- Create and manage multiple local projects.
- Create, edit, search, and delete project profiles.
- Create, edit, duplicate, search, filter, and delete user stories.
- The focused user-story format: **As a**, **I want**, and **So that**.
- Exactly three states: **Draft**, **Active**, and **Completed**.
- Completed stories are read-only until they are reopened as Active or Draft.
- Checkable acceptance criteria with add, edit, and remove actions.
- Visual completion progress as completed criteria over total criteria.
- A direct **Mark as Completed** action once every criterion is satisfied.
- One intentionally simple notes field per story—no comment threads or activity
  feed.

### Managed attachments

- Add files with the file picker or drag and drop.
- Preview supported files with native macOS Quick Look.
- Files are copied into managed application storage, so moving the original does
  not break the story.
- Up to 10 attachments per story, 10 MB per file, and 50 MB total per story.
- Attachment metadata and SHA-256 hashes travel with the portable project data.

### Local persistence

- Projects, profiles, stories, criteria, notes, and attachment metadata persist
  in a local SQLite database.
- Attachment contents remain in the app's managed Application Support directory.
- The application works fully without an Internet connection.
- UI and MCP operations use the same application layer and persistence rules, so
  data is not duplicated across separate implementations.
- Changes made through MCP notify the application and refresh the visible state.

### Local MCP for any compatible agent

The app runs a loopback-only MCP server while it is open. The MCP screen shows
the live status, URL, port, and connection instructions; the same status is also
visible in the app footer and menu bar.

Alpha 1 exposes 27 tools covering the product's real operations:

- Describe the application and list or inspect projects.
- Create projects and inspect repository status.
- List, create, edit, and delete profiles.
- Search and filter stories; read complete story details.
- Create, edit, duplicate, delete, and change the status of stories.
- Add, update, complete, and remove acceptance criteria.
- Update the single notes field.
- List, add, resolve, and delete managed attachments.
- Connect and synchronize shared repositories and create invitations.

Destructive MCP calls require explicit confirmation. Completed stories remain
read-only through MCP just as they do in the UI. The server also includes a
prompt that helps an agent inspect an existing codebase and propose profiles and
user stories for the selected project.

The server binds only to the local loopback interface. FS User Stories operates
no proxy, account service, or remote MCP infrastructure, and receives none of the
user's project data.

### Optional Git synchronization

Every project receives a private managed repository inside the app's Application
Support directory. Users interact with simple product actions—connect, create,
share, join, and synchronize—rather than with commits or branches.

- A remote is optional and may be hosted by GitHub, GitLab, or another compatible
  Git host.
- The app can connect an existing remote or create a private GitHub repository
  after browser-based Device Flow authorization.
- The GitHub OAuth token is stored in macOS Keychain when available. Development
  runs without Keychain entitlement keep it only in memory for that session. It
  is never written to SQLite, project JSON, invitations, logs, or Git.
- Repository owners can invite a GitHub collaborator by username from the app.
  A new Mac authorizes its own GitHub account automatically while joining a
  private GitHub project.
- SSH remotes use the user's existing local SSH agent. Public HTTPS remotes work
  without credentials.
- Share invitations contain the project identity and remote URL, never account
  credentials.
- Changes to separate stories or profiles merge automatically. Concurrent changes
  to the same item ask the user to choose **Keep Mine** or **Use Shared**.
- The app never places the SQLite database in Git.

FS User Stories reserves the isolated `fs-user-stories` branch in every remote.
It never fetches, checks out, merges, pushes, force-pushes, or deletes `main`,
`master`, or another code branch. This keeps an existing source repository safe,
although a dedicated repository remains the clearest choice for a team.

## Install

Alpha 1 currently requires an Apple Silicon Mac running macOS 26 or later.

1. Download the DMG from [GitHub Releases](https://github.com/gitlares/fs-user-stories/releases).
2. Open the DMG and drag **FS User Stories** to **Applications**.
3. Open the application normally.

The published DMG and application are Developer ID signed, notarized by Apple,
and stapled for Gatekeeper. End users do not need Xcode, Rust, CMake, Git,
Homebrew, or libgit2 installed.

This is an alpha intended for team testing. Back up important project data and
[report unexpected behavior](https://github.com/gitlares/fs-user-stories/issues).

### Test with two Macs

1. On the first Mac, open **Share & Sync** and choose **Create on GitHub**.
2. Enter the second person's GitHub username under **Invite a GitHub collaborator**.
3. The collaborator accepts GitHub's repository invitation.
4. On the first Mac, choose **Copy Invitation** or **Share Invitation…**.
5. On the second Mac, choose **Join Shared Project** and paste the invitation.
6. Authorize GitHub when the app opens Device Flow. No token is included in the
   invitation.
7. Make a change on either Mac and choose **Synchronize Now** on both Macs.

## Portable project format

SQLite is the local source of truth. Git synchronization exports an open,
reviewable archive instead of copying the database:

```text
.fs-user-stories/
├── project.json
├── README.md
├── profiles/
│   └── <profile-id>.json
├── stories/
│   └── <story-id>.json
└── attachments/
    └── <story-id>/<managed-files>
```

The project header and one JSON file per profile and story form the synchronized
source of truth. This keeps diffs focused, conflicts small, and the data directly
readable by language models. A generated README summarizes the project for people.
Attachments are copied, size-limited, and verified by hash.

## Architecture

The codebase separates the native product from portable infrastructure:

- `Sources/FSUserStoriesApp/App`: application entry point and macOS lifecycle.
- `Sources/FSUserStoriesApp/Application`: shared application operations and
  business rules used by both the UI and MCP.
- `Sources/FSUserStoriesApp/Domain`: projects, profiles, stories, criteria, and
  attachment models.
- `Sources/FSUserStoriesApp/Infrastructure`: SQLite and managed attachment
  storage.
- `Sources/FSUserStoriesApp/UI`: SwiftUI views, components, localization, and
  native macOS presentation.
- `Sources/FSUserStoriesApp/MCP`: loopback HTTP transport and MCP adapter.
- `Sources/FSUserStoriesApp/Infrastructure/Git`: portable archive generation,
  Swift-side synchronization orchestration, GitHub Device Flow, and Keychain
  integration.
- `Core`: Rust archive, invitation, three-way merge, conflict handling, and
  libgit2 transport.

The Rust core is compiled from the source under `Core` and bundled into the app
as a self-contained executable. It is the portable basis for future platforms
while the current user interface remains fully native to macOS.

## Build from source

The alpha currently supports only Apple Silicon Macs (M1 or newer) running
macOS 26 or later. Building locally does not require an Apple Developer account,
signing certificate, GitHub token, or FS User Stories account.

### Requirements

- Xcode 26 or newer.
- Rust 1.97 or newer.
- CMake, used only to compile the vendored libgit2 dependency.
- Git, for cloning the source and optional project synchronization.

Install Xcode from the Mac App Store, open it once to finish installing its
components, and make it the active developer directory if necessary:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

Install Rust with the official [rustup](https://rustup.rs/) installer. Install
CMake with [Homebrew](https://brew.sh/) or another trusted package manager:

```sh
brew install cmake
rustc --version
cargo --version
cmake --version
```

### One-command local build

Clone the repository and run the local build helper:

```sh
git clone https://github.com/gitlares/fs-user-stories.git
cd fs-user-stories
./Scripts/build-and-run-local.sh
```

The script validates the Mac and toolchain, compiles the Rust core from `Core`,
creates an unsigned local application and DMG under `Distribution`, and opens the
app. Use `--no-open` to build without launching or `--test` to run both suites:

```sh
./Scripts/build-and-run-local.sh --no-open
./Scripts/build-and-run-local.sh --test
```

The first build takes longer because Cargo compiles vendored libgit2 and OpenSSL
from their locked source dependencies. Later builds reuse the local build cache.
The resulting app is intended for use on the Mac that built it; share the official
signed and notarized DMG with testers instead of redistributing this unsigned
build.

No precompiled FS User Stories executable is stored in the repository. The
generated Rust core, Swift build products, application bundle, and DMG are all
ignored by Git. `Core/Cargo.lock` pins the complete Rust dependency graph so the
source used by Cargo can be reviewed and reproduced.

### Build transparency

The application source, Rust core, build scripts, package metadata, OAuth client
identifier, schemas, migrations, and dependency lockfile are public. The GitHub
OAuth client identifier is intentionally included because Device Flow client IDs
identify an application; they are not passwords or access tokens. Every user
authorizes their own GitHub account, and credentials are never committed.

Official downloads add a Developer ID signature and an Apple notarization ticket
to the application built by these scripts. The release owner's private signing
key is the only release input that cannot be public. Anyone can independently
build the unsigned application and inspect an official download with:

```sh
codesign --verify --deep --strict --verbose=2 "/Applications/FS User Stories.app"
spctl --assess --type execute --verbose=4 "/Applications/FS User Stories.app"
```

Release notes publish a SHA-256 checksum for the DMG so testers can verify the
downloaded artifact with `shasum -a 256`.

### Manual build

Build the Rust core and then the macOS application:

```sh
./Scripts/build-core.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
```

Run the test suites:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
cargo test --manifest-path Core/Cargo.toml
```

Create an unsigned local application and DMG:

```sh
./Scripts/package-alpha.sh
```

Local data is stored in:

```text
~/Library/Application Support/FS User Stories/
```

Removing the repository checkout does not remove that local application data.
Do not delete the Application Support directory unless you intentionally want to
remove every locally stored project and managed attachment.

Signing and notarization are release-owner actions performed separately with
`Scripts/sign-and-notarize-alpha.sh`. See
[`docs/releasing-macos-alpha.md`](./docs/releasing-macos-alpha.md) for the release
checklist.

## Product principles

- No telemetry.
- No FS User Stories accounts.
- No FS User Stories servers.
- No subscriptions.
- No required cloud.
- No sprints, estimates, assignees, deadlines, or dashboards.
- No built-in AI provider.
- Local MCP for the tools the user chooses.
- Optional Git for sharing through infrastructure the user controls.
- Open and portable data.
- Dependencies compatible with commercial redistribution.

## Project language

English is the default language for source code, documentation, issues, and pull
requests. The application follows the user's system language and currently ships
in English and Spanish.

## License

FS User Stories is distributed under the [MIT License](./LICENSE). It permits
free and paid distributions, including a future commercial iOS edition. See
[`THIRD_PARTY_NOTICES.md`](./THIRD_PARTY_NOTICES.md) for bundled dependency
licenses.
