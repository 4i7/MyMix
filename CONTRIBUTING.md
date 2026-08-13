# Contributing to MyMix

MyMix is an independent derivative of EarTrumpet. Issues and pull requests in this repository should concern MyMix itself; they are not submissions to the EarTrumpet project.

## Before changing code

- Read `LICENSE` and preserve upstream copyright/license notices in inherited or substantially derived code.
- Keep MyMix clearly identified as an unofficial derivative. Do not present the project as an official EarTrumpet release.
- Preserve the privacy posture: no automatic telemetry, crash reporting, feedback upload, or hidden network reporting.
- Avoid adding dependencies unless they provide clear value and have been reviewed for licensing, maintenance, security, runtime size, and startup cost.
- Do not reintroduce removed add-on/extensibility or Store/MSIX infrastructure into the standalone core without a specific reviewed requirement.

## Development workflow

Create a branch from `main`, make the smallest coherent change, and run the MyMix transformation/validation path before opening a pull request. For changes to upstream-conversion logic, test a clean regeneration from the recorded EarTrumpet revision rather than only editing the generated source.

A distributable change should pass `tools\Test-MyMixRefactor.ps1`, Release/x86 compilation with warnings treated as errors, and the application startup smoke test on Windows. Changes to audio routing, hotkeys, tray behavior, DPI/theme behavior, device add/remove, or application-session movement should also receive relevant interactive testing.

## Generated source and transformation scripts

Much of the maintained behavior is expressed in `tools\Convert-ToMyMix.ps1`, `tools\Finalize-StandaloneMyMix.ps1`, and the staged optimizer under `tools\Optimize-MyMix`. When a generated-source fix is intended to survive future EarTrumpet imports, update the transformation stage as well as validating the resulting source.

Transformations should be fail-fast and assert their intended invariants. A changed upstream pattern should produce an obvious validation failure rather than a silently incomplete conversion.

## Upstream fixes

If a change fixes an issue that also exists in unmodified EarTrumpet and does not depend on MyMix-specific behavior, consider contributing an appropriate version of the fix to the upstream EarTrumpet project under its contribution process. Do not imply that MyMix maintainers speak for or represent the upstream project.

## Security and diagnostics

Do not place secrets, private keys, access tokens, private diagnostic dumps, machine-specific paths, or personal data in commits or public issues. Follow `SECURITY.md` for security-sensitive reports. Local diagnostic exports can contain application/device identifiers and paths; review and redact them before sharing.
