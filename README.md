# Quest Log Completed Marker

A small World of Warcraft addon for **WoW Forever** (client 1.60, Interface 16001) that brings classic-style quest log markers to the modern quest log.

The modern quest log only says "Ready for turn-in" in small text under a finished quest. This addon makes finished quests easy to spot:

- **Green check mark** to the left of completed quests.
- **(Complete)** shown in the tag column, where "(Dungeon)" usually appears, like the classic quest log. Failed quests show **(Failed)**.
- **Level letter** after the quest level: `[26D]` for dungeon quests and `[40R]` for raid quests.
- **Colour choice** for (Complete): green (default) or the same colour as the quest title.
- **Options window** with a live preview.

## Installation

1. Download `QuestLogCompletedMarker-vX.Y.Z.zip` from the [latest release](../../releases/latest).
2. Unzip it into your game's `Interface\AddOns\` folder, so that you have
   `Interface\AddOns\QuestLogCompletedMarker\QuestLogCompletedMarker.toc`.
3. Restart the game or type `/reload`, and make sure the addon is enabled on the character screen.

**With WoWUp:** choose **Get Addons → Install from URL** and paste `https://github.com/Andremijo/QuestLogCompletedMarker`. WoWUp then installs and updates the addon from the releases.

Upgrading from the old name (`QuestLogCompleted`, version 1.4.0 and earlier)? Delete the old `Interface\AddOns\QuestLogCompleted` folder.

If the game says the addon is out of date after a client update, tick **Load out of date AddOns**.

## Options

Type `/qlc` to open the options window. The same page is also under **Options → AddOns → Quest Log Completed Marker**.

| Command | What it does |
| --- | --- |
| `/qlc` | Open the options window |
| `/qlc both` | Show the check mark and (Complete) |
| `/qlc check` | Show only the check mark |
| `/qlc text` | Show only (Complete) |
| `/qlc off` | Show neither |
| `/qlc level` | Turn the D/R letter after the level on or off |
| `/qlc color` | Switch the (Complete) colour between green and the quest's colour (`/qlc color green`, `/qlc color quest`) |
| `/qlc debug` | Print troubleshooting information (open the quest log first) |
| `/qlc help` | List the commands |

Settings are saved per account in `QuestLogCompletedMarkerDB`.

## How it works

The addon doesn't replace the quest log. It finds the quest rows Blizzard draws and adds its own check mark and text on top of them. When a quest title would run into "(Complete)", it wraps the title onto the next line. Everything the addon adds is kept in its own tables rather than on Blizzard's frames, to avoid taint.

## Making a new release

1. Update `## Version:` in `QuestLogCompletedMarker/QuestLogCompletedMarker.toc` and add a section to `CHANGELOG.md`.
2. Commit and push to `main`.
3. On GitHub, open **Actions → Release → Run workflow**. (Or push a tag instead: `git tag v1.5.0 && git push origin v1.5.0`.)

GitHub Actions then creates the tag, builds the zip and publishes the release (`.github/workflows/release.yml`).

## Reporting problems

If something lines up wrong or doesn't show, open the quest log, type `/qlc debug`, and open an issue with a screenshot of the chat output.

## License

MIT. See [LICENSE](LICENSE).
