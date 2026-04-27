# Codex Switcher

Codex Switcher is a native SwiftUI account manager for Codex on **macOS**, with synced companion apps for **iPhone** and **Apple Watch**.

The app turns Codex's single live `auth.json` login into a managed library of saved accounts. On the Mac it can capture a file-backed Codex auth snapshot, store it safely, restore another saved snapshot, track 5-hour and 7-day rate-limit headroom, and expose account switching through the main window, menu bar, Dock, widgets, controls, and App Intents.

> [!IMPORTANT]
> Codex Switcher switches accounts by rewriting a file-backed Codex `auth.json`. It intentionally refuses to switch a linked Codex folder that is configured for `keyring` or `auto` credential storage because those modes do not give the app an authoritative `auth.json` file to restore safely.

> [!IMPORTANT]
> Actual Codex account switching is a **macOS responsibility**. The iPhone and Apple Watch apps are companions for synced account management, rate-limit viewing/refresh, widgets, complications, and archive import/export. They do not directly rewrite a desktop Codex installation.

---

## Quick start

1. Open the **macOS** app.
2. In **Settings → Codex Folder**, select the `.codex` folder that Codex uses for `auth.json` and `config.toml`.
3. Make sure the linked Codex folder is file-backed. In `config.toml`, this means either no `cli_auth_credentials_store` setting or:

   ```toml
   cli_auth_credentials_store = "file"
   ```

4. Press **Add Account**.
   - If the linked folder currently contains a new or recoverable `auth.json`, Codex Switcher captures it.
   - Otherwise the app starts a browser sign-in flow and imports the resulting ChatGPT/Codex auth snapshot as a saved account.
5. Repeat for the accounts you want to keep.
6. Rename accounts, choose icons, pin favorites, and choose a sort order.
7. Use **Log In** from the main window, menu bar, Dock menu, widget, control, or Shortcuts/App Intents to restore a saved account.

When Codex is already running as a desktop app, Codex Switcher may show **“Account change pending. Restart Codex.”** after a switch. Restart Codex so it reloads the replaced `auth.json`.

---

## Platform roles

| Platform | Role | What it can do |
| --- | --- | --- |
| macOS | Authoritative switcher | Link a Codex folder, read/write `auth.json`, capture accounts, switch accounts, run Autopilot, expose menu bar/Dock/widgets/controls/App Intents. |
| iPhone | Synced companion | Browse and manage synced accounts, import/export `.cxa` archives, refresh rate limits, show Home/Lock Screen widgets, use Home Screen quick actions. |
| Apple Watch | Lightweight companion | Browse, search, rename, choose icons, remove accounts, refresh rate limits, and show complications. |

The shared data model is designed so the companion apps stay useful even when a full secret snapshot has not arrived on that device yet. In that case, the UI can still show account metadata while export, live-refresh, or Mac extension-switching surfaces report that a local snapshot is missing.

---

## What the app does

### Account library

- Saves Codex accounts as named records with icons.
- Supports ChatGPT-backed auth, ChatGPT token payloads, and API-key auth payloads.
- Searches by account name, email hint, or account identifier.
- Sorts by **Name**, **Date Added**, **Last Login**, **Rate Limit**, or **Custom** order.
- Keeps pinned accounts above unpinned accounts while preserving each lane's custom order.
- Supports up to **1000** saved accounts.
- Marks invalidated accounts as **Unavailable** instead of silently using a stale refresh token.

### Adding accounts

The macOS **Add Account** action has two paths:

1. **Capture current `auth.json`** — if the linked Codex folder contains a valid, new, or recoverable file-backed account, the app saves that snapshot.
2. **Browser sign-in import** — if there is no usable current snapshot, or the current snapshot is already saved, the app opens an OpenAI/Codex browser sign-in flow. The OAuth callback is handled on a local loopback server, then the app builds a file-backed `auth.json`-style snapshot and imports it.

The browser sign-in path is useful when Codex is logged out, when the linked folder is missing `auth.json`, or when you want to add an account without first manually switching Codex to it. After importing through browser sign-in, select the saved account and choose **Log In** to write it to the linked Codex folder.

### Switching accounts

Switching restores the selected account's saved snapshot into the linked Codex folder as `auth.json`.

The switch code is defensive:

- It only runs when the linked folder is reachable and file-backed.
- It loads the saved snapshot from Keychain.
- It normalizes legacy ChatGPT token payloads into the current Codex runtime shape before restore.
- It writes through coordinated file operations.
- It uses an atomic replacement helper and applies restrictive `0600` permissions.
- It immediately reads the file back and verifies the identity key.
- It preserves the account you are switching away from when that live snapshot maps to a saved account.
- Shared extension switching uses an App Group process lock so widgets/controls do not race each other.

