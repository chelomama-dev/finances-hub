# API contract

The HTTP contract between the backend (`src/FinancesHub.Api`) and the Flutter app (`mobile/`). It changes
**before** the API does, and the app uses only what it describes.

> **Status: confirmed by the Enable Banking spike, not implemented yet.** Every change is recorded in the
> [changelog](#changelog). Until an endpoint is implemented, the app uses its demo
> repositories (`--dart-define=DEMO=true`) with the examples below.

| Endpoint | Purpose | Implemented |
|---|---|---|
| `GET /api/summary` | Total balance and balance per bank | Yes |
| `GET /api/banks/{bankId}/accounts` | A bank's accounts and their balances | Yes |
| `GET /api/transactions` | Transactions of every account, filtered and paged | Yes |
| `GET /api/statistics` | Income, expenses and top expenses of a date range | Yes |
| `GET /api/connections` | Linked banks and consent status | Yes |
| `POST /api/connections` | Start linking a bank | Yes |
| `POST /api/connections/{connectionId}/renew` | Start reconnecting an expired or expiring bank | Yes |

## Conventions

- **Base URL**: local `http://localhost:5080` (`http://10.0.2.2:5080` from the Android emulator). All paths start
  with `/api`.
- **JSON** in camelCase. Fields marked *nullable* can be `null`; all other fields are always present.
- **IDs** are opaque strings. Banks use their code (`caja-rural-navarra`, `trade-republic`); everything else uses
  UUIDs. Don't parse them.
- **Transaction IDs are not stable**: the transactions of the last days are replaced on every sync
  ([ADR 0001](adr/0001-sync-replaces-a-recent-window-of-transactions.md)). Use them as list keys within one
  response, but never store them or link to them.
- **Money** is always an object with the amount as a **decimal string** with a dot, never a JSON number:
  `{ "amount": "-23.40", "currency": "EUR" }`. Negative amounts are expenses, positive ones are income.
- **Dates**: `bookingDate` is a date with no time (`"2026-11-01"`). Timestamps are UTC ISO 8601
  (`"2026-11-02T07:00:12Z"`).
- **Auth**: none in local development. In Azure, every request needs `Authorization: Bearer <token>`: a Microsoft
  Entra ID access token for the API, with the delegated scope `api://<API client id>/access_as_user`, signed in as
  the owner. Without a valid token the API answers `401`; with a valid token for someone else, `403`. The bank's
  callback and the health checks are the only anonymous endpoints.
- **Errors** use ProblemDetails (RFC 9457), `Content-Type: application/problem+json`:

  ```json
  {
    "type": "https://tools.ietf.org/html/rfc9110#section-15.5.5",
    "title": "Not Found",
    "status": 404,
    "detail": "Account 3f2c… was not found."
  }
  ```

  Validation errors (`400`) add an `errors` object: field name → list of messages. The app shows `detail` if it is
  there, otherwise a generic Spanish message.

## Endpoints

### Get the summary

`GET /api/summary`

The total balance across all banks and the balance of each bank. Data comes from the last sync, not live from the
banks.

```json
{
  "totalBalance": { "amount": "12873.45", "currency": "EUR" },
  "lastSyncedAt": "2026-11-02T07:00:12Z",
  "banks": [
    {
      "id": "caja-rural-navarra",
      "name": "Caja Rural de Navarra",
      "balance": { "amount": "3120.80", "currency": "EUR" },
      "connectionStatus": "active"
    },
    {
      "id": "trade-republic",
      "name": "Trade Republic",
      "balance": { "amount": "9752.65", "currency": "EUR" },
      "connectionStatus": "expiring"
    }
  ]
}
```

- `lastSyncedAt` *nullable*: `null` if no sync has run yet.
- `banks` is empty if no bank is linked yet; then `totalBalance.amount` is `"0.00"`.
- `lastSyncedAt` is the most recent sync of any account. A bank's `balance` is the sum of its accounts; it is
  `"0.00"` until its first sync.
- `connectionStatus`: see [connection status](#connection-status).
- All accounts are in EUR for now; the total only adds EUR balances.

### List a bank's accounts

`GET /api/banks/{bankId}/accounts`

```json
{
  "bank": {
    "id": "caja-rural-navarra",
    "name": "Caja Rural de Navarra"
  },
  "accounts": [
    {
      "id": "3f2c8d71-5a0b-4e9f-8c16-b7d2e4a90f55",
      "name": "Cuenta Corriente",
      "maskedIban": "ES12 **** 4567",
      "balance": { "amount": "3120.80", "currency": "EUR" }
    }
  ]
}
```

- `name` *nullable*: the bank may not send one; show the masked IBAN instead. Banks send the holder's name or
  their own product name here (`MI CUENTA`), as is.
- `maskedIban` *nullable*: some accounts have no IBAN.
- `404` if the bank doesn't exist. A known bank that isn't linked returns an empty `accounts` list.

### List transactions

`GET /api/transactions?from=2026-10-01&to=2026-11-02&direction=expense&limit=50&cursor=…`

The transactions of every account of every bank, together. Newest first by `bookingDate`; transactions of the same
day come in a stable order, so paging never repeats or skips one.

| Query | Required | Default | Notes |
|---|---|---|---|
| `from` | No | no lower limit | Date, inclusive |
| `to` | No | today | Date, inclusive |
| `direction` | No | both | `income` or `expense` |
| `limit` | No | `50` | 1 to 100 |
| `cursor` | No | first page | The `nextCursor` of the previous page. Keep the same filters when you send it |

```json
{
  "items": [
    {
      "id": "c81e5a0f-2d3b-4f6a-9e47-1a8b5c0d9e21",
      "bookingDate": "2026-11-01",
      "amount": { "amount": "-23.40", "currency": "EUR" },
      "description": "MERCADONA PAMPLONA",
      "counterparty": "Mercadona S.A.",
      "status": "booked",
      "bank": { "id": "caja-rural-navarra", "name": "Caja Rural de Navarra" }
    },
    {
      "id": "e4a7b2c9-6f1d-4a83-b5e0-3c9d8f2a1b76",
      "bookingDate": "2026-10-31",
      "amount": { "amount": "1650.00", "currency": "EUR" },
      "description": null,
      "counterparty": null,
      "status": "booked",
      "bank": { "id": "trade-republic", "name": "Trade Republic" }
    }
  ],
  "nextCursor": "eyJkIjoiMjAyNi0xMC0zMSIsImkiOjQyfQ"
}
```

- `description` and `counterparty` *nullable*: Trade Republic never sends them. Caja Rural always sends a
  description, and a counterparty only for transfers.
- `status`: `booked` or `pending`. Both banks have sent only `booked` so far, but the app must handle `pending`.
- `bank`: the bank of the transaction's account, with the same `id` and `name` as in the summary.
- `nextCursor` *nullable*: `null` on the last page.
- `400` if a query value is invalid (for example `from` after `to`).

### Get statistics

`GET /api/statistics?from=2026-10-07&to=2026-11-05`

What came in and went out in a date range, across every account: the totals, the descriptions with the most
expenses, and the totals of each day. Data comes from the last sync.

| Query | Required | Default | Notes |
|---|---|---|---|
| `from` | Yes | | Date, inclusive |
| `to` | No | today | Date, inclusive. At most 366 days after `from` |

```json
{
  "from": "2026-10-07",
  "to": "2026-11-05",
  "income": { "amount": "1650.00", "currency": "EUR" },
  "expenses": { "amount": "-812.30", "currency": "EUR" },
  "topExpenses": [
    { "description": "MERCADONA PAMPLONA", "amount": { "amount": "-212.75", "currency": "EUR" }, "count": 6 },
    { "description": "RECIBO LUZ", "amount": { "amount": "-61.32", "currency": "EUR" }, "count": 1 },
    { "description": null, "amount": { "amount": "-49.95", "currency": "EUR" }, "count": 5 }
  ],
  "otherExpenses": { "amount": "-488.28", "currency": "EUR" },
  "days": [
    {
      "date": "2026-10-31",
      "income": { "amount": "1650.00", "currency": "EUR" },
      "expenses": { "amount": "0.00", "currency": "EUR" }
    },
    {
      "date": "2026-11-01",
      "income": { "amount": "0.00", "currency": "EUR" },
      "expenses": { "amount": "-23.40", "currency": "EUR" }
    }
  ]
}
```

- Expenses are negative, as in transactions; income is positive. Pending transactions count too.
- `topExpenses`: up to 5 descriptions with the largest total expenses, largest first. Transactions are grouped by
  their exact `description`; those without one are grouped together with `description: null`. `count` is how many
  transactions the group has.
- `otherExpenses`: the expenses of every other description, so `topExpenses` plus `otherExpenses` add up to
  `expenses`. `"0.00"` when there are none.
- `days`: only the days with transactions, oldest first.
- Only EUR transactions count, like the summary's total.
- `400` if `from` is missing, after `to`, or more than 366 days before it.

### List connections

`GET /api/connections`

A connection is a bank linked through Enable Banking, with a consent that expires.

```json
{
  "items": [
    {
      "id": "a5d3f8e1-9b2c-4e7a-8f60-4c1b7d9e2a58",
      "bankId": "caja-rural-navarra",
      "bankName": "Caja Rural de Navarra",
      "status": "active",
      "expiresAt": "2027-04-28T21:58:00Z"
    }
  ]
}
```

#### Connection status

Consents last what each bank allows: 180 days for Caja Rural de Navarra, **90 days for Trade Republic**.

| Value | Meaning | What the app shows |
|---|---|---|
| `active` | Consent valid for more than 14 days | Nothing special |
| `expiring` | Consent expires in 14 days or less | A warning and "Reconectar" |
| `expired` | Consent expired or revoked; the data is no longer updated | An error and "Reconectar" |

### Link a bank

`POST /api/connections`

```json
{ "bank": "caja-rural-navarra" }
```

`bank` is a bank code: `caja-rural-navarra` or `trade-republic`; anything else is a `400` with
`errors.bank`. Response `200`:

```json
{ "authorizationUrl": "https://tilisy.enablebanking.com/welcome?sessionid=…" }
```

`POST /api/connections/{connectionId}/renew` has no body and returns the same response, to reconnect an existing
connection (`404` if it doesn't exist). Its accounts and their history stay.

The login URL must be opened within **30 minutes**; after that the callback fails with `reason=failed`.

The flow:

1. The app calls the endpoint and opens `authorizationUrl` in the **external browser** (`url_launcher`,
   `LaunchMode.externalApplication`), not in a WebView, because some banks block logins inside a WebView.
2. The user logs in to the bank and accepts the consent.
3. The bank sends the browser back to the API (`GET /api/connections/callback`), which completes the session, saves
   the accounts and loads their history. This part is backend only.
4. The API redirects the browser to the app's deep link:
   - `financeshub://connections/result?status=success&synced=true`. `synced=false` means the bank is linked but the
     first load of data failed; the scheduled sync will retry, so show it as linked with a note.
   - `financeshub://connections/result?status=error&reason=<code>`, where `reason` is `cancelled`, `denied` or
     `failed`.
5. The app handles the deep link (an Android intent filter for the `financeshub` scheme and a go_router route),
   shows the result and refreshes the connections and the summary.

The first load happens before the redirect, so when the app gets `synced=true` the data is already there. Only the
accounts in the backend's allowed list are saved, whatever the owner shares in the bank's consent screen.

## Changelog

- 2026-11-02: first draft.
- 2026-11-02: confirmed by the spike. Bank IDs are their codes instead of UUIDs; masked IBANs are shorter
  (`ES12 **** 4567`); transaction IDs are not stable; consent length per bank; which fields each bank sends.
- 2026-11-02: connections implemented. The callback path is `/api/connections/callback`, the result deep link
  carries `synced`, and the login URL is valid for 30 minutes.
- 2026-11-02: summary, accounts and transactions implemented. Same-day transactions come in a stable order rather
  than arrival order.
- 2026-11-02: auth in Azure: the `access_as_user` scope, and `403` for a valid token that isn't the owner's.
- 2026-11-05: `GET /api/transactions` lists the transactions of every account together, each with its `bank`. It
  replaces `GET /api/accounts/{accountId}/transactions`, which the app no longer uses.
- 2026-11-05: `GET /api/statistics`: income, expenses, top expenses by description and daily totals of a date
  range.
