<div align="center">

# 🧮 Tally

### Know where your money goes.

A private, offline-first budget tracker that follows cash **and** digital money — with per-category budgets, split expenses, and encrypted backups.

![License](https://img.shields.io/badge/License-MIT-2F9E44?style=flat-square)
![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-2F9E44?style=flat-square)
![Built with Flutter](https://img.shields.io/badge/Built%20with-Flutter-027DFD?style=flat-square&logo=flutter)
![Privacy](https://img.shields.io/badge/Data-Offline%20%26%20Encrypted-34D399?style=flat-square)
![Trackers](https://img.shields.io/badge/Trackers-0-34D399?style=flat-square)

</div>

> ### 🔒 Private by design
> Tally works **completely offline**. Every account, transaction, and budget is **encrypted on your device**. No account, no servers, no analytics — your finances never leave your phone.

Tally answers one question well: *where did my money go this month?* It tracks cash and digital together with an accounts model, so moving money around never looks like spending — and it handles the messy real-world cases (splitting a bill, getting paid back, recurring bills) that generic budget apps get wrong.

## ✨ Features

**Track cash and digital together**
- **Accounts** — cash, bank, wallet, card — each with a live balance.
- **Transfers** between your own accounts: an ATM withdrawal is `Bank → Cash`, so it moves money without ever counting as spending.
- Fast entry of expenses, income, and transfers.

**Budget with intent**
- **Categories with monthly budgets**, progress bars, and over-budget warnings.
- A **dashboard** showing this month's spend vs income, total balance across accounts, and recent activity.

**Settle up with friends**
- **Split / reimbursable expenses** — mark the part friends will pay back. Only *your share* counts as spending; the rest becomes a receivable.
- An **"Owed to you"** view; record a repayment and it clears the receivable **without** being counted as income — even when you paid cash and were paid back digitally.

**Automate the boring parts**
- **Recurring transactions** (salary, rent, subscriptions) post automatically, with catch-up on open.
- **Auto-capture from notifications (Android)** — with your opt-in "notification access", Tally reads bank/wallet transaction alerts (e.g. Meezan SMS) **on-device**, nudges you, and drops them into a review inbox to confirm in one tap. You can also paste a message manually — the same on-device parser handles both.

**Yours alone**
- **Fingerprint / device lock** — optionally require your fingerprint or device PIN to open the app (shared `core_lock`).
- **Encrypted backup & restore** to a folder or **Google Drive**, protected by a passphrase only you know.

## 🔒 Privacy & Security

- **Offline-only.** No network code beyond your own optional Drive-folder backup — nothing to leak.
- **Encrypted at rest.** The whole dataset is encrypted with **AES-256-GCM** under a random key held in the platform keystore.
- **Your backups, your key.** Backups are encrypted with a separate passphrase via **Argon2id** — restorable on any device.
- **On-device parsing.** Imported messages are read and parsed locally; the raw text is never stored or uploaded.
- **No accounts, no telemetry, no ads.**

## 📸 Screenshots

| Dashboard | Add transaction | Budgets | Owed to you |
| :---: | :---: | :---: | :---: |
| _coming soon_ | _coming soon_ | _coming soon_ | _coming soon_ |

## 🚀 Getting Started

**Prerequisites:** [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel) and Android Studio / Xcode.

```sh
# 1. Clone
git clone https://github.com/MalicKAbdullah/tally.git
cd tally

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
