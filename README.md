# MyMix

MyMix is a private Windows volume mixer derived from EarTrumpet. The fork is intentionally narrowed to a lightweight, logarithmic-only mixer experience.

## Conversion

The repository currently contains the upstream `EarTrumpet-master.zip` source snapshot. Run the following once from a Windows PowerShell or Visual Studio Developer PowerShell:

```powershell
.\tools\Convert-ToMyMix.ps1
```

The converter expands the upstream source into the repository, applies the MyMix refactor, removes the source ZIP unless `-KeepArchive` is supplied, validates the result, restores packages when `nuget.exe` is available, and builds `Release|x86` when `msbuild.exe` is available.

After conversion the main solution is `MyMix.sln` and the application project is `EarTrumpet\MyMix.csproj`.

## Refactor scope

- Right-side device/app numeric volume labels are removed. Their reserved column is deleted and the slider receives the reclaimed width with a 16 px right inset.
- Logarithmic volume mapping is unconditional. The runtime linear/logarithmic branch is removed from the real and mock audio paths, and the conversion math avoids recomputing the curve scale.
- Bugsnag reporting, its configuration, and its NuGet references are removed. Diagnostics remain local-only.
- EarTrumpet feedback/telemetry UI is removed from the active MyMix settings experience.
- The legacy EarTrumpet icon selection setting is disabled and removed from the tray-icon hot path.
- Add-on-host startup and add-on menu/settings integration are disabled for the lean core runtime.
- MyMix uses a separate assembly name, package identity, startup task, mutex identity (through the assembly name), and unpackaged registry key.
- Internal `EarTrumpet.*` namespaces are intentionally retained to avoid a large no-op namespace churn that would make the functional refactor harder to audit.

## Privacy

MyMix does not initialize Bugsnag and does not send crash or diagnostic data to the EarTrumpet project. The diagnostics command writes a temporary local text file and opens it locally.

## License and attribution

MyMix is derived from EarTrumpet. The upstream `LICENSE` must remain with the derived source. During conversion the upstream README is preserved as `UPSTREAM_README.md`.
