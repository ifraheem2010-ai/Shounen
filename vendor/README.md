# vendor/

Third-party code, pinned to an exact upstream commit. Nothing in here is ours, and
nothing in here gets edited.

## What is here

| | |
|---|---|
| `ProfileStore.luau` | ProfileStore by loleris (MAD STUDIO) |
| `LICENSE` | Apache License 2.0, the upstream licence |

**Source:** <https://github.com/MadStudioRoblox/ProfileStore>
**Pinned commit:** `45c9847cbcf1fc260369c50eb335aba7c35aecdd` (2025-07-31)
**Upstream `sha256`:** `ad43737203688b8e88cab34ebe8c483000c157e53bfb41e35f1b49ee89d0c95f`

The upstream repository publishes no tags and no releases, so the pin is the commit
that was the default branch tip when this was vendored. There is no version number to
quote because upstream does not issue one.

## Why vendored instead of a Wally dependency

ProfileStore is **not on the Wally index under any official scope**. Every package
there named `profilestore` is a third-party fork — `b1ntran`, `aspecky`, `ddashdev`,
`vyon`, `goset33` and others.

This is the one module in the project whose failure is permanent. A bug anywhere else
is a bad battle; a bug here is somebody's save. Depending on an unreviewed fork from an
account with no reputation, pinned by a version string its owner can move, is a
supply-chain decision rather than a dependency choice. Pinned in-tree it can be read,
diffed and audited.

The full argument, and the options that were rejected, is in `docs/DECISIONS_P2.md`
**P13**.

## Proving the file has not been tampered with

The only change made to `ProfileStore.luau` is a 33-line provenance comment at the top.
Everything after it is byte-for-byte upstream. To prove that:

```bash
tail -n +34 vendor/ProfileStore.luau | sha256sum
```

That must print `ad43737203688b8e88cab34ebe8c483000c157e53bfb41e35f1b49ee89d0c95f`. To
check it against upstream rather than against this file's own claim:

```bash
curl -sS "https://raw.githubusercontent.com/MadStudioRoblox/ProfileStore/45c9847cbcf1fc260369c50eb335aba7c35aecdd/ProfileStore.luau" | sha256sum
```

## Why it is excluded from the repo's checks

The file is `--!nonstrict`, uses upstream's formatting, and is 2242 lines of someone
else's code. Running our checks over it would produce noise we would then be tempted to
fix, and every fix makes the next upstream diff less readable.

| check | how it is excluded |
|---|---|
| Absolute Rule 3 (`--!strict` scan) | `tests/battle/Purity.spec.luau` scans `src`, `tests` and `.lune`. `vendor/` is none of them, and a test asserts it stays that way. |
| `luau-lsp analyze` | CI analyses `src` only. |
| StyLua | `.styluaignore` at the repo root. |
| strict language mode | `vendor/.luaurc` sets `nonstrict` and turns lints off, overriding the root `.luaurc`. |

This is the one directory in the repo where "do not apply our standards" is correct.
It is also the only directory where a file may be nonstrict.

## Updating it

1. Pick the new upstream commit and record its sha.
2. Download that exact commit's `ProfileStore.luau` to a scratch directory.
3. Read the diff against `tail -n +34 vendor/ProfileStore.luau` before replacing
   anything. This module holds player saves; an upstream change to the session-locking
   or save path is worth understanding rather than skimming.
4. Replace the body, keep the header, update the commit, date and `sha256` in **both**
   the header and this file.
5. Re-check the adapter. `src/server/Services/DataService.luau` depends on three
   specific upstream behaviours, each noted in its comments: `StartSessionAsync` throws
   rather than returning nil when the key is already live on this server, `params` is
   `{Steal: boolean?}` with no cancel callback, and `EndSession` is asynchronous.
6. Add a decision-log entry if anything about the adapter had to change.

## Licence obligations

Apache 2.0. The licence is retained in full in `LICENSE`, upstream's attribution is
retained in the file's own header, and the one modification — the provenance comment —
is stated in that comment. Keep all three if this file moves.