### “None” account

When **Show “None” Account** is enabled, the Mac list includes a local logout row. Choosing it deletes the linked `auth.json` instead of writing another account. It is useful for intentionally leaving Codex logged out.

### Account details

Account detail views on macOS, iPhone, and Apple Watch show account metadata, last login, availability, and stored 5-hour/7-day rate-limit information. On Mac and iPhone, detail views can also export or share a `.cxa` account archive when the full snapshot is available locally.

---

## Auth support

Codex Switcher parses these `auth.json` auth modes:

- `apiKey`
- `chatgpt`
- `chatgptAuthTokens`

The linked folder's `config.toml` credential-store hint controls whether switching is allowed:

| `cli_auth_credentials_store` value | Switching support |
| --- | --- |
| `file` | Supported. |
| missing / unknown | Allowed as potentially file-backed. |
| `keyring` | Unsupported. |
| `auto` | Unsupported. |

API-key accounts can be captured, named, exported, imported, and restored. They cannot fetch live ChatGPT usage/rate-limit data because the live rate-limit request requires ChatGPT access-token credentials.

### Unavailable accounts

A saved account can become unavailable when its refresh token is revoked, expired, reused, mismatched, missing, or when the saved snapshot is corrupted. The app then zeros the cached rate-limit display, marks the account unavailable, and prevents accidental switching.

To recover, add/sign in to that account again. Avoid using Codex's own **Log out** button for accounts you want Codex Switcher to preserve, because that can invalidate the refresh token backing the saved snapshot.

---

## Rate limits

Codex Switcher tracks the remaining **5-hour** and **7-day** Codex windows.

Rate-limit refresh uses multiple sources:

- **Remote live refresh** for ChatGPT-backed accounts with a synced access token.
- **macOS session-log fallback** for the currently active account when live refresh is unavailable but recent Codex session telemetry exists in the linked folder.
- **Local reset normalization** so stored values return to `100%` when a known reset time has passed.

Stored rate-limit values carry a data status:

| Status | Meaning |
| --- | --- |
| `exact` | Fresh live or directly observed value. |
| `cached` | Previously known value that is being kept until a better one arrives. |
| `missing` | No useful value is known yet. |
| `unavailable` | The account cannot currently provide rate-limit data, often because credentials are invalid. |

The best-account ranking used by rate-limit sort, Autopilot, and “Switch to Best” requires both 5-hour and 7-day values. It prioritizes the account with the strongest worst-window headroom, then the strongest remaining window.

---

## Autopilot and automation

macOS settings include three automation toggles:

| Setting | Behavior |
| --- | --- |
| **Automatically Add Accounts** | Watches the linked `auth.json`; when Codex changes to a new file-backed account, the app captures it automatically. |
| **Automatically Remove Accounts** | Removes accounts that become authoritatively unavailable. |
| **Automatically Switch Accounts** | Runs Autopilot in the background and switches to the account with the most remaining 5-hour/7-day headroom. |

Autopilot refreshes accounts before ranking them, prefers accounts with local snapshots, ignores unavailable accounts, and does not switch when the active account is already the best candidate. It also reacts to launch, app focus, system wake, and quiet periods after Codex session activity. Periodic unattended timers are skipped while the Mac is sleeping or screens are sleeping; Low Power Mode or critically low battery pauses only the periodic timer path, not explicit user/system triggers.

---

## Notifications

macOS, iPhone, and Apple Watch share rate-limit reset notification preferences. The Mac also has account-switch notifications.

Available notification preferences:

- **Account Switch** on macOS.
- **5-Hour Limit Reset**.
- **7-Day Limit Reset**.

Reset notifications are scheduled only for accounts with exact known reset dates, are prioritized for the current account and pinned accounts, and are capped so the app does not flood Notification Center with stale requests.

---

## Widgets, controls, complications, and shortcuts

### macOS widgets and controls

- **Current Account** widget — shows the account currently active in the linked Codex folder and important setup/error states.
- **Saved Account** widget — shows one configured saved account and can switch to it.
- **Rate Limits** widget — shows selected or automatically chosen accounts with 5-hour/7-day headroom.
- **Open Codex Switcher** control — opens the app.
- **Switch Codex Account** control — shows which configured account is active and switches when turned on.

### iPhone widgets and quick actions

- **Rate Limits** Home Screen widget.
- **Rate Limit** Lock Screen accessory widget.
- Home Screen quick actions for the first accounts in the app's current sort order.
- Background App Refresh for rotating batches of rate-limit refresh work.

