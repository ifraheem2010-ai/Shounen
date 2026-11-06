# Studio checks — the save system

`src/server/Services/DataService.luau` is the only file in the save path that no test
covers. That is deliberate: `src/server/` cannot be required under Lune, which is why all
the logic lives in `src/shared/Save/` instead. But it means the wiring itself — the real
ProfileStore, the real `Players` events, the real DataStore — has never been run.

This is the pass that runs it. About ten minutes.

---

## Setup

**1. Enable API services.** Studio cannot touch DataStores without it, and without it
every check below fails for the same uninteresting reason.

> Studio → **Game Settings** → **Security** → **Enable Studio Access to API Services** → on

This needs the place to be saved to Roblox at least once (**File → Publish to Roblox**).
A local-only `.rbxl` has no DataStore to talk to.

**2. Sync the project in.**

```bash
cd C:\Websites\shounen
export PATH="$HOME/.rokit/bin:$PATH"
rojo serve
```

Then in Studio: **Plugins → Rojo → Connect**.

**3. Open the Output window.** Everything below is read from it. `DataService` logs with a
`[DataService]` prefix and the bootstrap logs once with `[Bootstrap]`.

**4. Confirm the tree looks right** before pressing play:

- `ServerScriptService.Server.Bootstrap` — a **Script**
- `ServerScriptService.Server.Services.DataService` — a ModuleScript
- `ServerScriptService.Vendor.ProfileStore` — a ModuleScript, ~2275 lines
- `ReplicatedStorage.Shared.Save` — five modules

---

## The checks

Run them in order. Check 4 depends on check 3. Check 6 is independent of the rest but
needs the place published and a second device signed in to the same account.

### 1 — The server comes up

**Do:** press **Play** (F5).

**Expect:** `[Bootstrap] server up: DataService started` in Output, and **no warnings and
no red**. A clean first join logs nothing else at all — `DataService` only speaks when
something happened, so silence here is the pass.

**If it fails:** a `ProfileStore` require error means the `Vendor` branch did not sync;
re-check the tree above.

---

### 2 — A first-time profile is created, and it is yours

**Do:** with the game still running, open the **Command Bar** and run:

```lua
local p = require(game.ServerScriptService.Server.Services.DataService).get(game.Players:GetPlayers()[1])
print(p.ownerUserId, p.schemaVersion, p.money, #p.party, p.nextCreatureSerial)
```

**Expect:** your own UserId, then `1 0 0 1`.

**Why it matters:** `ownerUserId` must be your id and **never `0`**. Zero is the store
template's "never been saved" sentinel; a live profile still carrying it would mint
creature uids that collide with every other new player's.

---

### 3 — A change is held in the live profile

**Do:**

```lua
local DataService = require(game.ServerScriptService.Server.Services.DataService)
local p = DataService.get(game.Players:GetPlayers()[1])
p.money = 4242
p.flags.studioCheck = true
print("set:", p.money, p.flags.studioCheck)
```

**Expect:** `set: 4242 true`.

**Why it matters:** `get` returns the same table ProfileStore will save. If it returned a
copy, this would print correctly and then persist nothing — which is the failure mode that
looks fine right up until check 4.

---

### 4 — It persists across a rejoin

**Do:** **Stop** (Shift+F5). Wait about **five seconds** — `EndSession` is asynchronous, so
the final write happens after the call returns. Then **Play** again and run:

```lua
local p = require(game.ServerScriptService.Server.Services.DataService).get(game.Players:GetPlayers()[1])
print(p.money, p.flags.studioCheck, p.lastLoginUnix)
```

**Expect:** `4242 true` and a `lastLoginUnix` that is now, not the one from before.

**This is the check the whole save system exists for.** If `money` is `0`, the write never
landed — look for a `[DataService]` warning in the previous session's output, and check
that API services are still enabled.

**If you stopped too fast** and see `0`, that is not necessarily a bug: repeat with a
longer wait before concluding anything.

---

### 5 — A repair is applied and reported

**Do:** corrupt the live profile deliberately, then force a reload:

