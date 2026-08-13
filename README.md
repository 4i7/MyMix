# MyMix

MyMix is an independent Windows volume-mixer derivative based on [EarTrumpet](https://github.com/File-New-Project/EarTrumpet). It focuses on a smaller standalone x86 build, a logarithmic-only volume path, and reduced background/runtime work.

MyMix is **not an official EarTrumpet release** and is not maintained, supported, or endorsed by the EarTrumpet project. Internal `EarTrumpet.*` namespaces are intentionally retained where renaming them would add compatibility risk without changing the product identity.

## What MyMix changes

- Removes the numeric volume labels at the right side of device/app rows and returns that space to the sliders.
- Uses logarithmic volume mapping as the only volume mapping path.
- Removes Bugsnag, outbound crash reporting, EarTrumpet feedback submission, and telemetry controls.
- Keeps diagnostics local and user-initiated only.
- Removes EarTrumpet add-on/extensibility hosting from the standalone build.
- Removes the legacy icon-selection feature and does not redistribute EarTrumpet's bundled application/horn icon as MyMix branding.
- Uses Windows audio/system icon resources for tray volume states, with a stock system fallback if those resources are unavailable.
- Keeps the peak meter at a 30 FPS target while reducing work through aggregate peak reads, visible-device scoping, cached snapshots, coalesced UI updates, and lightweight release smoothing.
- Uses explicit view-model cleanup, bounded/frozen icon caching, per-process app-information caching, and coalesced Core Audio callback updates.
- Stores unpackaged settings under the current user's `Software\MyMix` registry key.

## Download

Validated standalone builds are intended to be published under **GitHub Releases** as `MyMix-x86.zip`, together with a SHA-256 checksum file. GitHub Actions build artifacts are intentionally not used for distribution.

Release binaries are currently unsigned unless a separate code-signing process is added. Windows may therefore display an unknown-publisher or SmartScreen warning. Verify the downloaded archive against the checksum published with the same release before running it.

MyMix currently has no automatic updater. Updating is an explicit download/replacement operation.

## Platform and build model

MyMix is a standalone WPF application targeting .NET Framework 4.6.2 and x86, matching the architecture assumptions in the inherited Core Audio/P/Invoke code. It is intended for Windows 10 and Windows 11. The current public distribution path is the standalone executable build, not the original EarTrumpet MSIX/Store package.

See [COMPILING.md](COMPILING.md) for reproducible build information.

## Privacy

Normal MyMix operation does not send telemetry, crash reports, diagnostics, or feedback to the MyMix or EarTrumpet maintainers. Local diagnostic export is available only when explicitly requested by the user and can contain local device/application identifiers and paths, so diagnostic files should be reviewed before sharing.

See [PRIVACY.md](PRIVACY.md) for details.

## Upstream updates

`tools/Update-FromEarTrumpet.ps1` can import an EarTrumpet revision into a clean work tree, reapply the MyMix transformation/optimizer stages, validate invariants, and build it on the self-hosted Windows runner. Upstream updates are kept reviewable rather than being blindly merged into `main`.

The exact EarTrumpet source revision used by the current tree is recorded in `.mymix-converted`. `UPSTREAM_README.md` preserves the imported upstream README for reference.

## License and attribution

MyMix is a derivative of EarTrumpet and retains the upstream [LICENSE](LICENSE) verbatim. **Read that file before using or redistributing MyMix:** the retained upstream terms are MIT-style terms preceded by explicit excluded entities, so this repository should not be described as plain/unmodified MIT licensing.

Upstream EarTrumpet authors and contributors retain their applicable copyright in the inherited code. MyMix-specific modifications do not remove or replace those notices. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for provenance and dependency notes.

## Security and contributions

Please read [SECURITY.md](SECURITY.md) before reporting a security-sensitive issue or sharing diagnostics. General MyMix contributions are described in [CONTRIBUTING.md](CONTRIBUTING.md).