### Apple Watch complications

- **Rate Limit** complication.
- **Open Codex Switcher** complication.

### App Intents and Shortcuts

The Mac app owns intents that need app-owned mutations, security-scoped folder access, or durable command results. Shared/widget intents use the App Group state snapshot.

Implemented intents include:

- Open Codex Switcher.
- Add Current Codex Account.
- Get Selected Codex Account.
- Get Current Codex Account.
- Get Current / Account / Best Codex Rate Limits.
- Get All Codex Accounts.
- Get Best Codex Account.
- Find Codex Account / Find Codex Accounts.
- Switch Codex Account.
- Switch to Best Codex Account.
- Remove Codex Account.
- Quit Codex Switcher.
- Toggle notifications, menu bar visibility, Launch at Login, and automatic switching settings.

The app also contains conditional Spotlight indexing support for accounts when built with the `CODEX_ACCOUNT_SPOTLIGHT` flag.

---

## Sync, storage, and security model

Codex Switcher separates metadata from secrets.

### Synced metadata

Account rows are stored with SwiftData and CloudKit in the private iCloud container:

```text
iCloud.com.marcel2215.codexswitcher
```

The synced metadata includes account name, icon, identity key, auth mode, email/account hints, ordering, pinned state, last login, availability, and cached rate-limit display fields. Full `auth.json` snapshots are migrated out of the SwiftData/CloudKit model and kept in Keychain instead.

### Secret snapshots

Full auth snapshots are stored in Keychain under the shared access group configured by the project:

```text
$(AppIdentifierPrefix)group.com.marcel2215.codexswitcher
```

The snapshot store keeps:

- a device-local shared Keychain copy for fast local access, and
- a synchronizable iCloud Keychain copy when available.

Reads prefer the local shared copy, then fall back to the synchronizable copy, and repair missing copies when possible. A separate local availability file records whether this device currently has a usable snapshot for an account.

### Rate-limit credentials

For live rate-limit refresh, the app stores a narrow synchronizable Keychain payload containing only the identity key, auth mode, optional ChatGPT account ID, access token, and export timestamp. It deliberately does not duplicate the full `auth.json` just to refresh widgets or companion devices.

### App Group shared state

Widgets, controls, and intents read a portable JSON snapshot from the App Group:

```text
group.com.marcel2215.codexswitcher
```

Important App Group files include:

| File | Purpose |
| --- | --- |
| `SharedCodexState.json` | Current account, auth state, and display-safe account records for extensions. |
| `LocalSnapshotAvailability.json` | Per-device snapshot availability. |
| `LinkedCodexFolderShared.bookmark` | Shared bookmark for the linked Codex folder. |
| `PendingCodexAppCommands.json` | Durable command queue for app-owned work requested by intents/extensions. |
| `PendingCodexAppCommandResults.json` | Results for intents waiting on app-owned mutations. |
| `PendingCodexAccountOpenRequest.json` | Requests to open the app to a specific account. |
| `CodexAccountSwitch.lock` | Cross-process lock used during shared switching. |

Shared JSON files are written atomically with sorted keys, and corrupt shared files are quarantined rather than reused.

### Account archives

`.cxa` files are portable account archives. Current archives use a compressed binary property-list container with the exported UTI:

```text
com.marcel2215.codexswitcher.account-archive-binary
```

The app can still import legacy `.cxa` archives with the older UTI:

```text
com.marcel2215.codexswitcher.account-archive
```

Archives may contain one or many accounts. Each archived account can include metadata, icon, identity information, cached rate limits, a synced rate-limit credential, and the full auth snapshot.

> [!CAUTION]
> `.cxa` archives contain secret auth material when export succeeds. The archive format is compressed/opaque, not encrypted. Treat exported archives like credentials.

---

## macOS UI and behavior

The macOS app includes:

- Main account list with search, pinning, custom icons, drag reordering, and sort controls.
- Account detail windows with metadata, rate limits, export/share, pin/unpin, and removal actions.
- Menu bar extra with current account, quick switching, account info, add account, open app, and quit.
- Dock menu with up to five immediately switchable accounts in the current app sort order.
- Launch at Login support.
- Single-instance coordination that asks older app instances to quit when a newer instance launches.
- Settings sections for Codex folder, general preferences, Autopilot, menu bar, notifications, support links, and destructive reset/remove-all actions.

Keyboard/menu highlights:

