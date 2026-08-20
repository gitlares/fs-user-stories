# Snap Store listing — FS User Stories 1.0.3

This is the copy and screenshot checklist for the Snap Store listing. The
images below are real application captures, not mock-ups or generated artwork.

## Short description

Plan, share and sync user stories with Git.

## Description

FS User Stories is a focused desktop workspace for product teams. Create user
stories, acceptance criteria, profiles and attachments in one local project,
then share the project through Git without a hosted database or account.

The Linux app uses the same Rust core as the macOS app and a Qt/QML interface
that stays useful offline. Git synchronization is explicit and conflict-aware:
the app reports a remote change instead of silently overwriting work.

This snap is the x86_64 Linux build of FS User Stories 1.0.3. It is free to
use. If FS User Stories saves your team time, you can help cover development
and infrastructure costs with a voluntary donation:

https://www.paypal.com/donate/?hosted_button_id=7RDCBR3QXXEMJ

## Store metadata

- Website: https://github.com/gitlares/fs-user-stories
- Source: https://github.com/gitlares/fs-user-stories
- Issues: https://github.com/gitlares/fs-user-stories/issues
- Contact: https://github.com/gitlares/fs-user-stories
- License: MIT
- Donation: https://www.paypal.com/donate/?hosted_button_id=7RDCBR3QXXEMJ

## Screenshots

Use the following real captures in this order. They are already in the
repository and are suitable for the store gallery:

1. `docs/screenshots/linux-01-welcome.png` — welcome screen (1400×900)
2. `docs/screenshots/linux-02-workspace.png` — project workspace (1400×900)
3. `Support/AppStore/Screenshots/en-US/01-story-detail-1440x900.jpg` — story
   detail and acceptance criteria (1440×900)
4. `Support/AppStore/Screenshots/en-US/02-profiles-1440x900.jpg` — profiles
   view (1440×900)
5. `Support/AppStore/Screenshots/en-US/03-share-sync-1440x900.jpg` — sharing
   and synchronization (1440×900)

Before uploading, review each capture at its full resolution and remove any
personal project names or invitation codes. The Snap Store screenshot upload
is a separate store-account action; keeping this manifest and this checklist
in the repository makes the listing reproducible without putting screenshots
inside the snap payload.
