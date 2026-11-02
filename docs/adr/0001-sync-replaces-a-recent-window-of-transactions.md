# ADR 0001: The sync replaces a recent window of transactions

- Status: accepted
- Date: 2026-11-02

## Context

The sync job reads each account's transactions from Enable Banking a few times a day and must store them without
duplicates or gaps. The usual way is to match each transaction by an ID from the bank and insert only the new ones.

The spike (real data from both banks, 2 November 2026) showed that there is no ID we can trust:

- **Trade Republic** sends no ID at all: only amount, currency, credit/debit indicator, status and booking date.
- **Caja Rural de Navarra** sends `entry_reference`, but it is empty for the current day's transactions and is
  presumably filled in later, so the same transaction would look new the next day.
- A natural key (date, amount, direction, description) is not unique either: 13 of 320 Caja Rural transactions
  share it with another one (two equal card payments on the same day, for example).

Other facts from the spike: both banks return newest first, all transactions came as booked, and the amount's
sign is not consistent (Caja Rural sends every amount positive, Trade Republic sends debits negative), so the sign
must come from `credit_debit_indicator`.

## Decision

Each sync **replaces a recent window** of each account's transactions instead of merging them one by one:

1. The window starts `TransactionWindow.Overlap` (10 days) before the account's last successful sync. If the
   account has never been synced, there is no window: the full history is loaded (`strategy=longest`).
2. The sync reads every transaction from the start of the window, following `continuation_key`.
3. In one database transaction, it deletes the account's stored transactions booked on or after the start of the
   window and inserts the ones just read. If reading fails, nothing is deleted.

## Consequences

Good:

- No duplicates and no missed transactions, with the same code for both banks and no matching heuristics.
- Late changes from the bank inside the window (an `entry_reference` filled in, a pending transaction booked, a
  corrected description) are picked up for free.
- A failed or skipped sync is recovered by the next one.

Bad:

- Transactions inside the window get new IDs on every sync. The app must not keep transaction IDs across
  refreshes; this is stated in `docs/api.md`. Anything that needs a stable ID later (categories, notes) will need
  a different design.
- Each sync rewrites up to 10 days of rows. With a personal account that is a few dozen rows, which is negligible.
- Changes the bank makes to transactions older than the window (a correction three weeks later, for example) are
  never picked up. Banks rarely do that for booked transactions, and a reconnection reloads the full history.
- The window always reaches back past the last successful sync, so a sync that stops for days loses nothing, as
  long as the bank still gives that history: with background access, many banks give only the last 90 days.

## Alternatives considered

- **Match by bank ID**: rejected, there is no reliable ID (see Context).
- **Match by a computed fingerprint** (date, amount, direction, description, plus the position among equal ones):
  works for exact repeats, but breaks as soon as the bank changes a field or the order of equal transactions, and
  adds complexity to every sync.
- **Replace the full history on every sync**: simplest, but each bank gives the full history only right after
  linking (Trade Republic only 90 days), so older transactions would be lost.