```lua
local DataService = require(game.ServerScriptService.Server.Services.DataService)
local player = game.Players:GetPlayers()[1]
local p = DataService.get(player)
p.money = -500
p.playtimeSeconds = -1
DataService.service:release(player.UserId)
```

Wait about five seconds, then:

```lua
local DataService = require(game.ServerScriptService.Server.Services.DataService)
local player = game.Players:GetPlayers()[1]
print(DataService.service:load(player.UserId).repaired)
print(DataService.get(player).money)
```

**Expect:** `2`, then `0`. And in Output, two `[DataService] profile <id>: repaired …`
lines naming `money` and `playtimeSeconds`.

**Why it matters:** repairs must be visible. A validator that silently clamps is a
validator nobody will ever debug.

---

### 6 — A second server cannot share the session

**Studio's "Clients and Servers" cannot test this.** It starts several *clients* against
**one** server process, and the extra players get placeholder UserIds — so the keys are
`Player_-1`, `Player_-2` and so on, which never collide. One server, different keys, no
contention. An earlier version of this document got that wrong.

A real test needs **two server processes on one key**, which means two places to be the
same account in at once.

**Do:**

1. **Publish the place** if you have changed anything since the last publish
   (**File → Publish to Roblox**). The live servers run the published build, not your
   local tree.
2. **Join the published place on your phone** (or any second device, or a browser) on
   **your own account**. Wait until you are properly in.
3. **Back in Studio, press Play.** Same account, same key — Studio's Play runs its own
   server simulation with your real UserId, so the two genuinely contend.
4. **Wait up to about 45 seconds.** This is the part that looks broken and is not; see
   the timing note below.

**Expect:**

- **Studio wins.** Its Output eventually shows a normal load, and
  `DataService.get(...)` returns a profile. The waiting server is the one that takes
  the session, so the *second* joiner wins and the *first* loses it.
- **The phone client is kicked**, with:
  `Your save was opened in another session, so this one can no longer save. Please rejoin.`

**Expect specifically NOT:** both sessions alive at once. Two live sessions on one key
means two servers writing the same profile, and whichever saves last silently wins.

#### Why the wait

ProfileStore does not refuse the second server. It queues a force-load, waits for the
holder to let go, and **steals the session after 40 seconds** —
`SESSION_STEAL = 40` in `vendor/ProfileStore.luau`. So:

| | |
|---|---|
| `SESSION_STEAL` | 40s — the waiting server takes over |
| `START_SESSION_TIMEOUT` | 120s — it gives up entirely |
| `ASSUME_DEAD` | 630s — a lock with no updates is treated as a crashed server |

`StartSessionAsync` **yields** for that whole period rather than returning nil, so for up
to 40 seconds the Studio player is in the game with no profile and Output says nothing.
That is expected. Do not conclude anything before 45 seconds.

#### What this check is really for

`onSessionLost` → kick is the only reason the phone client goes. Without it,
`SaveSession` drops the profile and logs a warning, and that player keeps playing with
nothing that will ever save — collecting creatures into a table no longer connected to a
save. That handler exists because writing this check exposed its absence.

If the phone client stays in the game after Studio loads the profile, the kick path is
broken even though the session locking worked. Both halves have to pass.

---

## Cleaning up after yourself

Check 3 wrote `money = 4242` and a `studioCheck` flag into your real profile. To clear it:

```lua
local DataService = require(game.ServerScriptService.Server.Services.DataService)
local p = DataService.get(game.Players:GetPlayers()[1])
p.money = 0
p.flags.studioCheck = nil
```

Then stop, wait five seconds, and rejoin to confirm it saved as `0`.

---

## If something fails

Report it with the Output text, which check number it was, and whether API services were
enabled. The three things most likely to be wrong, in order:

1. **API services off**, or the place never published — every DataStore call fails.
2. **Rojo not connected**, so Studio is running a stale tree. Check 1 catches this.
3. **Stopped too quickly** before the asynchronous save finished. Affects checks 4 and 5.

Check 6 needs 45 seconds before it means anything — ProfileStore steals a contended
session at 40. A real failure in check 4 or 6 is worth stopping for. Everything in `src/shared/Save/` has
tests, so a failure there points at the adapter or at the vendored module's behaviour
having changed — see `vendor/README.md` step 5.
