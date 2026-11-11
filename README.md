# Camelus' Enhanced Quest Log

<img src="media/icon.png" alt="Camelus' Enhanced Quest Log icon" width="128">

A small World of Warcraft addon for **WoW Forever** (client 1.60, Interface 16001) that brings classic-style quest log markers to the modern quest log.

The modern quest log only says "Ready for turn-in" in small text under a finished quest. This addon makes finished quests easy to spot:

- **Green check mark** to the left of completed quests.
- **(Complete)** shown in the tag column, where "(Dungeon)" usually appears, like the classic quest log. Failed quests show **(Failed)**.
- **Level letter** after the quest level: `[26D]` for dungeon quests and `[40R]` for raid quests.
- **Quest XP** after the title, e.g. `(1,950 XP)`.
- **Colour choice** for (Complete): green (default) or the same colour as the quest title.
- **Completed count**: "Quests completed: 5/34" under "Quests: 34/40" at the top of the quest log.
- **Options window** with a live preview.

### Works with Leatrix Maps

With Leatrix Maps' "Use simple map frame", Blizzard's "Quests: 34/40" box is replaced by "17/40" in the map's title bar. The completed count is then shown there instead: "17/40 · 5 completed".

## Installation

1. Download `CamelusEnhancedQuestLog-vX.Y.Z.zip` from the [latest release](../../releases/latest).
2. Unzip it into your game's `Interface\AddOns\` folder, so that you have
   `Interface\AddOns\CamelusEnhancedQuestLog\CamelusEnhancedQuestLog.toc`.
3. Restart the game or type `/reload`, and make sure the addon is enabled on the character screen.

**With WoWUp:** choose **Get Addons → Install from URL** and paste `https://github.com/Andremijo/QuestLogCompletedMarker`. WoWUp then installs and updates the addon from the releases.

Upgrading from an old name? Delete the old folder: `Interface\AddOns\QuestLogCompletedMarker` (versions 1.5.0 to 1.8.0) or `Interface\AddOns\QuestLogCompleted` (1.4.0 and earlier). The addon warns in chat if one is still installed.

If the game says the addon is out of date after a client update, tick **Load out of date AddOns**.

## Options

Type `/ceql` to open the options window. The same page is also under **Options → AddOns → Camelus' Enhanced Quest Log**.

| Command | What it does |
| --- | --- |
| `/ceql` | Open the options window (`/qlc` also works) |
| `/ceql both` | Show the check mark and (Complete) |
| `/ceql check` | Show only the check mark |
| `/ceql text` | Show only (Complete) |
| `/ceql off` | Show neither |
| `/ceql level` | Turn the D/R letter after the level on or off |
| `/ceql xp` | Turn the quest's XP after the title on or off |
| `/ceql count` | Turn "Quests completed: 5/34" under the quest count on or off |
| `/ceql color` | Switch the (Complete) colour between green and the quest's colour (`/ceql color green`, `/ceql color quest`) |
| `/ceql debug` | Print troubleshooting information (open the quest log first) |
| `/ceql help` | List the commands |

Settings are saved per account in `CamelusEnhancedQuestLogDB`.

## How it works

The addon doesn't replace the quest log. It finds the quest rows Blizzard draws and adds its own check mark and text on top of them. When a quest title would run into "(Complete)", it wraps the title onto the next line. Everything the addon adds is kept in its own tables rather than on Blizzard's frames, to avoid taint.

## Making a new release

1. Update `## Version:` in `CamelusEnhancedQuestLog/CamelusEnhancedQuestLog.toc` and add a section to `CHANGELOG.md`.
2. Commit and push to `main`.
3. On GitHub, open **Actions → Release → Run workflow**. (Or push a tag instead: `git tag v1.5.0 && git push origin v1.5.0`.)

GitHub Actions then creates the tag, builds the zip and publishes the release (`.github/workflows/release.yml`).

## Reporting problems

If something lines up wrong or doesn't show, open the quest log, type `/ceql debug`, and open an issue with a screenshot of the chat output.

## License

MIT. See [LICENSE](LICENSE).
