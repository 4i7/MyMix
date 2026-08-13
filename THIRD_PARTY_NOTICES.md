# Third-Party Notices and Provenance

## EarTrumpet

MyMix is an independent derivative of [File-New-Project/EarTrumpet](https://github.com/File-New-Project/EarTrumpet). The exact imported upstream commit is recorded in `.mymix-converted`, and `UPSTREAM_README.md` preserves the imported upstream README for reference.

The upstream `LICENSE` is retained verbatim at the repository root and applies to the inherited/derived source according to its terms. It contains MIT-style permission text **and explicit excluded entities before that text**. Do not replace it with a generic MIT license file or describe MyMix as simply/unmodified “MIT licensed.”

Upstream EarTrumpet authors and contributors retain their applicable copyright in inherited code. The continued presence of internal `EarTrumpet.*` namespaces is a source-compatibility decision and does not indicate that MyMix is an official EarTrumpet build.

MyMix is not maintained, supported, sponsored, or endorsed by the EarTrumpet project. Problems caused by MyMix-specific changes should be reported to MyMix rather than to the upstream maintainers.

## Upstream application artwork

EarTrumpet's upstream README credits its “Horn” icon to Artjom Korman from the Noun Project. MyMix public hardening removes the bundled upstream `Icon-Light.ico` and `Icon-Dark.ico` application/horn assets rather than redistributing them as MyMix branding. The runtime tray uses Windows-provided audio/system icon resources and a stock system fallback.

## Microsoft.NETFramework.ReferenceAssemblies

`Microsoft.NETFramework.ReferenceAssemblies` / the .NET Framework 4.6.2 reference-assembly package is used only as a build-time targeting aid when the local targeting pack is unavailable. It is not an application runtime dependency shipped as a MyMix third-party DLL in the standalone release payload.

## Adding dependencies

Before adding another third-party package or asset, document its purpose, source, version, license/redistribution terms, and whether it is shipped in the release payload. Public-release validation should fail rather than silently introducing an unreviewed dependency.
