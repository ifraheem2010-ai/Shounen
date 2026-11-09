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

**4. Know how to reach the server context.** This catches everyone once. During Play, the
Command Bar runs on the **client**, where `ServerScriptService` does not exist — every
snippet below will fail with a nil index until you switch.

Studio exposes this two different ways depending on version. Check the **Explorer panel's
header** — it reads `Explorer / Client` or `Explorer / Server`, and that is the one place
that always tells you the truth.

> **If there are `Client` and `Server` tabs** above the viewport (current Studio): click
> the **`Server`** tab.
>
> **If there is a `Current: Client` button** on the **Test** tab (older layout): click it
> to toggle to Server.

Confirmed working when the Explorer header says `Explorer / Server`. Switch back to Client
if you want to poke at anything client-side. Each snippet below prints its own diagnosis
rather than throwing, so a nil error means you are still on the client.

**5. Confirm the tree looks right** before pressing play:

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

**Do:** with the game running and the Command Bar in the **Server** context, paste this.
It is deliberately one line: the Command Bar is a single-line input, and a multi-line
paste runs only the first line.

```lua
local DS = require(game:GetService("ServerScriptService").Server.Services.DataService); local pl = game:GetService("Players"):GetPlayers()[1]; if not pl then warn("CHECK 2 - no player on this server. Are you in the Server context, and is the game running?"); return end; local p = DS.get(pl); if not p then warn("CHECK 2 - no profile for " .. pl.Name .. ". The load may still be running, or it failed - look for a [DataService] line above."); return end; print(string.format("owner=%s  you=%s  schemaVersion=%s  money=%s  party=%s  serial=%s", tostring(p.ownerUserId), tostring(pl.UserId), tostring(p.schemaVersion), tostring(p.money), tostring(#p.party), tostring(p.nextCreatureSerial))); local idOk = p.ownerUserId == pl.UserId and p.ownerUserId ~= 0; local verOk = p.schemaVersion == 1; print(if idOk and verOk then "CHECK 2 PASS" else `CHECK 2 FAIL -{if idOk then "" else " ownerUserId is not yours"}{if verOk then "" else " schemaVersion is not 1"}`); print(if p.money == 0 and #p.party == 0 and p.nextCreatureSerial == 1 then "   fresh profile, as expected on a first run" else "   not a fresh profile - fine if you have run check 3 before")
```

**Expect:**

```
owner=<your UserId>  you=<your UserId>  schemaVersion=1  money=0  party=0  serial=1
CHECK 2 PASS
   fresh profile, as expected on a first run
```

**Why it matters.** `ownerUserId` must be your own id and **never `0`**. Zero is the store
template's "never been saved" sentinel; a live profile still carrying it would mint
creature uids that collide with every other new player's. The snippet asserts that rather
than leaving you to eyeball it.

The last line is informational, not a failure. `money=0 party=0 serial=1` only holds on a
genuinely first-time profile, so it will say "not a fresh profile" once you have run
check 3 — which is correct, not a problem.

**If it warns instead:** "no player on this server" means you are still in the Client
context, or the game is not running. "no profile" means the load is still going or it
failed — scroll up for a `[DataService]` line.

### 3 — A change is held in the live profile

**Do:** Server context, one line:

```lua
local DS = require(game:GetService("ServerScriptService").Server.Services.DataService); local pl = game:GetService("Players"):GetPlayers()[1]; local p = pl and DS.get(pl); if not p then warn("CHECK 3 - no profile. Are you in the Server context, and is the game running?"); return end; p.money = 4242; p.flags.studioCheck = true; print(string.format("CHECK 3 set  money=%s  flag=%s", tostring(p.money), tostring(p.flags.studioCheck))); print(if p.money == 4242 and p.flags.studioCheck == true then "   held in the live profile - now Stop, wait 5s, and Play again for check 4" else "CHECK 3 FAIL - the write did not stick in memory, which should be impossible")
```

**Expect:** `CHECK 3 set  money=4242  flag=true`, then the "held in the live profile" line.

