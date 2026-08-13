# MyMix

MyMix is a private Windows volume mixer derived from EarTrumpet and optimized around a single logarithmic volume-control path.

## MyMix changes

- Removes the numeric volume labels at the right side of device/app rows and gives that width back to the slider with a 16 px right inset.
- Uses logarithmic volume mapping unconditionally; the linear/logarithmic runtime branch and settings toggle are no longer part of the hot path.
- Removes outbound Bugsnag crash reporting and the EarTrumpet feedback/telemetry UI. Diagnostics are local-only.
- Removes the legacy EarTrumpet-icon selection feature from the tray-icon path.
- Disables add-on-host startup and removes community/legacy settings pages from the core experience.
- Uses a separate MyMix assembly name, package identity, startup task, mutex identity (via assembly name), and unpackaged registry key.
- Keeps upstream internal namespaces where renaming them would add risk without changing the product identity.

## Build

Run `tools\Convert-ToMyMix.ps1` once from PowerShell on Windows. The main solution after conversion is `MyMix.sln` and the application project is `EarTrumpet\MyMix.csproj`.

## Privacy

MyMix does not initialize Bugsnag and does not transmit crash/diagnostic data to the EarTrumpet project. The diagnostics command writes and opens a local text file only.

## License and attribution

MyMix is based on EarTrumpet. The upstream `LICENSE` is retained and applies to the derived source. `UPSTREAM_README.md` contains the upstream project README captured from the source archive.