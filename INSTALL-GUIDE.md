# Silent Wallet — Install & Use Guide

Silent Wallet is an expense manager that keeps everything **on your phone only**.
It has no internet permission, no account, no ads and no cloud. Nothing you enter is ever uploaded.

## 1. Install (Android)

1. Copy the APK file you were given to your phone (WhatsApp, USB cable, Bluetooth, etc.).
   Pick the file that matches your phone. If unsure, use the `arm64-v8a` one — it fits almost every phone made since 2017.
2. Open the file from your **Files** / **Downloads** app and tap **Install**.
3. If Android says *"For your security, your phone isn't allowed to install unknown apps from this source"*:
   tap **Settings**, switch on **Allow from this source**, go back, and tap **Install** again.
   (You can switch that setting off again afterwards.)
4. If **Google Play Protect** says *"App blocked"* or *"Unknown developer"*:
   tap **More details → Install anyway**. This warning appears for any app that isn't from the Play Store.
   Silent Wallet can't connect to the internet, so it has no way to send anything out.

**Updating:** install the newer APK over the old one. Your data is kept, as long as the new APK came from the same person who gave you the first one.

## 2. First start

- Choose whether to **lock the app** with your fingerprint/face/phone PIN (needs a screen lock set in Android settings).
- Keep the **weekly backup reminder** switched on.

## 3. Using it

| To do this | Go to |
|---|---|
| Add an expense, income or transfer | **Add** button (attach a receipt photo if you like) |
| See where money went | **Reports** tab |
| Add a bank / cash / UPI account | **Manage** tab → Accounts → **Add** |
| Copy an entry (same amount, account, category, note) | Tap the entry, then the copy button next to the bin at the top; change anything you like and **Save** |
| Add a longer comment to an entry | The **comment** box on the **Add** page, below the note |
| Type an amount or do a quick sum | The keypad on the **Add** page: tap the calculator key for + − × ÷, then **Done** to go to the note |
| Find a past transaction | The search icon on **Transactions**: search notes, categories, accounts or amounts, and use **Filters** for time period, account, category and amount range |
| Choose which account new entries start on | **Manage** tab → Accounts → **Edit** → tap an account → **Default account** |
| Make or change your own categories | **Manage** tab → Categories (**Add** a new one, or **Edit** to rename, recolour or delete) |
| Make an entry repeat (rent, subscriptions, salary) | The repeat button 🔁 next to the receipt button on the **Add** page |
| Automatically record rent, subscriptions, salary | **More → Recurring expenses** |
| Get a daily reminder to add entries | **More → Daily reminder** (on by default at 8:00 pm; skipped if you already added an entry that day; you can change the time or turn it off) |

## 4. ⚠ Back up regularly — this is important

Because nothing is stored online, **if you lose, reset or break your phone and you have no backup file, your data is gone for good.**

1. Go to **More → Backup & restore → Save encrypted backup to device**.
2. Choose a **backup password** and write it down somewhere safe. It cannot be recovered or reset.
3. Copy the `.swbak` file to a safe place (another device, your computer, your own cloud storage). It is encrypted, so it is useless without the password.

**To restore** on a new phone: install Silent Wallet, then **More → Backup & restore → Restore from backup file**, choose the `.swbak` file and enter the password. Restoring **replaces** everything currently in the app.

The app reminds you once a week. Uninstalling the app or clearing its data also deletes everything, so export a backup first.

## 5. Privacy facts

- No internet permission — Android itself blocks the app from using the network.
- The database and receipt photos are encrypted (AES-256). The key lives in your phone's secure keystore and never leaves it.
- Screenshots, screen recording and the recent-apps preview are blocked inside the app by default. To take a screenshot, turn on **More → Allow screenshots**, and turn it off again afterwards.
- The CSV export is **not** encrypted — treat that file carefully.