**Why it matters:** `get` returns the same table ProfileStore will save. If it returned a
copy this would print correctly and persist nothing — the failure mode that looks fine
right up until check 4.

---

### 4 — It persists across a rejoin

**Do:** **Stop** (Shift+F5). **Wait about five seconds** — `EndSession` is asynchronous, so
the final write happens after the call returns. Then **Play** again, switch back to the
**Server** context, and run:

```lua
local DS = require(game:GetService("ServerScriptService").Server.Services.DataService); local pl = game:GetService("Players"):GetPlayers()[1]; local p = pl and DS.get(pl); if not p then warn("CHECK 4 - no profile yet. Give the load a moment and run this again."); return end; print(string.format("money=%s  flag=%s  lastLoginUnix=%s  (now is %s)", tostring(p.money), tostring(p.flags.studioCheck), tostring(p.lastLoginUnix), tostring(os.time()))); print(if p.money == 4242 and p.flags.studioCheck == true then "CHECK 4 PASS - the write survived a full rejoin" else "CHECK 4 FAIL - check 3's write never reached the DataStore. Did you wait ~5s after Stop? Is Studio API access still enabled?")
```

**Expect:** `CHECK 4 PASS`, and a `lastLoginUnix` close to the `now` printed beside it
rather than the earlier one.

**This is the check the whole save system exists for.** On `CHECK 4 FAIL`, look for a
`[DataService]` warning in the previous session's Output and confirm API services are
still enabled.

**If you stopped too fast,** a fail is not conclusive. Retry with a longer wait before
believing it.

---

### 5 — A repair is applied and reported

**Do:** first corrupt the live profile and release it:

```lua
local DS = require(game:GetService("ServerScriptService").Server.Services.DataService); local pl = game:GetService("Players"):GetPlayers()[1]; local p = pl and DS.get(pl); if not p then warn("CHECK 5a - no profile. Server context?"); return end; p.money = -500; p.playtimeSeconds = -1; DS.service:release(pl.UserId); print("CHECK 5a - corrupted money and playtime, then released the session. Wait ~5s, then run 5b.")
```

**Wait about five seconds** for the release to finish, then:

```lua
local DS = require(game:GetService("ServerScriptService").Server.Services.DataService); local pl = game:GetService("Players"):GetPlayers()[1]; if not pl then warn("CHECK 5b - no player on this server."); return end; local r = DS.service:load(pl.UserId); if not r.ok then warn("CHECK 5b - the load was refused: " .. tostring(r.reason) .. " - " .. tostring(r.detail) .. " (if this says lock-unavailable, 5a's release has not finished; wait and retry)"); return end; local p = DS.get(pl); print(string.format("repaired=%s  money=%s  playtimeSeconds=%s", tostring(r.repaired), tostring(p.money), tostring(p.playtimeSeconds))); print(if r.repaired == 2 and p.money == 0 and p.playtimeSeconds == 0 then "CHECK 5 PASS - both repairs applied, and both reported" else "CHECK 5 FAIL - expected 2 repairs clamping money and playtimeSeconds to 0")
```

**Expect:** `repaired=2  money=0  playtimeSeconds=0` and `CHECK 5 PASS`, plus two
`[DataService] profile <id>: repaired …` lines in Output naming `money` and
`playtimeSeconds`.

**If 5b says `lock-unavailable`,** 5a's release had not finished. Wait and run 5b again —
that is the asynchronous `EndSession` again, not a failure.

**Why it matters:** repairs must be visible. A validator that silently clamps is one
nobody will ever debug.

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
local DS = require(game:GetService("ServerScriptService").Server.Services.DataService); local pl = game:GetService("Players"):GetPlayers()[1]; local p = pl and DS.get(pl); if not p then warn("cleanup - no profile."); return end; p.money = 0; p.flags.studioCheck = nil; print("cleanup - money reset to 0 and studioCheck cleared. Stop, wait 5s, rejoin to confirm it saved.")
```

Then Stop, wait five seconds, and rejoin to confirm it saved as `0`.

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
