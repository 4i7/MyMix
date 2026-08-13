# MyMix Privacy

MyMix is designed to operate locally. The current MyMix build does **not** initialize Bugsnag or another crash-reporting/analytics SDK and does not automatically submit telemetry, crash reports, diagnostics, or feedback to the MyMix or EarTrumpet maintainers.

## Normal operation

Normal mixer operation uses Windows APIs on the local machine to enumerate playback devices and audio sessions, read/update volume and mute state, display application/device information, and manage user-selected playback routing. MyMix does not require a MyMix account or a hosted MyMix service.

Settings for the standalone build are stored for the current Windows user under `Software\MyMix` in the registry.

## Local diagnostics

The About/diagnostics command is user-initiated. It creates a text file in the local temporary directory and opens that file locally. MyMix does not automatically upload the file.

A diagnostic file can contain information that should be treated as potentially sensitive, including application/session display names, application identifiers, process IDs, icon/application paths, audio-device identifiers and names, volume/mute state, persisted endpoint identifiers, Windows/build information, language/region, DPI/theme settings, runtime duration, and process/resource counts.

Review and redact a diagnostic file before attaching it to a public issue or sending it to another person. Deleting the generated file removes MyMix's local diagnostic copy.

## Network access

The mixer itself has no telemetry or update service. User actions that explicitly open a web link, such as the repository link in About or links to Windows settings/help destinations, may launch the user's browser or Windows settings application. Those destinations are outside MyMix and are governed by their own policies.

The repository's maintenance/build scripts can access GitHub, NuGet, and the EarTrumpet upstream repository when a developer explicitly runs those workflows. Those developer workflows are separate from normal end-user application operation.

## Changes

If a future version introduces any automatic data transmission, the privacy documentation and release notes should be updated before that version is distributed. The public-hardening validation intentionally checks that the removed telemetry/crash-reporting paths do not silently return during an upstream refresh.