- `⌘N` — Add Account.
- `⌘O` — Import `.cxa` archive.
- `⌘C` / `⌘V` — Copy/paste account archives.
- `⌘R` — Refresh.
- `⌘I` — Get Info.
- `⌘L` — Log In to selected account.
- `⌘P` — Pin/unpin selected account.
- `Delete` — Remove selected account.
- `⌘Q` — hide to menu bar when the menu bar extra/background residency is enabled; otherwise quit.
- `⌥⌘Q` — quit when the primary quit action hides to menu bar.

---

## iPhone app behavior

The iPhone app is a companion account browser and rate-limit surface.

It supports:

- Synced account list and detail views.
- Search, sort, custom ordering, pinning, rename, icon selection, and removal.
- `.cxa` import from Files/share flows and export from account detail views when a snapshot exists locally.
- Cached and live rate-limit display.
- Background App Refresh with rotating batches of tracked accounts.
- Home Screen quick actions based on the current app sort order.
- Reset notification settings and support links.

If an account exists in CloudKit but its snapshot has not arrived through iCloud Keychain, the iPhone UI can still show the account but export/live refresh may be unavailable until Keychain sync completes.

---

## Apple Watch behavior

The Apple Watch app focuses on small-screen account management:

- Synced account list.
- Search and sort.
- Account detail views with rate limits and last-login metadata.
- Rename, icon selection, and removal.
- Pull/foreground refresh of rate limits.
- Settings with version and remove-all action.
- Complications for one-account rate-limit display and app launching.

Watch copy explicitly distinguishes between accounts waiting for iCloud Keychain sync and API-key accounts, where live rate-limit refresh is not available.

---

## Build from source

### Requirements

The checked-in Xcode project currently declares:

| Setting | Value |
| --- | --- |
| Swift | 6.0 |
| macOS deployment target | 26.0 for app/widget targets; one macOS test configuration also declares 26.4. |
| iOS deployment target | 26.0 |
| watchOS deployment target | 26.0 |
| Marketing version | 1.0 |
| Build number | 1 |

Use an Xcode version that includes the SDKs needed by those deployment targets.

### Schemes and targets

Shared schemes are checked in under `CodexSwitcher.xcodeproj/xcshareddata/xcschemes`:

| Scheme / target | Purpose |
| --- | --- |
| `CodexSwitcherMacApp` | macOS app, product name “Codex Switcher”. |
| `CodexSwitcher` | iPhone app. |
| `CodexSwitcherWatchApp` | Apple Watch app. |
| `CodexSwitcherMacWidgets` | macOS widgets and controls. |
| `CodexSwitcherWidgets` | iPhone widgets. |
| `CodexSwitcherWatchWidgets` | watchOS widgets/complications. |
| `CodexSwitcherMacTests`, `CodexSwitcherMacUITests` | macOS tests. |
| `CodexSwitcherTests`, `CodexSwitcherUITests` | iPhone tests. |
| `CodexSwitcherWatchTests`, `CodexSwitcherWatchUITests` | watchOS tests. |

### Signing and capabilities

The repository is configured for the original bundle IDs and Team ID. A fork or local build usually needs updated signing across every app, widget, watch, test, App Group, Keychain, and iCloud entitlement.

Current identifiers in the project include:

| Capability / ID | Current value |
| --- | --- |
| Main app bundle ID | `com.marcel2215.codexswitcher` |
| Watch app bundle ID | `com.marcel2215.codexswitcher.watchkitapp` |
| App Group | `group.com.marcel2215.codexswitcher` |
| CloudKit container | `iCloud.com.marcel2215.codexswitcher` |
| Keychain access group | `$(AppIdentifierPrefix)group.com.marcel2215.codexswitcher` |
| Widget extension bundle IDs | `com.marcel2215.codexswitcher.widgets`, `com.marcel2215.codexswitcher.watchkitapp.widgets` |

macOS app entitlements include sandboxing, user-selected read/write file access, app-scoped security bookmarks, App Group access, CloudKit/iCloud document support, network client/server access for the local OAuth callback, and shared Keychain access.

### Local build steps

1. Open `CodexSwitcher.xcodeproj` in Xcode.
2. Select your development team for every app, widget, watch, and test target.
3. Update bundle IDs, App Group, iCloud container, and Keychain access group if you are not building with the original identifiers.
4. Build and run `CodexSwitcherMacApp` first.
5. Link the `.codex` folder in macOS Settings.
6. Build/run the iPhone and watch apps after the Mac app is working and iCloud/Keychain capabilities are configured.

---

## Repository structure

