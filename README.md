# playervault

A virtual playervault for luanti

# commands

- `/pv` shows usage and your vault count
- `/pv <number>` opens your own vault
- `/pv <number> <player>` opens another player's vault (admin only)
- works for checking offline users

## Privileges

- `playervaults_admin`: can open/edit other players' vaults
- `server`: also accepted as admin access
- `playervault.amount.<number>`: grants access up to that vault count (highest amount wins)
