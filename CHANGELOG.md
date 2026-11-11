# Changelog

## 2.1.0

- New addon icon (a camel with a green check mark). It shows in the game's AddOns list and next to the title in the options.

## 2.0.0

- Renamed to **Camelus' Enhanced Quest Log**. The addon folder is now `CamelusEnhancedQuestLog`.
- Delete the old `QuestLogCompletedMarker` folder in `Interface\AddOns`. The addon warns in chat if it is still installed.
- Settings start from the defaults again after the rename, because the game stores them under the folder name.
- The options command is now `/ceql`. `/qlc` still works.

## 1.8.0

- New: the quest's XP after the title, e.g. "[33] Vahlarriel's Search (1,950 XP)". It is hidden for quests without XP and at max level. Turn it off in the options ("Quest title") or with `/qlc xp`.

## 1.7.1

- The options window widens itself to fit its longest line, so no text runs outside it. The quest count option has a shorter label.

## 1.7.0

- Works with **Leatrix Maps** and its "Use simple map frame" option. Leatrix Maps hides Blizzard's "Quests: 34/40" box and shows "17/40" in its own title bar, so the completed count is now added there: "17/40 · 5 completed".
- When another addon hides the quest count box, the quest list is no longer moved down.

## 1.6.1

- The options window and the Options → AddOns page show the addon version in the bottom right corner.

## 1.6.0

- New: "Quests completed: 5/34" under "Quests: 34/40" at the top of the quest log. The box grows to two lines, and the quest list moves down a little to make room. Turn it off in the options or with `/qlc count`.

## 1.5.1

- Releases now include a `release.json`, so WoWUp can tell the addon is for WoW Forever and install it from the GitHub link without a warning.

## 1.5.0

- Renamed to **Quest Log Completed Marker**. The addon folder is now `QuestLogCompletedMarker`.
- If you had the old `QuestLogCompleted` folder installed, delete it. The addon warns in chat if both are installed.
- Settings start from the defaults again after the rename.

## 1.4.0

First public release.

- Green check mark to the left of completed quests in the modern quest log.
- (Complete) / (Failed) shown where (Dungeon) usually appears, like the classic quest log.
- D/R after the quest level for dungeon and raid quests, e.g. [26D].
- (Complete) in green (default) or in the quest title's colour.
- Long titles wrap instead of running into (Complete).
- Options window (`/qlc`), also under Options → AddOns, with a live preview.
