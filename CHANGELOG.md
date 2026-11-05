# Changelog

All notable changes to Metal HUD Manager are listed here. Each release's section is also used as its GitHub release notes and is shown in the app's update dialog.

## [1.1.0] - 2026-11-05

### Added

- **All apps switch**: turn the HUD on or off for every app currently shown in the list, after a confirmation.
- **Update checker**: on launch the app checks GitHub for a newer release. When one is available, a download button appears in the toolbar and opens a dialog with the changelog.
- **Show filter**: switch between **All Apps**, **Games** and **HUD Enabled**. The choice is remembered.
- **Game detection**: likely games are marked with a controller icon, based on their App Store category, game controller support, a Steam install, or Unity, Unreal, Godot or Steamworks files. Use **Mark as Game** or **Not a Game** in the **…** menu to correct it.
- **DMG download**: releases now include a `.dmg` you can open and drag to Applications, next to the `.zip`.

### Changed

- The **Enabled only** toggle is replaced by the **HUD Enabled** option in the Show filter.

## [1.0.0] - 2026-11-04

First release.

### Added

- A switch per app to enable the Metal Performance HUD persistently, instead of globally for every Metal app.
- **Launch once with HUD**: start an app with the HUD for a single session, without saving anything.
- Lists apps from `/Applications`, `~/Applications` and your Steam library.
- Shows which apps are running and offers **Restart to apply**.
- Detects when the HUD is enabled globally and lets you turn that off.
- Search and **Add App…** for apps in other locations.
- Universal build for Apple Silicon and Intel Macs.

[1.1.0]: https://github.com/RuggeDX/MetalHUDManager/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/RuggeDX/MetalHUDManager/releases/tag/v1.0.0
