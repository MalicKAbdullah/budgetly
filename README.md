<div align="center">

# 🧮 Budgetly

### Know where your money goes.

A private, offline-first budget tracker that follows cash **and** digital money — with per-category budgets, split expenses, and encrypted backups.

![License](https://img.shields.io/badge/License-MIT-2F9E44?style=flat-square)
![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-2F9E44?style=flat-square)
![Built with Flutter](https://img.shields.io/badge/Built%20with-Flutter-027DFD?style=flat-square&logo=flutter)
![Privacy](https://img.shields.io/badge/Data-Offline%20%26%20Encrypted-34D399?style=flat-square)
![Trackers](https://img.shields.io/badge/Trackers-0-34D399?style=flat-square)

</div>

> ### 🔒 Private by design
> Budgetly works **completely offline**. Every account, transaction, and budget is **encrypted on your device**. No account, no servers, no analytics — your finances never leave your phone.

Budgetly answers one question well: *where did my money go this month?* It tracks cash and digital together with an accounts model, so moving money around never looks like spending — and it handles the messy real-world cases (splitting a bill, getting paid back, recurring bills) that generic budget apps get wrong.

## ✨ Features

**Track cash and digital together**
- **Accounts** — cash, bank, wallet, card — each with a live balance.
- **Transfers** between your own accounts: an ATM withdrawal is `Bank → Cash`, so it moves money without ever counting as spending.
- Fast entry of expenses, income, and transfers.

**Budget with intent**
- **Categories with monthly budgets**, progress bars, and over-budget warnings.
- A **dashboard** showing spend vs income for the window you picked, total balance across accounts, and recent activity.

**Settle up with people — one bill, several people, both directions**
- **People registry.** Add, rename and remove the people you share bills with from the People screen. Names are typed — no contacts permission, nothing leaves the device. Renaming updates every transaction that names them. Somebody who still appears on a transaction can't be deleted; Budgetly tells you how many to clear first rather than quietly losing who owes what.
- **Split one expense with several people.** Enter the split total, then assign it: add people, type each share, or tap **Split evenly**. The running "still to assign" line has to reach zero, so a half-assigned bill is never saved. A split points one way only — either they owe you or you owe them.
- **Older transactions too.** Anything recorded before this version opens in the same editor, keeps its numbers exactly, and can have people added to it.

- **Split an expense with a person**, whichever way it went: *they owe me back* (you fronted the bill) or *I owe them* (someone else paid your share). Either way only **your share** counts as your spending, and the rest becomes a debt with that person's name on it. Names come from a simple free-text field with suggestions from people you have split with before — no contacts access, nothing leaves the app.
- **People / Settle up** shows each person's net position — "Ali owes you 1,200", "You owe Sara 300" — the transactions behind it, and a **Settle** action. A settlement clears that person's **oldest debt first**.
- **A settlement is never income and never spending.** Money that only passes through you — a friend paying you back, or you paying them back — moves real cash in and out of your account balance but is left out of Spent, Income, budgets, the category breakdown and the statement. Pay 1,000, mark 500 as owed to you, get the 500 back: Budgetly shows you spent **500** and are **500** poorer, not that you broke even.
- Lists never show a bare "−1,000" for a bill you only fronted. A split reads *Your share Rs 500 · you paid Rs 1,000 · Rs 500 owed by Ali*, so the full amount can never be mistaken for your own spending.

**One date filter, everywhere, remembered**
- A single window — **This month / Last 3 months / Last 6 months / This year / All time / Custom range** — shared by the dashboard, the activity list and the statement export. Pick it once on any screen and the others follow.
- **Custom range** opens a two-date calendar picker. Whatever you choose is remembered across launches, so the app reopens on the window you care about.
- **Tap a category, see the transactions.** Tapping a row in the dashboard's Top categories card opens Activity filtered to that category. Activity also has its own category picker, plus search, alongside the type and account filters — they all narrow together inside the selected date window, and a banner names whatever is hiding rows with one tap to clear it. "Uncategorized" is a filter of its own. The category filter is per-session: the date window is remembered across launches, the category deliberately is not.

**Automate the boring parts**
- **Recurring transactions** (salary, rent, subscriptions) post automatically, with catch-up on open.
- **Auto-capture from notifications (Android)** — with your opt-in "notification access", Budgetly reads bank/wallet transaction alerts (e.g. Meezan SMS) **on-device**, nudges you, and files them under **Captured transactions**. Tapping one opens a **review sheet** right over the list: the bank, amount, date, and direction come pre-filled from the alert, and every one of them stays editable — the **purpose/note** is always yours to write. Alerts the parser can't read still open the same sheet with the raw text and a blank amount, so there is always a way to add one. Nothing disappears: every captured alert stays in **History**, marked Added (with the transaction it became) or Dismissed, and a dismissed one can be added later with **Add anyway**.
- **A captured alert can be a transfer, not spending.** Reviewing one offers Expense / Income / **Transfer**. A transfer asks for From and To accounts and skips the category — an ATM withdrawal is `Bank → Cash`, so it never counts as spending and the cash isn't double-counted when you spend it later. Alerts mentioning "withdrawn", "withdrawal" or "ATM" open on Transfer already; you can always switch it back.

**Yours alone**
- **Fingerprint / device lock** — optionally require your fingerprint or device PIN to open the app (shared `core_lock`).
- **Encrypted backup & restore** to a folder or **Google Drive**, protected by a passphrase only you know.

## 🔒 Privacy & Security

- **Offline-only.** No network code beyond your own optional Drive-folder backup — nothing to leak.
- **Encrypted at rest.** The whole dataset is encrypted with **AES-256-GCM** under a random key held in the platform keystore.
- **Your backups, your key.** Backups are encrypted with a separate passphrase via **Argon2id** — restorable on any device.
- **On-device parsing.** Captured messages are read and parsed locally and never uploaded. Their text is kept in your capture history — inside the same encrypted store as everything else.
- **No accounts, no telemetry, no ads.**

## 📸 Screenshots

| Dashboard | Add transaction | Budgets | People / Settle up |
| :---: | :---: | :---: | :---: |
| _coming soon_ | _coming soon_ | _coming soon_ | _coming soon_ |

## 🚀 Getting Started

**Prerequisites:** [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel) and Android Studio / Xcode.

```sh
# 1. Clone
git clone https://github.com/MalicKAbdullah/budgetly.git
cd budgetly

# 2. Install dependencies (also fetches secure-suite-core)
flutter pub get

# 3. Run on a connected device or emulator
flutter run
```

**Build a release APK:**

```sh
flutter build apk --release
```

Run the checks the way CI does:

```sh
flutter analyze
flutter test
```

## 🧱 Built With

- **Flutter** & **Dart** — one codebase, Android & iOS
- **Riverpod** (state) · **go_router** (navigation) · **intl** (formatting)
- [**secure-suite-core**](https://github.com/MalicKAbdullah/secure-suite-core) — shared encryption, storage, backup & design system

## 📄 License

[MIT](LICENSE) © 2026 Abdullah Malik — part of the [Secure Suite](https://github.com/MalicKAbdullah/secure-suite-core).
