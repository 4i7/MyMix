# Compiling MyMix

MyMix is built as a standalone x86 WPF application. The public distribution build does not require the original EarTrumpet Store/MSIX packaging project.

## Requirements

- Windows 10 or Windows 11 development machine.
- Git for Windows.
- Visual Studio 2022 Build Tools or Visual Studio with MSBuild and the .NET desktop build tools.
- NuGet CLI.
- .NET Framework 4.6.2 reference assemblies. The repository workflows can obtain `Microsoft.NETFramework.ReferenceAssemblies.net462` 1.0.3 into a build-tool cache when the targeting pack is not installed locally.

## Build the current MyMix tree

From a Developer PowerShell/PowerShell session at the repository root:

```powershell
nuget restore .\EarTrumpet\packages.config -PackagesDirectory .\packages
msbuild .\EarTrumpet\MyMix.csproj /m /p:Configuration=Release /p:Platform=x86
```

If the machine does not have the .NET Framework 4.6.2 targeting pack, use the same portable-reference-assembly setup implemented in `.github/workflows/apply-mymix.yml` and pass its calculated `TargetFrameworkRootPath` to MSBuild.

The Release output is written under `Build\Release`.

## Rebuild from EarTrumpet upstream

MyMix is maintained as a reproducible transformation of an EarTrumpet source revision rather than as an unrestricted direct merge. `tools\Update-FromEarTrumpet.ps1` imports a requested upstream revision into a clean working tree, then runs:

1. `Convert-ToMyMix.ps1`
2. `Finalize-StandaloneMyMix.ps1`
3. `Optimize-MyMix.ps1`
4. `Test-MyMixRefactor.ps1`
5. Release/x86 compilation in the GitHub workflow

The optimizer is intentionally fail-fast. If an EarTrumpet update changes code that a MyMix transformation expects, the update should fail for review instead of silently producing a partially transformed binary.

The exact imported upstream commit is recorded in `.mymix-converted`. MyMix-maintained public documentation is preserved across upstream refreshes; the upstream `LICENSE` is refreshed verbatim and `UPSTREAM_README.md` captures the upstream README.

## Validation expectations

Before distributing a build, require all of the following to pass on the Windows self-hosted runner: transformation invariants, public/privacy hardening assertions, Release/x86 compilation with warnings treated as errors, and the `--smoke-test` startup path. The smoke test checks that the application can initialize and exit cleanly; it does not replace interactive testing of every audio device, DPI/theme, taskbar, routing, or hotkey scenario.

## Architecture

Keep x86 unless the inherited P/Invoke/Core Audio interop surface is separately audited for another target architecture. Changing `PlatformTarget` alone is not sufficient evidence that the native interop declarations are safe on x64/ARM64.
