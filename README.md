# Inventory BackPack for Multiplayer — Farming Simulator 25

![Inventory BackPack logo](assets/backpack-preview.png)

**Version:** 1.0.0.0  
**Author:** Vovainter  
**Game:** Farming Simulator 25 (PC)  
**Mode:** Singleplayer and multiplayer, including dedicated servers

[Русское описание / Russian documentation](README_RU.md)

## About

Inventory BackPack adds a personal inventory for portable game objects. Instead of leaving your filters, grease guns, small boxes and consumables at the farm or workshop, you can carry them with your character.

The inventory is intended for **portable objects only** — not tractors, trailers, vehicles or implements. Compatible modded items must meet the game's portability and persistent-object requirements.

## Features

- Personal backpack per multiplayer player, including dedicated-server sessions.
- Up to **15 individual items**, displayed in a **5 × 3 grid**.
- Items with matching configurations can be grouped visually with a quantity counter.
- Mouse selection or keyboard navigation using the arrow keys.
- Persistent inventory ownership metadata in each individual savegame (`InventoryBackPack.xml`).
- The existing game object is temporarily stored and restored; the mod does not intentionally create a duplicate item.
- Shop item images and item descriptions where provided by the game or source mod.
- Uses the game's input binding system.

## Controls

| Key | Action |
| --- | --- |
| `I` | Open / close backpack (while on foot) |
| `Y` | Store the targeted eligible portable object |
| Arrow keys | Select an inventory slot |
| `Enter` | Drop the selected object |
| Mouse | Select an item in the grid |
| `Esc` | Close the dialog |

## Install

1. Download the **`FS25_InventoryBackPack_for_Multiplayer.zip`** file from [Releases](../../releases) (not the auto-generated GitHub source-code archive).
2. Copy the ZIP **without extracting it** to your FS25 mods folder: `Documents/My Games/FarmingSimulator2025/mods` (or the active custom mod directory).
3. For multiplayer, install the **same ZIP version** on the dedicated server and every player client.
4. Enable the mod for the savegame.
5. Back up your savegame before upgrading or using the mod on an important server.

## Data and safety

Inventory data is saved in the savegame's own `InventoryBackPack.xml`. Players' backpacks and separate game saves should stay independent. Objects must have a suitable persistent identifier to enter the backpack.

**Important:** This is an actively tested community mod. Dedicated-server save/restart behaviour, item-specific compatibility and any new release should be verified on a backup before use on a production savegame. Some modded objects may not be supported.

## Report a bug

Open a [GitHub Issue](../../issues) and include:
- Mod version and whether you play singleplayer or on a dedicated server.
- A short description of what you did, expected to happen and what actually happened.
- Relevant entries from the client and/or server `log.txt`.
- The name of any other mod whose item was involved.

Please remove passwords, access tokens, player identifiers or other private data from logs before uploading.

## Credits

Created by **Vovainter** for Farming Simulator 25.  
Farming Simulator is a trademark of GIANTS Software. This project is not affiliated with GIANTS Software.

## License

A public repository alone does not grant permission to reuse or redistribute source code. A license has **not yet been selected**. Contact the author for licensing or reuse permissions.
