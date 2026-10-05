# Attunely

Raid attunement checker for **Turtle WoW / Capycraft** (Vanilla 1.12). See which raid attunements you and your guildmates have, from the guild panel, a guild-wide roster window, or the right-click menu. It includes custom server content like Emerald Sanctum and the Karazhan keys.

Works with the default UI and with pfUI (it picks the matching look automatically).

> **Everyone in the guild needs the addon installed.** There is no way to read another player's attunements without it, so each player's addon reports their own status and shares it with the guild.

## Tracked attunements

| Key | Raid | How it's detected |
|-----|------|-------------------|
| `ony` | Onyxia | Item: Drakefire Amulet |
| `mc`  | Molten Core | Quest: Attunement to the Core |
| `bwl` | Blackwing Lair | Quest: Blackhand's Command |
| `es`  | Emerald Sanctum | Item: Gemstone of Ysera |
| `nax` | Naxxramas | Quest: The Dread Citadel - Naxxramas |
| `kut` | Karazhan Upper Key | Item: Upper Karazhan Tower Key |
| `ksm` | Karazhan Scepter | Item: Scepter of Medivh |

Item-based attunements are found in your bags, bank or equipped gear. Quest-based ones are recorded when you turn the quest in, and past turn-ins are picked up from the server's completed-quest list, pfQuest or Questie when available. Being inside a raid zone or having a raid lockout also counts as proof.

You can add or rename attunements by editing the `RAIDS` list at the top of `Attunely.lua`.

## Installation

1. Download the latest release and unzip it.
2. Put the `Attunely` folder in `World of Warcraft\Interface\AddOns\`.
3. Log in. If you are upgrading from the old **AttuneCheck**, delete that folder first. Your saved data carries over.

## Features

### Guild panel
Open the guild roster and click a member. A panel under the member details shows each raid as **Attuned** (green), **No** (red), or **?** (no data), plus how old the data is. Your own row is always live.

### Roster window
Open it with the minimap button or `/attune roster`.

- A table of all guild members with one column per raid.
- **Search bar** to find a single player.
- **Raid filter button** (left-click for the next raid, right-click for the previous one) and a **Show** button that cycles Everyone / Missing / Attuned.
- Filters for **Online only**, **Group only** and **With addon data**.
- Click a column header to sort by name or by that raid.
- **Refresh** asks everyone to resend their data.
- **Print missing** lists who is missing the selected raid in your chat window. **Post missing** sends the same list to raid, party or guild chat (whichever applies, in that order).

### Right-click menu
Right-click a player in your group, raid or guild to see their attunements in an **Attunements** submenu.

### Minimap button
- **Left-click:** open the roster window.
- **Right-click:** options menu (open roster, request data, show or hide the guild panel extra, choose which raids to show, hide the button).
- **Drag:** move it around the minimap.
- **Hover:** your own attunements and how many guild members have shared data.

## Commands

`/attune` and `/attunely` are the same command.

| Command | What it does |
|---------|--------------|
| `/attune` | Rescan and show your own attunements |
| `/attune <name>` | Show a guildie's attunements from cached data |
| `/attune roster` | Open or close the roster window |
| `/attune refresh` | Ask the guild to resend their attunements |
| `/attune who <key>` | List who is and isn't attuned for a raid, for example `/attune who es` |
| `/attune alts` | Show saved attunements for all your characters |
| `/attune minimap` | Show or hide the minimap button |
| `/attune set <key> [player]` | Mark an attunement as done (officers only for other players) |
| `/attune unset <key> [player]` | Mark an attunement as not done (officers only for other players) |
| `/attune probe` | Show which quest-history sources your client has (for troubleshooting) |
| `/attune hist` | Search your pfQuest history for attunement quests (for troubleshooting) |
| `/attune debug` | Print pfUI layout info (for troubleshooting) |

Keys: `ony` `mc` `bwl` `es` `nax` `kut` `ksm`

### Manual overrides
If an attunement can't be detected automatically (for example a quest you finished before installing the addon), set it yourself with `/attune set mc`. Setting or unsetting for **another player** is limited to guild officers. By default that means Guild Master and the next rank down. Change `OFFICER_MAX_RANK` in `Attunely.lua` to include more ranks. The other player must be online with the addon, and their addon checks that the sender really is an officer before accepting the change.

## Notes

- Data is only as fresh as the last time that player was online with the addon. The panel and roster show how old each entry is.
- Players without the addon show as **?**, not as "No".
- Saved data lives in the `AttuneDB` saved variable, which is why it survives the AttuneCheck to Attunely rename.

## Credits

Made by Ironshield (rotaruandrei93) for Blades of Wrynn.
