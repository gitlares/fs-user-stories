# Third-party notices

FS User Stories is distributed under the MIT License. Its bundled Rust core
uses the following redistributable open-source components:

- `git2-rs`: MIT OR Apache-2.0.
- `libgit2` 1.9.6: GPL-2.0-only WITH GCC-exception-2.0. The linking exception
  explicitly permits linking libgit2 with an independent module and
  distributing the resulting executable under terms of our choice.
- OpenSSL: Apache-2.0.
- SQLite: public domain.

The complete transitive Rust dependency versions are pinned in
`Core/Cargo.lock`. Release packaging must retain the corresponding license
texts and this notice.
# QtKeychain

FS User Stories uses QtKeychain 0.15.0 to store GitHub access tokens in the
operating system's secure credential service. QtKeychain is distributed under
the Modified BSD License. Source: https://github.com/frankosterfeld/qtkeychain

# Interface fonts

- Inter is bundled as the cross-platform interface font under the SIL Open
  Font License 1.1. Its complete license is in `Support/Licenses/Inter-OFL.txt`.
- Material Symbols is bundled for interface icons under the Apache License 2.0.

The Qt application does not bundle Apple SF Pro or SF Symbols.