```text
CodexSwitcher.xcodeproj/        Xcode project and shared schemes
CodexSwitcherApp/               iPhone app plus shared cross-platform models, stores, intents, widgets support, and services
CodexSwitcherMacApp/            macOS app, controllers, views, file access, OAuth sign-in, menu bar/Dock behavior
CodexSwitcherWatchApp/          Apple Watch app views and bootstrap
CodexSwitcherWidgets/           iPhone WidgetKit extension
CodexSwitcherMacWidgets/        macOS widgets and control widgets
CodexSwitcherWatchWidgets/      watchOS complications/widgets
CodexSwitcherTests/             iPhone/shared unit tests
CodexSwitcherMacTests/          macOS unit tests
CodexSwitcherWatchTests/        watchOS unit tests
CodexSwitcherUITests/           iPhone UI tests
CodexSwitcherMacUITests/        macOS UI tests
CodexSwitcherWatchUITests/      watchOS UI tests
```

---

## Test coverage highlights

The test suite covers the main behaviors that make the app safer than a raw file replacer, including:

- `auth.json` parsing for ChatGPT and API-key payloads.
- Stable identity-key derivation.
- Account capture, duplicate prevention, recovery of unavailable accounts, and browser-login import behavior.
- Safe switching, skipped rewrites, legacy OAuth snapshot normalization, and “None” account deletion.
- Automatic add/remove/switch behavior.
- Rate-limit refresh, backoff, unauthorized handling, background refresh batches, and notification scheduling.
- Cloud/Keychain migration and local snapshot availability repair.
- `.cxa` archive round trips, multi-account archives, compressed container encoding, legacy archive import, filenames, and synced rate-limit credential export.
- Shared app command queues, pending account-open requests, widget/control switch behavior, Dock menus, menu bar state, and single-instance coordination.
- Basic UI launch and state tests for macOS, iPhone, and watchOS.

Run the appropriate Xcode test schemes for the platform you are changing.

---

## Troubleshooting

### “Link Codex Folder”

The Mac app does not have a linked folder yet. Choose the `.codex` folder that contains Codex's `auth.json` and `config.toml`.

### “No auth.json”

Codex may be logged out, using a different `CODEX_HOME`, or using non-file credential storage. Add Account can still open the browser sign-in flow, but switching the linked folder requires a file-backed setup.

### “Unsupported Credential Store”

The linked folder's `config.toml` advertises `keyring` or `auto`. Change Codex to file-backed credential storage if you want Codex Switcher to restore saved snapshots into that folder.

### “Permission Needed” or “Codex Folder Missing”

The security-scoped bookmark is stale, the folder moved, or the app lost access. Re-select the Codex folder in Settings.

### “Invalid auth.json”

The linked file is not valid UTF-8 JSON or does not contain a supported Codex auth payload. Fix Codex's auth file or use Add Account's browser sign-in flow.

### Account is unavailable

The saved refresh token or snapshot is no longer usable. Remove the account or sign in/add it again to replace the snapshot.

### Widgets show setup or stale states

Widgets read `SharedCodexState.json` from the App Group. Open the Mac app, refresh, and confirm the linked folder and shared App Group/Keychain capabilities are valid.

### iPhone or Watch cannot export an account

The account metadata may have synced through CloudKit before the full snapshot arrived through iCloud Keychain. Leave iCloud Keychain enabled and allow sync to complete, or export from a Mac that has the local snapshot.

### API-key account has no live rate limits

API-key accounts can be switched, but live ChatGPT usage refresh needs a ChatGPT access token. The UI may show cached/missing rate-limit data for API-key accounts.

### Autopilot is not switching

Check that:

- Automatically Switch Accounts is enabled.
- The Mac app can access the linked folder.
- The linked folder is file-backed.
- Candidate accounts have local snapshots on this Mac.
- Candidate accounts are not unavailable.
- Both 5-hour and 7-day rate-limit values are known for ranking.
- The current account is not already the best candidate.

### Account change pending

If Codex was running during a switch, restart Codex so it reloads `auth.json`.

---

## Support links

The app exposes these support links in Settings:

- Website: `https://codexswitcher.marcel2215.com`
- Source code: `https://github.com/marcel2215/codex-switcher-app`
- Contact: `marcel2215@icloud.com`
- Terms of Service: `https://codexswitcher.marcel2215.com/terms-of-service`
- Privacy Policy: `https://codexswitcher.marcel2215.com/privacy-policy`

---

## Practical summary

Codex Switcher is a multi-platform SwiftUI app that safely manages file-backed Codex `auth.json` identities on macOS, syncs a usable account library across Apple devices, tracks rate-limit headroom, and exposes the system through widgets, controls, watch complications, notifications, and App Intents.

Use it when you want fast, verified switching between saved Codex accounts. Avoid using it as a switcher for Codex setups that rely on `keyring` or `auto` credential stores, because the app is intentionally built around safe control of file-backed `auth.json`.
