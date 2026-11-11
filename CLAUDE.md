# Camelus' Enhanced Quest Log: notes for Claude

World of Warcraft addon for **WoW Forever** that brings classic-style quest log markers to the modern quest log. Repo: https://github.com/Andremijo/QuestLogCompletedMarker

## Working on this project
- Explain changes in plain, non-technical language and say what they mean in practice.
- Reply in the language of the latest message (English or Swedish).
- Testing happens in the game, with screenshots as feedback. You cannot run WoW, so say plainly what has and hasn't been tested.

## The client
- WoW Forever, client 1.60.x, **Interface 16001**. Its UI is the retail ("Mainline") UI with overrides. Internally the game type is `camelot`, and addon managers call it `forever`.
- Blizzard's UI source for this client is mirrored in **Gethe/wow-ui-source, branch `forever`**. Read it instead of guessing. It is huge, so do a sparse, blob-less clone:
  ```bash
  GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 --branch forever --filter=blob:none --sparse https://github.com/Gethe/wow-ui-source ~/wow-ui-source
  git -C ~/wow-ui-source sparse-checkout set --no-cone '/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/' '/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/QuestMapFrame*'
  ```
  Relevant files:
  - `Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua` and `.xml`: the quest log, `QuestLogQuests_Update`, `QuestScrollFrame`, title rows.
  - `Blizzard_UIPanels_Game/Camelot/QuestMapFrameUtils.lua`: Forever's `QuestLogQuests_ShowQuestCount` (the "Quests: 34/40" box).
  - `Blizzard_SharedXML/Shared/InputBox/InputBoxTemplates.xml`: `InputBoxVisualTemplate`, the box art.

## Files
- `CamelusEnhancedQuestLog/CamelusEnhancedQuestLog.toc`: `## Version:` is the single source of the version number.
- `CamelusEnhancedQuestLog/CamelusEnhancedQuestLog.lua`: all the code.
- `CamelusEnhancedQuestLog/CamelusEnhancedQuestLog.tga`: the addon icon (64×64, 32-bit TGA with alpha, uncompressed), set with `## IconTexture:` in the .toc and shown next to the options title. Regenerate it with `python3 media/make_icon.py <out_dir>` (Pillow), which also writes the README image (`media/icon.png` is its `preview_256.png`).
- `CHANGELOG.md`: one `## x.y.z` section per release. The release workflow copies it into the release notes.
- `.github/workflows/release.yml`: builds the zip and `release.json` and publishes the GitHub release.

The addon was called `QuestLogCompleted` up to 1.4.0 and `QuestLogCompletedMarker` ("Quest Log Completed Marker") from 1.5.0 to 1.8.0. Since 2.0.0 it is **Camelus' Enhanced Quest Log**: use that exact name wherever people see it, and `CamelusEnhancedQuestLog` for folder, file and code names (no apostrophe or spaces there). It warns in chat if an old folder is still installed. The GitHub repo is still called `QuestLogCompletedMarker` until the owner renames it on GitHub.

## Features (as of 2.1.0)
- Green check mark to the left of completed quests.
- "(Complete)" / "(Failed)" in the tag column where "(Dungeon)" is shown. Colour is green (default) or the quest title's colour.
- Level letter: `[26D]` for dungeon quests, `[40R]` for raid quests.
- Quest XP after the title: `(1,950 XP)`, from `GetQuestLogRewardXP(questID)` (the same call Blizzard's Forever UI uses). Not shown for 0 XP or at max level. Part of the same title pipeline as the level letter (`UpdateTitle` always rebuilds from Blizzard's text), so it is counted when long titles are wrapped.
- "Quests completed: 5/34" under "Quests: 34/40". The box grows downwards and the list moves down.
- With Leatrix Maps' simple map frame (which hides `QuestLogCount`): " · 5 completed" is appended to Leatrix's own "17/40" in its title bar instead.
- Options window (`/ceql`), also under Options → AddOns, with a live preview and the version in the bottom-right corner.
- Slash commands (`/qlc` still works as an alias): `/ceql`, `/ceql help`, `both|check|text|off`, `level`, `xp`, `color [green|quest]`, `count`, `debug`.
- Saved variables `CamelusEnhancedQuestLogDB`: `mode` (both/check/text/off), `level`, `color` (green/quest), `showCount`, `showXP`.

