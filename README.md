# CoverFlow

A Windows game library built with Godot, featuring rotating 3D cases, local cover artwork, a street-art interface, and playtime tracking.

## Features

- Discover installed games from Steam, Epic Games, Xbox / Microsoft Store, Rockstar, GOG, EA, and Ubisoft. Select which games to add.
- Drag the bottom bar or use the arrow controls to browse; drag a case to rotate it.
- Import front-only, separate front/back, or full-wrap artwork from your computer.
- Adjust artwork size, width, and height per game without modifying the original image.
- Launch games using their launcher integration or a selected executable/shortcut.
- View tracked playtime, last played, session counts, and local milestones in a collapsible stats panel.

Cover artwork is local-only. This project contains no online cover search or automatic artwork downloads.

## Run the app

Download a Windows build from the repository's Releases section when one is available. Extract the ZIP and run `CoverFlow.exe`. Godot is not required for the exported app.

This source ZIP does not contain an EXE or any installed games.

## Open or build the project

1. Install Godot 4.5.1 with the matching export templates.
2. Import `project.godot` into Godot and open the project.
3. Run the main scene to preview the app. Windows is required for installed-game discovery and launching.
4. To build, choose **Project → Export → Windows Desktop**. Choose your output path and leave **Embed PCK** enabled.

No API keys, account passwords, or external service setup are required.

## Add artwork

Select a game, click the gear beside **Play Game**, and choose **Upload local cover**. Select a layout and your image files, then apply them. Use **Edit artwork size** to adjust the fit.

Game artwork is not bundled. Use images you have permission to use.

## Playtime tracking

Launch a game through CoverFlow and leave CoverFlow open; minimizing it is fine. Tracking starts when a matching game process is detected and ends when the process closes. If automatic detection misses a game, use **Tracking executable** in the gear menu to select the actual game EXE.

- Time is measured only while CoverFlow is open; historical launcher hours are not imported.
- Running time includes game menus and idle time. Sleep/suspend gaps are excluded.
- Sampling is approximately every three seconds, so totals are estimates.
- Protected processes or unusual launcher handoffs may require configuration or may not be detectable.
- Milestones belong to CoverFlow and are not official platform achievements.

## Privacy and saved files

Game discovery and tracking read local installation and process information. Data is stored locally under:

```text
%APPDATA%\Godot\app_userdata\CoverFlow\
```

`coverflow_library.json` stores game records and artwork references. `coverflow_stats.json` stores tracked time. Neither file nor any personal covers are included in this repository. The `.gitignore` excludes common saved-data files, credentials, caches, and exported builds.

## Tests

The `tests/` directory includes Godot checks for stats persistence, artwork dimensions, and panel controls, plus mocked PowerShell process-monitor tests. Run tests with an isolated user-data directory so they cannot overwrite your own library.

For Godot tests, use a separate copy with a different application name or an isolated test account. Native Windows game detection should also be tested with actual installations.

## Credits

- Built with Godot Engine. See `GODOT_LICENSE.txt` and `GODOT_COPYRIGHT.txt`.
- Anton font: see `assets/OFL-Anton.txt`.
- Alley and sticker assets were generated for this project with AI assistance.

Third-party license files apply to their respective components. No additional license for the original application code is selected by this cleanup.
