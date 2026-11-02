# Privacy policy

Last updated: 2 November 2026

Finances Hub is a personal, non-commercial app. Its only user is the author of this repository, who is also the
owner of the bank accounts it reads. It is not offered to anyone else.

## What data it processes

Through the [Enable Banking](https://enablebanking.com) API (PSD2 account information), and only for the accounts
the owner links:

- Account details: IBAN, account name, currency and product.
- Balances.
- Transactions: amount, currency, dates, description and counterparty, as far as each bank sends them.

The app is read-only: it never requests payments or moves money.

## What it is used for

Only to show the owner their own balances and transactions in one place. The data is not sold, shared with third
parties, used for advertising or used for profiling.

## Where it is stored and for how long

In a database in a Microsoft Azure region in the European Union, reachable only by the owner after signing in.
Secrets such as API keys are kept in Azure Key Vault. The data is kept while the owner uses the app, and deleted
when the owner stops using it.

## Consent and withdrawal

Access to each bank is granted through the bank's own consent screen, and lasts at most what the bank allows
(usually 180 days). Consent can be withdrawn at any time from the bank or by unlinking the account, after which no
more data is read.

## Contact

Questions about this policy: open an issue in
[github.com/chelomama-dev/finances-hub](https://github.com/chelomama-dev/finances-hub/issues).
