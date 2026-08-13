# Security Policy

## Supported versions

Security fixes are expected to target the latest MyMix release and the current `main` branch. Older standalone ZIP releases may not receive backports.

## Reporting a vulnerability

Do not post secrets, exploit details that would unnecessarily put users at risk, or unredacted diagnostic dumps in a public issue. If GitHub private vulnerability reporting is available for this repository, use it for security-sensitive reports. Otherwise, open a minimal issue stating that you have a security concern and avoid including sensitive reproduction data until a private channel is available.

Include the affected MyMix version/commit, Windows version, a minimal reproduction description, expected versus observed behavior, and whether the issue requires local user interaction or special privileges. Do not include access tokens, credentials, private file paths, or unrelated machine data.

## Diagnostic files

MyMix diagnostic exports are local-only but can contain application/device identifiers, process IDs, paths, and system configuration. Review and redact them before sharing, even in a security report.

## Release security model

MyMix release builds are validated from source on a Windows self-hosted runner. GitHub Actions artifacts are not used as a distribution channel. Release ZIPs should be accompanied by SHA-256 checksums.

Unless a future release explicitly states otherwise, MyMix binaries are not Authenticode-signed. A checksum detects accidental or malicious modification after the release asset was produced, but it is not a substitute for publisher code signing.

The repository's upstream-refresh workflow is intentionally review-oriented. New EarTrumpet revisions should not be executed automatically on the persistent self-hosted runner merely because upstream changed; a maintainer should choose when to run the refresh and review the resulting change.
