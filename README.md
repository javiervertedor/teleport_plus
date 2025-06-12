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
| `/setloc <pos> <name> [pvp=on\|off] [tp=on\|off] [editable=on\|off] [radius=number_of_blocks] [HUD=on\|off]` | Set a teleport location at a given position (default current position)     |
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

## Teleportation Area Restrictions

When creating a location with `/setloc`, you can use the `tp=on|off` parameter:

- `tp=on` (default): Players inside this area can teleport freely.
- `tp=off`: Players inside this area **cannot** teleport to other locations or use `/home`, unless they have `server` or `teleport_plus_admin` privileges.

**Admins** (users with `server` or `teleport_plus_admin` privileges) can always teleport from and to any location, regardless of area restrictions. **Admins can also teleport other players from tp=off areas**, overriding the individual player's restrictions.

### Privilege Management
When players are teleported **to** a location with `tp=off`, their teleport-related privileges (`home`, `tp`, `teleport`) are temporarily revoked to prevent them from leaving the area. These privileges are automatically restored when using `/tprestore` to return them to their previous location.

When **admins** teleport players **to** a location with `tp=on`, waypoints, or any unrestricted destination, the `home` privilege is automatically granted to ensure players can use `/home` in areas that allow teleportation.

- **Admins are exempt** from privilege revocation and can always teleport themselves and others from any area
- **Admin bypass** allows teleporting other players from tp=off areas regardless of individual restrictions
- **Home privilege is granted** when admins teleport users to `tp=on` locations, waypoints, or unrestricted destinations
- Players will be notified when privileges are revoked, granted, or restored
- Revoked privileges are stored and restored exactly as they were before

Example:
```
/setloc MyBase tp=off
```
This will prevent regular users inside `MyBase` from teleporting away or using `/home` while inside the area, and will revoke teleport privileges from users teleported to this location.

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

## Troubleshooting

### Areas Mod Integration Issues
If locations with `nobuild=on` are not creating protected areas:

1. Check server logs for Areas-related error messages
2. Ensure the Areas mod is properly installed and enabled
3. Try creating a location after server restart

### Teleport History Problems
If `/tprestore` doesn't work or gives unexpected results:

1. The mod automatically cleans up history on server startup
2. History is only stored when teleportation succeeds
3. **Original location preservation**: Once a player's original location is stored, it remains unchanged even after multiple teleports, allowing restoration to the very first position
4. **Persistent storage**: Teleport history is saved to mod storage and persists across server restarts
5. **Simplified safety system**: The mod uses basic safety checks (avoiding lava and solid blocks) while trusting the game engine to handle minor position adjustments

### Position Safety System
The teleportation system uses a simplified safety approach:

- **Basic safety only**: Prevents teleporting into lava or solid blocks
- **Ground detection**: Ensures solid ground exists within 10 blocks below
- **Game engine trust**: Lets Minetest handle minor position adjustments automatically
- **Fewer restrictions**: More locations are accessible without complex safety failures

### Privilege Management Issues
If privilege revocation/restoration isn't working properly:

- Admins are exempt from privilege revocation
- Privileges are restored automatically with `/tprestore`

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