## Lessons learned (don't undo these)
- **Taint:** never write fields on Blizzard frames. Everything the addon adds is tracked in its own weak tables (`checks`, `ourTags`, `titleState`, ...). Use `hooksecurefunc`, never replace Blizzard functions.
- Blizzard's "(Dungeon)" tag is faded with `SetAlpha(0)`, never hidden or re-texted, and is restored with `SetAlpha(1)`.
- **Long titles:** `SetWidth` on the title FontString does not narrow it (its width comes from anchors), and it caused a phantom row-height change that misaligned the row. Instead the addon inserts a `\n` at a word boundary, measured with its own FontString.
- **The measuring FontString must be emptied and hidden right after measuring.** In 1.2 it kept its text, and recycled rows showed "ghost" titles.
- The check mark and tag are aligned to the top of the title's visible text (`TextTop`), not the FontString's top.
- **Quest count layout:** `QuestLogCount` (100×20) sits to the right of `QuestScrollFrame.SearchBox`, which is anchored `BOTTOMLEFT` to the scroll frame's `TOPLEFT` at y=7. To add a line, the box and its Left/Middle/Right textures grow by `COUNT_EXTRA` (14), the scroll frame's `TOPLEFT` moves down 14, and the search box anchor moves up 14. The search box width is reapplied after every `QuestLogQuests_ShowQuestCount`, because Blizzard resets it there. Layout changes wait until combat has ended.
- **Leatrix Maps compatibility** (source: CurseForge, GitHub mirror `austinrr/leatrix-maps-forever-mirror`). Its "Use simple map frame" hides `QuestLogCount` (Hide + alpha 0), shows its own count FontString ("17/40", a local `LeaMapsCB["MapQuestCount"]`, not reachable by name) in a title bar on `WorldMapFrame`, with the zone menus anchored to its right, and re-anchors `QuestScrollFrame` (ClearAllPoints, TOPLEFT -50) and the search box itself. So: when `QuestLogCount` is not shown or has alpha 0, the addon doesn't move anything. It finds any visible FontString on `WorldMapFrame` (skipping `ScrollContainer`) whose text is exactly "numQuests/max" and appends a suffix it can strip again. `UnshiftPoint` only undoes an anchor if it is still exactly the one we set.
- Better Blizzard Frames does not touch the world map or quest log in WoW Forever (checked its source, `Bodify/BetterBlizzFrames`).
- The options window measures its labels (`BuildOptions` returns a `NeededWidth` function) and is at least 400 px wide, wider if a label needs it. Don't go back to a fixed width.
- `/ceql debug` prints the frames found and the structure of a quest row. Ask the owner for its output when something lines up wrong.

## Checking changes
There is no WoW here. At least check the Lua syntax:
```bash
mkdir -p /tmp/luacheck && cd /tmp/luacheck && npm init -y >/dev/null && npm i luaparse >/dev/null
node -e "require('/tmp/luacheck/node_modules/luaparse').parse(require('fs').readFileSync('CamelusEnhancedQuestLog/CamelusEnhancedQuestLog.lua','utf8'),{luaVersion:'5.1'});console.log('syntax OK')"
```
Run the second command from the repo root.

For logic tests, `pip install lupa` gives a real Lua 5.1 (`from lupa import lua51`). The tests in `tests/` cut a block of functions out of the .lua file, run it with small mock frames and FontStrings, and check the results. Run them all after changes (`python3 tests/test_*.py`, see `tests/README.md`) and add one for new logic.

## Releasing a new version
1. Bump `## Version:` in the .toc and add a `## x.y.z` section at the top of `CHANGELOG.md`.
2. Commit and push to `main`.
3. Start the **Release** workflow with `workflow_dispatch`: the GitHub tool `actions_run_trigger`, workflow `release.yml`, ref `main`. **Pushing tags from a Claude session is refused by the git proxy**, so don't try `git push origin vX.Y.Z`. The workflow creates the tag itself from the .toc version.
4. Check the release: download `CamelusEnhancedQuestLog-vX.Y.Z.zip` and `release.json` from the release and confirm the zip contains only the `CamelusEnhancedQuestLog/` folder.

`release.json` (flavor `"forever"`, interface from the .toc) is what lets WoWUp install from the GitHub URL without a compatibility warning. Keep it.

## Open points
- The quest count box, the version footer and the Leatrix Maps support (1.7.0) and the quest XP (1.8.0) haven't been seen in the game yet. Ask how they look.
- The old v1.4.0 release still has the old name. Only the owner can delete it on GitHub.
