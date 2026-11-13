# Tests

Logic tests that run parts of the addon in a real Lua 5.1 with small mock frames. They don't need WoW.

```bash
pip install lupa
python3 tests/test_foreign.py   # " · 5 completed" after Leatrix Maps' quest count
python3 tests/test_layout.py    # moving the quest list for the two-line count box, and undoing it
python3 tests/test_xp.py        # "(1,950 XP)" after the quest title
python3 tests/test_poi.py       # replacing Blizzard's "?" completed marker, and always giving it back
```

Each test cuts a block of functions out of `CamelusEnhancedQuestLog.lua` by its comments and function names. If you rename those, update the test.
