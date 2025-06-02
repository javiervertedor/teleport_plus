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
- Optional rule enforcement per location (PvP, unbreakable zones)
- Optional HUD waypoints to guide navigation

## Dependencies
- [Unified Inventory](https://content.luanti.org/packages/RealBadAngel/unified_inventory/): Integration with Unified Inventory’s waypoint system (5 per player)

## Optional dependencies
- [Areas](https://content.luanti.org/packages/ShadowNinja/areas/)
- [Protector Redo](https://content.luanti.org/packages/TenPlus1/protector/)
- [Whiter List](https://content.luanti.org/packages/AntumDeluge/whitelist/)

## Commands

| Command                                        | Description                                      |
|-----------------------------------------------|--------------------------------------------------|
| `/setloc <pos> <name> [pvp=on\|off] [editable=on\|off] [radius=number_of_blocks] [HUD=on\|off]` | Set a teleport location at a given position (default current position)     |
| `/delloc <name>`                               | Delete a saved location                          |
| `/listloc`                                     | List available teleport locations                |
| `/tp <targets> <location>`                         | Teleport players (me, all, or list) to a location |
| `/tprestore <targets>`                         | Return players to their previous position        |
| `/setgroup <group> user1, user2, ...`          | Set a group of users                            |
| `/groupadd <group> user1, user2, ...`          | Adds users to a specific group                  |
| `/groupremove <group> user1, user2, ...`       | Removes users from a specific group             |
| `/delgroup <group>`                         | Deletes a group of users                        |
| `/listgroups`                               | Lists all existing groups                          |
| `/group <group>`                               | Lists users in a group                          |
| `/givegroup <group> <item> [quantity]`         | Give items to all online users in a group (max 99) |
| `/groupmsg <group> <message>`                  | Send a private message to all online users in a group |
| `/tpschedule <targets> <location> [day1,day2] <HH:MM> [name=<namestring>] [repeat=on/off]` | Schedule users or group teleport. Time must be in 24-hour format (00:00-23:59) |
| `/schedules`                         | Show current schedules                        |
| `/delschedule <name>`                         | Deletes a teleport schedule                        |
| `/servertime`                        | Show current server time and day              |

Note: `<targets>` can be `me`, `all`, groups `Team1` or `name1,name2`

## Additional Notes

### Group Management
- When creating or modifying groups, the system validates that all players exist in the game's database
- If any player in a group doesn't exist, the operation will fail with a list of invalid players
- Groups cannot be used in commands if they contain invalid players

### Schedule Management
- Schedule names are automatically assigned (Schedule01, Schedule02, etc.) if not specified
- When schedules are deleted, their numbers become available for reuse
- Schedule numbers are kept as low as possible (fills gaps before creating new numbers)
- Custom schedule names can be specified using the `name=` parameter
- Time must be in 24-hour format (00:00-23:59)

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
