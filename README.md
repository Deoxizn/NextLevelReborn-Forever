# NextLevelReborn Forever 2.1.0

Remake of **Nextlevel - Classic** (WoWInterface, 2019-09-20, Classic 1.13.2, 244 downloads) for **WoW Forever, game version 1.60.1, Interface 16001, level cap 60**.

Original: when you kill an enemy, finish a quest, explore, or gain rep, you get a chat message telling you how many more of those you need to kill / do to level up, or to raise that faction's standing.

## Install

1. Exit WoW completely.
2. Copy the `NextLevelReborn` folder into the **Forever** client, not retail:
   - Windows: `World of Warcraft\_forever_\Interface\AddOns\`
   - Linux / Proton (Heroic / Steam): `.../World of Warcraft/_forever_/Interface/AddOns/`
   - Beta was `_classic_beta_`, live is `_forever_`. If in doubt, Battle.net app, Forever version, cog next to Play, Show in Explorer.
3. Result must be `Interface/AddOns/NextLevelReborn/NextLevelReborn.toc`
4. Log in, enable it on the character screen if needed, `/reload` after edits.

No libraries, no dependencies, no WeakAuras.

## What it prints

Kill a mob:
```
NLR: 38 more kills like that to level  |  avg 1,240 XP/kill
```

Turn in a quest (quest XP is huge in 80-90, so it does NOT pretend that was a kill):
```
NLR: 7 more gains like that to level  |  41 kills at your recent average (1,240 XP/kill)
```

Gain rep:
```
NLR: Silvermoon Court: +250 rep  |  9 more gains like that to Renown 12 (2,250 to go)
```

At level 60 the XP half turns itself off. Rep keeps running. Forever XP is the Classic curve, 4,084,700 total to 60, rested doubles kill XP up to 150% of a level, green mobs give less than Classic, dungeon mobs give less and dungeon quests give more.

## Commands

```
/nlr            help
/nlr xp         toggle XP messages
/nlr rep        toggle rep messages
/nlr xp/hr      toggle XP/hr + time-to-level estimate
/nlr verbose    also print raw +gain, %, rested XP banked
/nlr status     current XP, session XP, kill average
/nlr reset      reset session counters
```

## What changed vs the 2019 original

| | 2019 Classic (1.13.2) | This remake (12.1.5) |
|---|---|---|
| TOC | `11302` | `16001` |
| Level cap | 60 | 60 |
| Combat log | could lean on XP chat/combat-log lines | **not used at all** — `COMBAT_LOG_EVENT_UNFILTERED` / `CombatLogGetCurrentEventInfo()` are gone for addons in Midnight |
| XP source | `UnitXP` / `PLAYER_XP_UPDATE` diff | same event, but kills vs quests tracked separately + rolling average of last 10 kills |
| Rep source | `GetFactionInfo` diff | same, plus `CHAT_MSG_COMBAT_FACTION_CHANGE` for the exact gain; generic on `bottomValue` / `topValue` / `earnedValue` so it works for Renown (2500/step, Warband-shared, cap 20, Paragon after) and old standings |
| APIs | pre-`C_` globals | no dead globals (`GetSpellInfo` etc.), Lua 5.1 only, no LibStub/Ace |
| Settings | none | SavedVariables + `/nlr` toggles |

## What it does NOT do (Midnight rules)

- No combat decisions, no damage/healing numbers, no cooldown or aura reading in combat. XP and rep are not secret values, so those APIs still work.
- No `SendAddonMessage`, no automation, no auto-questing. It only prints text after you already gained something.
- No XP/hr spam in the first minute of a session; it waits until it has >60s of data.

## Known limits (honest)

- Not tested in-game by the author of this remake (no live WoW client here). Lua was syntax-checked only. Load it, kill one mob, turn in one quest, gain rep once, and check for errors. If you see a Lua error, paste it back.
- Kill vs quest classification relies on a combat-XP chat line arriving <1s before `PLAYER_XP_UPDATE`. If Blizzard changes that timing, a quest can be mislabelled a kill for one message; the rolling kill average is unaffected.
- Renown standing labels come from the generic faction ladder. If a Midnight faction reports a different `standingId` scheme, the "to Renown N" text may say "Standing N" instead — the number of gains and rep-to-go are still right.
- Delve / Prey / Labyrinth (12.1.5) XP counts as "other gains", same as quests. That is deliberate: their XP per run is not a kill.

## Files

```
NextLevelReborn/
  NextLevelReborn.toc
  NextLevelReborn.lua
```

Original addon: https://www.wowinterface.com/downloads/info25334-Nextlevel-Classic.html
