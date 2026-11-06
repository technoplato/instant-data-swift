# Held writes: what launch does to an existing outbox, and how an installed device recovers

A *held write* is an outbox mutation whose effect on the local cache this library cannot prove, moved aside at launch
so it stops nothing else. This guide says what happens to an existing outbox when an application upgrades, and how an
installed iPhone or iPad settles its held writes in place: no uninstall, no reinstall, no deleted data (#696, #134).

## Which writes are held

Every outbox row the runtime prepares carries a SQLite-owned preparation receipt: the record, written with the write's
local effect, of how to undo or replay that effect. Two kinds of row have none:

- a row an earlier library version wrote before durable optimistic-overlay metadata existed (before 1.2.0); retry,
  refresh and discard refuse it, because its local cache effect is unknown (`retainedUnknown`);
- a row from a version before SQLite-owned receipts (migration 0020), or one whose receipt the runtime revoked because
  its body no longer matched.

Up to 1.9.9 the first such row refused every live connection, so every later write waited unsent behind it, and the
only way out was a destructive reset of the whole store.

## What launch does to an existing outbox (since 1.9.10)

With the default `InstantRuntimeConfiguration.retainedMutationsWithoutPreparationReceipt = .quarantine`:

1. After the store's migrations, in one SQLite transaction, launch moves each such row whose effect is active, whole,
   into `instant_outbox_quarantined`: its body byte for byte, every column of its outbox row as one JSON object, the
   reason (`no-preparation-receipt`) and the time.
2. Every other write keeps its row, its receipt and its place, and the outbox drains in creation order as before.
3. A store with no such row is not written to, and never gains the table.
4. Nothing is deleted. The library never sends, changes or removes a held write on its own. A held write's lifecycle
   observers see it failed, not waiting forever.

`.blockSynchronization` keeps 1.9.9's wall, for an application that wants it.

## How an installed iPhone or iPad recovers

Run these steps in the installed application, on the device, with its store as it is. Do not uninstall or reinstall
the application, reset its local store, or delete rows by hand: a reset sets aside every unsent write along with the
held ones, and reinstalling does not reset this library's store.

1. **Install a build with this library at 1.9.79 or later and launch it, online.** Launch holds each write whose
   effect is unknown and synchronizes the rest. On a phone, keep the application in front until its pending count
   reaches zero: iOS suspends a background application within seconds, and each return reconnects and continues.
2. **List and export the held writes.** `quarantinedMutations(limit:)` lists them, oldest first;
   `quarantinedMutationCount()` counts them. Each `InstantQuarantinedMutation.outboxRowJSON` is the whole outbox row, for
   an export kept outside the device before anything is settled.
3. **Verify each one on the server.** `verifyQuarantinedMutation(id:)` reads the server's own rows for every entity the
   write set (one one-shot read each, the answers' own rows, not this device's view of them) and returns an
   `InstantQuarantinedMutationVerification`. It needs a connection; offline it says the server could not be read.
4. **Settle it on that evidence.**

   | Verdict | What it proves | What to do |
   | --- | --- | --- |
   | `.applied` | The server holds every value the write set, or a newer one a later write of this device, which the server accepted, set. | `completeQuarantinedMutation(id:)`: its observers see it accepted. |
   | `.notApplied(.refusedByServer)` | The server refused it with a client-error status, and its rows do not hold what it set. | `discardQuarantinedMutation(id:)`, or send it again if what it would set should be on the server (the server may refuse it again). |
   | `.notApplied(.neverSent)` | Its outbox row records no send: it never left the device. | `retryQuarantinedMutation(id:)` to deliver it, or `discardQuarantinedMutation(id:)` to drop it. |
   | `.cannotTell` | The server's rows cannot settle it: it was sent and the server holds another value (a later write may have replaced it), it has a deletion, retraction or lookup step, or the server could not be read. | Leave it held: it blocks nothing. Verify it again later, or send it again if its owner decides to. |

   `completeQuarantinedMutation(id:)` and `discardQuarantinedMutation(id:)` verify again before they write, and refuse
   any other verdict, so a stale verdict never settles a write. Each records the verification it acted on in
   `resolution_json`, beside the kept row; the body is never touched.
5. **A retained mutation still in the outbox** (an application on `.blockSynchronization`, or a row whose overlay is
   inactive and whose receipt is unknown) is held first, whole, when verification is asked for it.

Discarding does not roll this device's cache back by guesswork: the server's answers to the verification apply like any
server result, so the rows they cover show the server's values.

## What the library never does

- guess at a held write's effect on the local cache;
- call a write applied because a value differs or because this device shows it: a value that differs may be a later
  write over one that landed, and this device's view includes the held write's own leftover effect;
- delete a held write's body, or send one without being asked.

## Going back to an earlier version

A version before 1.9.10 does not read `instant_outbox_quarantined`: held writes stay there, untouched, and come back into
view when a later version launches. A version before 1.9.79 does not read `resolution_json`; it lists completed and
discarded rows as settled, because their `resolution` is set.
