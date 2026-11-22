# Four native radius sliders

Version remains 1.0; package/author/icon and retained modules are unchanged.

Settings → Control Center now contains four standard Preferences slider rows directly after the existing enable switch, with the original access/reset rows and explanatory footer retained:

1. Connectivity background
2. Now Playing card
3. Volume + brightness (shared value)
4. Other module cards (generic C18ModuleView container; no bundle-ID allowlist)

Independent domain: `com.ning.controlcenter18.radius`; keys `RadiusConnectivity`, `RadiusPlayer`, `RadiusSliders`, `RadiusOther`. Range 0–100, default 0. Zero means unmodified native appearance. Positive values interpolate the native corner radius toward half the surface's short side. A 2×2 square is eligible; a single 1×1 round button is not. The core's grid enum is 0=1×1, 1=1×2, 2=2×1, 3=4×1, 4=2×2, etc. Detection uses current span rows/columns, falling back to the enum, not screen aspect ratio.

The runtime hooks only seven CC18-specific `layoutSubviews` methods with ABI checks and per-hook once guards. Original layout executes first. Exact content/background/platter surfaces receive continuous corner clipping. Existing snapshots are restored before native layout; zero, circular mode and expanded menus restore native state. No global UIView/CALayer hook, recursive image scan, frame/transform changes or replacement artwork is used. Close/resize accessories remain outside the clipped content.

Values are saved through CFPreferences; a dedicated Darwin notification invalidates cached values. The current module tree is marked for layout, and preferences are reloaded on the next CC presentation. Changing radius does not request respring. Installing the updated dylib still requires the normal user-managed restart/respring to load it.

## Evidence and tests

- Existing pinned core class metadata: C18ModuleView `_cornerRadius`, `size`, `spanColumns`, `spanRows`, `contentView`, `platter`; specialized C18ConnectivityView/C18NowPlayingView/C18VolumeView/C18BrightnessView/C18ButtonModuleView/C18FocusView layout methods.
- Production C geometry compiled and run on the build host; 494,817 assertions.
- 6,144 repeated/partial native-list placement models plus existing 37,376 safe module-routing cases.
- Strict iOS arm64/arm64e syntax checks run locally before CI.
- CI verifies both final packages, actual arm64e ABI bit, macOS strict all-architecture signatures and new runtime/slider markers in each slice.

These checks are not UIKit/device visual validation. Verify real settings display, four independent values, resize transitions, default-zero restoration, and circular-button preservation on the target device. No automatic install, injection, respring or repository publication is part of the build request.
