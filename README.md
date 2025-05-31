# teleport_plus

This is a modular teleportation system for the Luanti game engine (Minetest-based), designed specifically for educational and classroom use.

## Overview

This mod provides immersive, teacher-friendly teleportation features. It allows defining named locations, teleporting individuals or groups, and integrating with the broader mod ecosystem including Unified Inventory, areas/protector mods, and visual markers.

## Features

- Named teleport locations (e.g. school, farm, lab)
- Group teleportation with support for `me`, `all`, and player lists
- Group management system with item distribution and messaging
- Scheduled teleports for automatic class movement
- Return teleport to bring players back to their original location
- Wooden signpost or banner marker nodes to visually represent destinations
- Optional rule enforcement per location (PvP, unbreakable zones)
- Minimap HUD waypoints to guide navigation
- No overlap with travelnet or sethome mods

## Dependencies
- [Unified Inventory](https://content.luanti.org/packages/RealBadAngel/unified_inventory/): Integration with Unified Inventory’s waypoint system (5 per player)

## Optional dependencies
- [Areas](https://content.luanti.org/packages/ShadowNinja/areas/)
- [Protector Redo](https://content.luanti.org/packages/TenPlus1/protector/)
- [Travelnet](https://content.luanti.org/packages/mt-mods/travelnet/)
- [Whiter List](https://content.luanti.org/packages/AntumDeluge/whitelist/)

## Commands

| Command                                        | Description                                      |
|-----------------------------------------------|--------------------------------------------------|
| `/setloc <pos> <name> [pvp=on\|off] [editable=on\|off]` | Set a teleport location at a given position (default current position)     |
| `/tp <targets> <name>`                         | Teleport players (me, all, or list) to a location |
| `/delloc <name>`                               | Delete a saved location                          |
| `/listloc`                                     | List available teleport locations                |
| `/tprestore <targets>`                         | Return players to their previous position        |
| `/setgroup <group> user1, user2, ...`          | Set a group of users                            |
| `/groupadd <group> user1, user2, ...`          | Adds users to a specific group                  |
| `/groupremove <group> user1, user2, ...`       | Removes users from a specific group             |
| `/deletegroup <group>`                         | Deletes a group of users                        |
| `/group <group>`                               | Lists users in a group                          |
| `/givegroup <group> <item> [quantity]`         | Give items to all online users in a group (max 99) |
| `/groupmsg <group> <message>`                  | Send a private message to all online users in a group |
| `/schedule_teleport <targets> <location> <day1,day2> <HH:MM>` | Schedule users or group teleport              |

Note: `<targets>` can be `me`, `all`, groups `Team1` or `name1,name2`

## Marker Nodes

Teachers/admins can place visual markers (`tp_marker:signpost`) at teleport destinations. These do not teleport on right-click and act as immersive labels.

## License

This project is licensed under the [Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)](https://creativecommons.org/licenses/by-nc/4.0/) license.

### You are free to:
- Share — copy and redistribute the material in any medium or format
- Adapt — remix, transform, and build upon the material

### Under the following terms:
- **Attribution** — You must give appropriate credit (to Francisco Javier Vertedor Postigo), provide a link to the license, and indicate if changes were made.
- **NonCommercial** — You may not use the material for commercial purposes.

---

Developed by Francisco Javier Vertedor Postigo for Luanti educational environments.
