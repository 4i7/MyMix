# MyMix technical changes from EarTrumpet

This document describes implementation-level changes made by MyMix on top of EarTrumpet. It is intended for maintainers who want to understand the runtime differences, review the trade-offs, or selectively port an individual change without adopting the rest of MyMix.

## Comparison baseline

MyMix records the EarTrumpet source revision used to generate the current tree in [`.mymix-converted`](.mymix-converted). The examples in this document were verified against:

- EarTrumpet: [`File-New-Project/EarTrumpet@aa894e51c22f5f9a939b31b224c4d2d3e163416e`](https://github.com/File-New-Project/EarTrumpet/tree/aa894e51c22f5f9a939b31b224c4d2d3e163416e)
- MyMix: the corresponding generated and optimized `main` tree

The Core Audio integration, per-application routing foundation, WPF mixer UI, and much of the Windows interop layer are inherited from EarTrumpet. The sections below describe MyMix-specific changes rather than claiming those inherited components as new work.

## Summary

| Area | MyMix change | Primary implementation |
| --- | --- | --- |
| Peak metering | Single aggregate peak reads, visible-device scoping, cached device snapshots, dropped stale frames, coalesced UI refresh, release smoothing | `Helpers.cs`, `AudioDeviceManager.cs`, `DeviceCollectionViewModel.cs`, `AudioSessionViewModel.cs` |
| Core Audio callbacks | Coalesces repeated volume notifications into at most one pending UI invalidation | `AudioDevice.cs`, `AudioDeviceSession.cs` |
| Process monitoring | Replaces the dedicated wait thread with `Process.Exited` and disposable registrations | `ProcessWatcherService.cs` |
| View-model lifetime | Replaces finalizer-dependent event cleanup with explicit `IDisposable` ownership | `AudioSessionViewModel.cs`, `DeviceViewModel.cs`, `DeviceCollectionViewModel.cs` |
| App information | Shares tracked process metadata per PID and makes process-stop notification race-safe | `AppInformationFactory.cs`, `DesktopAppInfo.cs`, `ModernAppInfo.cs` |
| Icon loading | Adds a bounded, DPI-aware cache of frozen WPF image sources | `ImageEx.cs` |
| Audio model | Removes runtime per-channel volume objects/callback work that MyMix does not expose | `AudioDevice.cs`, `AudioDeviceSession.cs` |
| Settings/volume path | Loads settings into memory once and uses one logarithmic volume path with separate raw/display state | `AppSettings.cs`, `FloatExtensions.cs` |
| Upstream maintenance | Regenerates MyMix from an EarTrumpet revision through scripted transformation, optimization, validation, and provenance checks | `tools/Update-FromEarTrumpet.ps1`, `tools/Optimize-MyMix/` |

## 1. Peak-meter hot path

### What changed

EarTrumpet's baseline peak reader obtains the metering channel count, allocates unmanaged memory, asks Core Audio for all channel peaks, allocates a managed array, copies the unmanaged values into it, and then exposes the first two channels.

MyMix uses the aggregate `IAudioMeterInformation.GetPeakValue()` value instead. This removes the per-sample unmanaged allocation, managed channel array, and `Marshal.Copy` from the 30 FPS meter path.

The sampling loop is also changed so that:

- the target remains 30 FPS;
- a new sampling pass is skipped if the previous pass has not completed;
- at most one render-priority UI refresh can be pending in the Dispatcher queue;
- the full mixer or expanded flyout samples all devices, while the compact flyout samples only the default device;
- `AudioDeviceManager` maintains an array snapshot used by the peak loop instead of rebuilding a collection projection each frame;
- the displayed peak uses fast attack and lightweight release smoothing (`PeakReleaseFactor = 0.72`) to avoid making dropped or aggregate samples look unnecessarily abrupt.

Relevant files:

- [`EarTrumpet/DataModel/WindowsAudio/Internal/Helpers.cs`](EarTrumpet/DataModel/WindowsAudio/Internal/Helpers.cs)
- [`EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceManager.cs`](EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceManager.cs)
- [`EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs`](EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs)
- [`EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs`](EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs)

### Behavioral trade-offs

The meter is deliberately aggregate rather than left/right-channel specific. Under load, stale frames are discarded instead of being delivered late. Release smoothing affects only the visual meter decay, not audio volume or Core Audio state.

### Selective upstream adoption

These changes are separable. Dispatcher coalescing and stale-frame dropping can be used while retaining channel-specific peak reads. Visible-device scoping and the cached device snapshot can also be adopted independently. Switching to `GetPeakValue()` is appropriate only where an aggregate peak is sufficient.

The corresponding transformation stages are primarily:

- `tools/Optimize-MyMix/03-peak-meter.ps1`
- `tools/Optimize-MyMix/03c-visible-peak-scope.ps1`
- `tools/Optimize-MyMix/04b-single-aggregate-peak.ps1`

## 2. Event-driven process monitoring

### What changed

The baseline `ProcessWatcherService` maintains raw process handles and a dedicated background thread. The thread repeatedly creates a handle array and waits with `WaitForMultipleObjects`, including a five-second timeout.

MyMix instead creates a managed `Process`, subscribes to its `Exited` event, and enables event raising. `WatchProcess` now returns an `IDisposable` registration. Internally, registrations receive unique IDs so multiple consumers can watch the same PID and can be removed independently. When the last registration is removed, the event handler is detached and the `Process` object is disposed.

The implementation also handles races where two callers attempt to create the watcher for the same PID at the same time.

Relevant file:

- [`EarTrumpet/DataModel/ProcessWatcherService.cs`](EarTrumpet/DataModel/ProcessWatcherService.cs)

### Behavioral trade-offs

This removes the permanent wait loop and its periodic array construction. It also changes the abstraction from a fire-and-forget static registration to a lifetime-bearing registration object.

Callers that need early cancellation should retain and dispose the returned registration. Existing MyMix app-information call sites currently rely on the process lifetime itself and do not retain that token, so the disposable API should not be interpreted as meaning every current caller explicitly cancels its watch.

### Selective upstream adoption

`ProcessWatcherService` is largely self-contained. It can be ported independently provided callers are compatible with the new return value. Consumers may ignore the returned `IDisposable` to preserve old call-site behavior, or retain it where shorter watcher lifetimes are useful.

## 3. Core Audio callback back-pressure

### What changed

In the baseline device callback, an endpoint-volume notification can synchronously invoke the UI Dispatcher. Session volume notifications also queue UI work for each callback.

MyMix separates state capture from UI invalidation. A Core Audio callback updates the latest raw/display volume and mute state immediately, then calls a coalescing helper. An `Interlocked.Exchange` guard allows at most one pending `DispatcherPriority.DataBind` refresh. Additional notifications arriving before that refresh are represented by the latest stored state rather than by additional queued UI work.

Relevant files:

- [`EarTrumpet/DataModel/WindowsAudio/Internal/AudioDevice.cs`](EarTrumpet/DataModel/WindowsAudio/Internal/AudioDevice.cs)
- [`EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSession.cs`](EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSession.cs)

### Behavioral trade-offs

Intermediate UI states may be skipped when notifications arrive faster than the UI thread can render them. The final state is retained. For a volume slider and mute indicator this is intentional: rendering a backlog of obsolete intermediate values is less useful than keeping the UI close to the newest state.

### Selective upstream adoption

The coalescing helper is independent of MyMix's logarithmic curve and can be applied to the existing EarTrumpet callback paths without changing the Core Audio interfaces.

The transformation is represented by `tools/Optimize-MyMix/11-audio-callback-coalescing.ps1`.

## 4. Explicit view-model lifetime

### What changed

The baseline `AudioSessionViewModel` subscribes to `_stream.PropertyChanged` and attempts to unsubscribe in its finalizer. A publisher event keeps a strong reference to its subscriber, so a finalizer is not a reliable ownership boundary for this relationship: the subscription can itself keep the view model reachable.

MyMix makes `AudioSessionViewModel` implement `IDisposable` and removes the event subscription there. Owning collections explicitly dispose view models when devices or application sessions are removed, replaced, regrouped, reset, or expire.

Relevant files:

- [`EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs`](EarTrumpet/UI/ViewModels/AudioSessionViewModel.cs)
- [`EarTrumpet/UI/ViewModels/DeviceViewModel.cs`](EarTrumpet/UI/ViewModels/DeviceViewModel.cs)
- [`EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs`](EarTrumpet/UI/ViewModels/DeviceCollectionViewModel.cs)

### Behavioral trade-offs

The design requires ownership sites to dispose removed objects correctly. In exchange, event lifetime no longer depends on garbage collection/finalization timing.

### Selective upstream adoption

This change should be ported together with disposal at collection ownership boundaries. Adding `IDisposable` only to the leaf view model without updating removal/replacement paths would leave the intended lifetime improvement incomplete.

The main transformation is `tools/Optimize-MyMix/08-viewmodel-lifetime.ps1`.

## 5. Per-process app-information sharing and process-exit race handling

### What changed

Tracked `IAppInfo` instances are cached by PID using:

`ConcurrentDictionary<int, Lazy<IAppInfo>>`

`LazyThreadSafetyMode.ExecutionAndPublication` prevents duplicate expensive metadata construction when multiple audio sessions for the same process appear concurrently. The cache entry is removed when the process stops.

`DesktopAppInfo` and `ModernAppInfo` also use a sticky stop event. If the process has already stopped when a subscriber attaches, that subscriber is invoked immediately instead of silently missing the one-time event. This closes the race between beginning process tracking and attaching later consumers.

Relevant files:

- [`EarTrumpet/DataModel/AppInformation/AppInformationFactory.cs`](EarTrumpet/DataModel/AppInformation/AppInformationFactory.cs)
- [`EarTrumpet/DataModel/AppInformation/Internal/DesktopAppInfo.cs`](EarTrumpet/DataModel/AppInformation/Internal/DesktopAppInfo.cs)
- [`EarTrumpet/DataModel/AppInformation/Internal/ModernAppInfo.cs`](EarTrumpet/DataModel/AppInformation/Internal/ModernAppInfo.cs)

### Behavioral trade-offs

Tracked sessions for the same PID intentionally share one app-information object and therefore one process-lifetime notification source. PID cache entries are removed on stop rather than retained indefinitely.

### Selective upstream adoption

The cache and sticky-stop semantics can be reviewed separately, although using both together gives the simplest shared lifetime model. The relevant transformation stages are:

- `tools/Optimize-MyMix/10-appinfo-cache.ps1`
- `tools/Optimize-MyMix/16-appinfo-exit-race.ps1`

## 6. Bounded DPI-aware icon cache

### What changed

The baseline `ImageEx` resolves Shell/GDI icon data each time an image source is loaded. MyMix caches the resulting WPF `ImageSource` using a key containing:

- desktop/modern application type;
- requested pixel width and height after DPI scaling;
- icon path.

Cached images are frozen when possible so they can be safely reused as immutable WPF resources. The cache is bounded at 256 entries; when the limit is reached the current implementation clears it rather than maintaining a more complex LRU structure. Native GDI bitmap handles are still released after conversion.

Relevant file:

- [`EarTrumpet/UI/Controls/ImageEx.cs`](EarTrumpet/UI/Controls/ImageEx.cs)

### Behavioral trade-offs

The 256-entry clear-all policy is intentionally simple rather than optimal for every workload. DPI dimensions are part of the cache key, so moving between displays can create additional entries until the bound is reached.

### Selective upstream adoption

The cache is localized to `ImageEx` and does not depend on the other MyMix runtime changes. The transformation is `tools/Optimize-MyMix/09-icon-cache.ps1`.

## 7. Removal of the per-channel runtime model

### What changed

MyMix does not expose per-channel volume control. Instead of only hiding that feature in XAML, it removes the corresponding runtime object graph and callback work from the device model. `AudioDevice` no longer constructs or exposes `AudioDeviceChannelCollection`, and session `OnChannelVolumeChanged` intentionally performs no per-channel model update.

This also aligns with the aggregate single-value peak meter described above.

Relevant files:

- [`EarTrumpet/DataModel/WindowsAudio/Internal/AudioDevice.cs`](EarTrumpet/DataModel/WindowsAudio/Internal/AudioDevice.cs)
- [`EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSession.cs`](EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSession.cs)

### Behavioral trade-offs

Per-channel controls and left/right peak semantics are intentionally unavailable in MyMix. This is a scope reduction, not a transparent optimization.

### Selective upstream adoption

This change is suitable only for a build or mode that does not need per-channel controls. The peak-loop optimizations and callback coalescing do not require removing the channel model and can be adopted without this trade-off.

## 8. Settings and volume hot paths

### Settings

`AppSettings` loads persisted values once into fields during construction. Runtime getters return those in-memory fields, while setters update the field and persist only when a setting changes. This keeps registry/storage abstraction work out of mouse-wheel, hotkey, tray, and flyout read paths.

Relevant file:

- [`EarTrumpet/AppSettings.cs`](EarTrumpet/AppSettings.cs)

### Volume mapping

MyMix uses one logarithmic mapping path rather than checking a linear/logarithmic option during every volume get/set. Raw Core Audio scalar volume and display volume are stored separately. The current curve uses a fixed factor of `3.5`, precomputes the inverse scale, and handles non-positive raw input explicitly when mapping back to display volume.

Relevant files:

- [`EarTrumpet/Extensions/FloatExtensions.cs`](EarTrumpet/Extensions/FloatExtensions.cs)
- [`EarTrumpet/DataModel/WindowsAudio/Internal/AudioDevice.cs`](EarTrumpet/DataModel/WindowsAudio/Internal/AudioDevice.cs)
- [`EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSession.cs`](EarTrumpet/DataModel/WindowsAudio/Internal/AudioDeviceSession.cs)

### Selective upstream adoption

The settings cache can be adopted independently. The logarithmic-only path is a product decision; the raw/display state separation and precomputed curve constants can still be useful in a codebase that keeps a user-selectable mapping mode.

## 9. Regeneratable transformation pipeline

MyMix is maintained as a reproducible transformation of an EarTrumpet source revision rather than only as a manually accumulated fork diff.

[`tools/Update-FromEarTrumpet.ps1`](tools/Update-FromEarTrumpet.ps1) performs the high-level update flow:

1. fetch the requested EarTrumpet revision into an isolated temporary tree;
2. record the exact upstream SHA;
3. preserve MyMix-owned documentation and release metadata;
4. replace the inherited source tree with the requested upstream tree;
5. verify that the imported EarTrumpet `LICENSE` is preserved exactly;
6. run `Convert-ToMyMix.ps1`;
7. run `Finalize-StandaloneMyMix.ps1`;
8. run the staged optimizer in `tools/Optimize-MyMix/`;
9. restore MyMix release metadata;
10. write the upstream provenance marker;
11. run `Test-MyMixRefactor.ps1` to validate expected invariants.

The optimizer is deliberately split into named stages. For an upstream maintainer, these scripts provide a map from a behavior described in this document to the source transformation that introduces it. The generated C# source remains the easiest place to review the final runtime behavior; the scripts show how MyMix reapplies that behavior after a new upstream import.

Additional lifetime-focused checks are present in [`tools/Test-ProcessWatcherLifetime.ps1`](tools/Test-ProcessWatcherLifetime.ps1), while [`.mymix-optimized`](.mymix-optimized) records the optimization feature set expected in the generated tree.

## Porting guidance

The changes with the least product-policy coupling are generally:

- Core Audio UI callback coalescing;
- explicit view-model disposal;
- event-driven process watching;
- per-PID app-information sharing;
- sticky process-stop notification;
- bounded/frozen icon caching;
- peak-loop back-pressure and cached device snapshots.

Aggregate peak reads and removal of the per-channel model intentionally change feature semantics, so they should be evaluated separately from the back-pressure and allocation reductions around them.

When reviewing a change for reuse, compare the generated source file first, then inspect the corresponding `tools/Optimize-MyMix/` stage to see the assumptions MyMix makes when applying it to an upstream EarTrumpet tree.
