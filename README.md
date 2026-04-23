# Codex Switcher

Codex Switcher is an open-source native SwiftUI developer utility for **macOS**, **iPhone**, and **Apple Watch** that turns Codex's single live login into a **managed library of named accounts**.

At its core, Codex Switcher captures, stores, syncs, and restores Codex's file-backed `auth.json`. Around that core it adds account naming, icons, pinned ordering, iCloud sync, rate-limit tracking, widgets, complications, notifications, menu bar access, App Intents, Shortcuts support, portable account archives, and automatic background switching on macOS.

It is distributed as a direct download from **GitHub Releases**, can be **purchased from the App Store**, and can also be built from source.

> [!IMPORTANT]
> Codex Switcher only supports **file-backed Codex authentication**. If the linked Codex folder is configured to use credential storage modes such as `keyring` or `auto`, the app intentionally refuses to switch accounts because there is no authoritative `auth.json` to rewrite safely.

> [!IMPORTANT]
> **Actual account switching happens on macOS.**  
> The iPhone app is the mobile companion that adds synced management UI, live rate-limit refresh, widgets, and `.cxa` archive import/export. The Apple Watch app focuses on synced account browsing, quick management, live refresh, and complications. Neither companion app directly rewrites a desktop Codex installation.

---

## Download and installation

You can use Codex Switcher in three ways:

- **[GitHub Releases](https://github.com/marcel2215/codex-switcher-app/releases)** — install the latest direct build from the repository's Releases page
- **App Store** — purchase the signed App Store build
- **Build from source** — open the Xcode project and run your own signed build

The macOS app is the version that links a real Codex folder and performs account capture/switching.  
The iPhone and Apple Watch apps are companions and make the most sense once you also have the macOS app in your setup.

## Recommended first-run workflow

1. Install and launch the **macOS** app.
2. Open **Settings** and link the folder that Codex actually uses for `auth.json` and `config.toml`.
3. Make sure Codex is using a **file-backed** credential store rather than `keyring` or `auto`.
4. Log into Codex normally, then capture the current account with **Add Account**.
5. Repeat that capture flow for every account you want in your library.
6. Rename accounts, choose icons, pin favorites, and set your preferred sort order.
7. Enable **iCloud** and **iCloud Keychain** if you want account metadata, rate-limit credentials, and exportability to propagate to iPhone/Apple Watch.
8. Optionally enable **Automatic Switching**, widgets, menu bar access, App Shortcuts, and reset notifications.

---

## What Codex Switcher does

Codex itself normally has one active identity at a time: whatever is currently represented by the `auth.json` in the linked Codex directory. Codex Switcher turns that into a repeatable workflow:

1. Link the Codex folder once.
2. Capture the currently active `auth.json` as a saved account.
3. Give it a human-readable name and icon.
4. Repeat for every account you care about.
5. Switch back and forth instantly by restoring the saved snapshot that belongs to the target account.

From there, the app adds quality-of-life features that make a multi-account setup usable in practice:

- a searchable account library
- pinned accounts and custom ordering
- desktop and mobile widgets
- watch complications
- current-account and selected-account automation
- background rate-limit refresh
- notifications for reset windows
- one-tap menu bar switching
- portable `.cxa` archive import/export
- iCloud-backed metadata sync
- iCloud Keychain-backed secret propagation
- automatic switching to the account with the most remaining headroom

Codex Switcher is not a replacement for Codex. It is a **native account-management layer around Codex's auth state**.

---

## High-level feature set

### Core switching
- Capture the currently active Codex account directly from `auth.json`
- Restore any previously captured account back into the linked Codex folder
- Verify every write with an immediate readback identity check
- Preserve the currently live account when switching away from it, so a switch does not destroy the account you are leaving behind

### Account library
- Human-readable names
- Custom SF Symbol account icons
- Pin / unpin
- Search by name, email hint, or account identifier
- Sorting by **Name**, **Date Added**, **Last Login**, **Rate Limit**, or **Custom**
- Stable custom ordering with drag reordering
- Support for up to **1000 saved accounts**

### Rate limits
- Track remaining **5-hour** and **7-day** Codex windows
- Remote live refresh for ChatGPT-backed accounts using minimal synced credentials
- Session-log fallback on macOS for the current account when the live endpoint is unavailable
- `exact`, `cached`, and `missing` data states
- Local reset-boundary normalization so values snap back to `100%` once a reset time passes

### Sync and portability
- CloudKit-backed SwiftData account metadata sync
- Synchronizable Keychain propagation for account snapshots
- Synchronizable Keychain propagation for minimal rate-limit credentials
- Portable compressed `.cxa` account archives
- Import from Files, drag-and-drop, `onOpenURL`, or Finder/Files sharing flows

### macOS-specific
- Main window account manager
- Menu bar extra
- Dock menu of switchable accounts
- Launch at Login
- Automatic background switching ("Autopilot")
- Background/headless handling of app-owned mutation intents
- Desktop widgets and control widgets

### iPhone-specific
- Synced companion account browser
- Live refresh of rate limits
- Home Screen quick actions
- Lock Screen widgets
- Background App Refresh integration
- `.cxa` sharing and import in the Files / share sheet model

### Apple Watch-specific
- Synced companion account browser
- Pull-to-refresh rate limits
- Watch complications
- On-watch account rename / icon management / removal

### Automation
- App Shortcuts and App Intents for switching, querying, opening, and removing accounts
- Intent-based setting toggles
- Spotlight indexing of accounts when that build configuration is enabled
- Widget / control integration that works through the app's shared state model

---

## Platform model

### macOS
macOS is the **authoritative switching environment**.

This is the only platform that can:
- link a real Codex folder on disk
- read and write the linked `auth.json`
- hold the security-scoped bookmark to that folder
- actually change which account Codex is using

It is also the richest surface, with the main window, menu bar extra, desktop widgets, controls, launch-at-login behavior, Dock menu integration, and automatic switching.

### iPhone
iPhone is a **synced companion**. It receives account metadata through CloudKit, receives secrets through iCloud Keychain when available, refreshes rate limits using the minimal synced credential payload, supports widgets and lock screen accessories, and can import/export account archives.

It does **not** link a Mac filesystem location or directly switch the Codex installation on your Mac.

### Apple Watch
Apple Watch is an even lighter **synced companion**. It shows the same saved account library, allows rename/icon/remove operations on synced accounts, refreshes rate limits, and powers watch complications.

It also depends on sync rather than direct Codex filesystem access.

---

## Supported and unsupported Codex auth setups

Codex Switcher recognizes these auth modes when parsing `auth.json`:

- `apiKey`
- `chatgpt`
- `chatgptAuthTokens`

### Supported
- Standard file-backed `auth.json` workflows
- Capturing and restoring API-key accounts
- Capturing and restoring ChatGPT-backed accounts
- Rate-limit refresh for ChatGPT-backed accounts that expose an access token

### Partially supported
- API-key accounts can be captured, stored, named, exported, and switched on macOS, but **live usage API rate-limit refresh is unavailable** for them because that path requires ChatGPT credentials

### Unsupported for switching
If the linked Codex folder advertises one of these credential-store hints in `config.toml`:

```toml
cli_auth_credentials_store = "keyring"
cli_auth_credentials_store = "auto"
```

Codex Switcher refuses to switch accounts. The app only supports file-backed switching because the safe source of truth is `auth.json`.

If the hint is:
- `file`: supported
- `unknown`: treated as potentially file-backed and allowed
- `keyring`: unsupported
- `auto`: unsupported

The credential-store hint is discovered by reading `config.toml` and extracting the scalar `cli_auth_credentials_store` value. Codex Switcher deliberately does not need a full TOML parser for this.

---

## Mental model and terminology

### Linked Codex folder
The directory you choose in macOS that contains Codex's configuration, including `auth.json` and usually `config.toml`.

### Current account
The account Codex is actively using right now, meaning the identity represented by the live `auth.json` in the linked folder.

### Selected account
The account currently highlighted in an app UI list. This matters because App Intents and widgets can expose "selected" as a separate concept from "current".

### Account snapshot
A preserved copy of the full `auth.json` contents for one saved account. This is what gets restored when you switch.

### Identity key
A stable semantic identifier derived from the account payload. It is not the local database UUID. It is used so sync, widgets, and automation survive cross-device duplication and reconciliation.

### Local snapshot
A full `auth.json` snapshot that is available on the current device. A device may know about an account through CloudKit metadata before the full secret payload reaches it through iCloud Keychain.

### Synced rate-limit credential
A deliberately minimal credential payload containing only the fields needed for live usage API reads. This is narrower than a full account snapshot.

### Metric status
Each rate-limit value is tagged as:
- `exact`: freshly known
- `cached`: old but still displayable
- `missing`: unavailable

---

## How account identity is derived

Codex Switcher does not trust a local database UUID to represent account identity, because UUIDs are device-local and do not solve cross-device matching. Instead, it derives a **stable identity key** from the auth payload.

For ChatGPT-backed accounts, the app tries to build a stable identity from combinations of:

- workspace ID
- account ID
- user ID
- subject claim
- email claim

Those normalized components are concatenated and hashed with SHA-256, producing a key like:

```text
chatgpt:<sha256>
```

If that is not possible but an email is available, the identity falls back to:

```text
email:<lowercased email>
```

For API-key accounts, the fallback is a SHA-256 hash of the key:

```text
api-key:<sha256>
```

This identity key is what binds together:
- SwiftData account metadata
- Keychain snapshots
- synced rate-limit credentials
- widget entities
- intent entities
- archive import reconciliation
- deletion cleanup
- current/selected account signaling

That design is why account records remain coherent across devices and after sync merges.

---

## How switching works

The switch pipeline is intentionally conservative.

### 1. Link the Codex folder
On macOS, the user chooses the Codex folder once. The app stores:

- an **app-scoped security-scoped bookmark** in local defaults
- a **shared implicit bookmark** in the App Group container for widgets / extensions / intents

### 2. Capture the current account
When you click **Add Account**, Codex Switcher:

1. reads the live `auth.json`
2. parses it
3. derives a stable identity key
4. extracts display hints such as email and account identifier
5. creates or updates a `StoredAccount`
6. stores the full snapshot in Keychain
7. publishes shared state for widgets / intents / companions
8. triggers rate-limit refresh
9. optionally exports the minimal synced rate-limit credential if the account supports it

If the account already exists, the app updates the stored snapshot instead of creating a duplicate.

### 3. Restore a saved account
When switching to a saved account, Codex Switcher:

1. loads the stored snapshot from Keychain
2. reads the current live `auth.json`
3. preserves the currently live account snapshot if it maps to a known saved identity
4. writes the target snapshot back to the linked `auth.json`
5. immediately reads the file back
6. reparses the file and confirms the resulting identity matches the target
7. marks the target as current
8. updates last-login and rate-limit state
9. republishes the shared widget / intent snapshot
10. posts switch feedback for other running surfaces

### 4. Enforce exclusive switching
Cross-process switching is protected by an App Group lock file using `flock`, so the main app and extension-driven switching surfaces do not race each other.

### 5. Keep file permissions restrictive
After a successful write, the app attempts to reapply restrictive `0600` permissions to `auth.json`, matching Codex's expectation that the file remain private.

---

## macOS application walkthrough

## Main window

The main macOS window is the full management console.

### Toolbar
The toolbar exposes:
- **Add Account**
- **Sort**

### Search
The window is searchable by:
- account name
- email hint
- account identifier

### Empty states
The app shows two distinct empty states:
- **No Accounts** when there are no saved entries
- **No Results** when a search query filters everything out

### Auth status banner
When the linked Codex state needs attention, an inline banner appears. This is the main recovery surface for:

- unlinked folder
- missing permission
- missing folder
- corrupt `auth.json`
- unsupported credential store

The banner includes:
- a title
- an explanatory message
- a **Link** or **Relink** button
- a **Refresh** button when a folder had previously been linked

### Account list behavior
Each row shows:
- icon
- name
- metadata summary
- current-account checkmark when applicable

Row interactions include:
- click selection
- double-activation / primary action to switch
- inline rename
- context menu actions
- drag-to-export
- custom-order drag reordering in Custom sort mode

### Keyboard shortcuts and key handling
The macOS app has unusually complete keyboard handling for a utility app.

Supported actions include:

- `⌘N` — Add Account
- `⌘I` — Import archive
- `Delete` — Remove selected account(s)
- `⌘R` — Refresh
- `⌘P` — Pin / Unpin selected account
- `⌘L` — Log in to selected account
- `Return` — Rename selected account
- `Space` — Switch to selected account
- Move commands — change selection up/down in the list

The delete handler intentionally only recognizes narrow modifier combinations so text editing behavior remains sane during rename.

### Context menus
When nothing is selected:
- Add Account
- Import Archive

When one account is selected:
- Log In
- Pin / Unpin
- Rename
- Choose Icon
- Remove

When multiple accounts are selected:
- Remove

### Sorting
The macOS app supports these sort criteria:

- Name
- Date Added
- Last Login
- Rate Limit
- Custom

For every mode except **Custom**, direction can be:
- Ascending
- Descending

Custom sort is always normalized to ascending order and becomes editable only when the list is not filtered by search.

### Pinned behavior
Pinned accounts are always kept above unpinned accounts.  
In custom ordering, pinned and unpinned accounts behave like two preserved lanes: manual reordering persists within each lane while maintaining the global invariant that pinned rows stay above unpinned rows.

### Rate-limit sort semantics
Rate-limit sorting is not a naive single-field sort. It prefers:

1. accounts with complete metrics over accounts with incomplete metrics
2. the **smaller** remaining window as the primary comparison
3. the **larger** remaining window as the secondary comparison

This is important because an account with `95%` 7-day remaining but `3%` 5-hour remaining is not actually a good candidate for active work.

### Finder drag export
Rows can be dragged out of the app as portable `.cxa` archives.

If a full local snapshot is available, the drag exports a real archive file.  
If it is not available, the same gesture can still carry an internal reorder token for in-app movement, but no external archive file is promised.

---

## Menu bar extra

The menu bar extra turns Codex Switcher into a background utility.

### Header
The menu bar header shows:
- app title
- current account name when known
- a logged-out message if the linked folder exists but `auth.json` is missing

### Header actions
It also exposes:
- **Add Account**
- **Open App**
- **Quit**

### Status card
If linking or auth recovery is required, the menu bar surface shows the same auth-state messaging and offers a relink action.

### Account list
The menu bar account list:
- is scrollable
- caps the visible height to roughly **five rows**
- shows the same icon / name / metadata summary model as the main app
- lets you switch directly from the menu bar
- visually marks the current account

### Quit behavior and background residency
When **Show in Menu Bar** is enabled, the primary quit command becomes **Hide to Menu Bar** rather than full termination.  
An explicit **Quit Codex Switcher** action is still available.

When the menu bar extra is disabled but automatic switching is enabled, the app restores a normal foreground presentation so the app remains reachable while background Autopilot continues to run.

---

## Dock menu

On macOS, right-clicking the Dock icon exposes a Dock menu of switchable accounts.

The menu:
- shows up to **five** accounts
- marks the current account
- includes the account icon
- lets you switch directly from the Dock

This is intentionally lightweight and mirrors the quick-access behavior of the menu bar extra.

---

## macOS settings

The settings window is broken into clear sections, and each preference matters.

## Codex Folder
- **Path** — displays the currently linked folder path
- **Link / Relink button** — opens a folder picker and updates the security-scoped bookmark

This is the single most important configuration point on macOS. Without it, switching is impossible.

## General
- **Launch at Login** — registers the app with `SMAppService.mainApp`
- **Automatic Switching** — enables background Autopilot

When launch-at-login requires user approval, the settings UI tells you to finish the approval in:

```text
System Settings > General > Login Items
```

The footer also explains the purpose of Automatic Switching: keep the app in the background and move to the account with the most remaining headroom.

## Menu Bar
- **Show in Menu Bar**
- **Icon**

Available menu bar icon choices are:
- Switch
- Key Card
- Key
- Person Badge Key
- Person
- Briefcase
- House
- Terminal
- Shield
- Lock
- Star
- Heart
- Bolt
- Globe
- Cloud
- Bell
- Bookmark

If Show in Menu Bar is off, the icon picker is disabled.

## Notification settings
- **Account Switch**
- **5-Hour Limit Reset**
- **7-Day Limit Reset**

Notification preferences are stored in the shared App Group defaults so:
- the main app
- app intents
- widgets
- companion logic

all read the same values.

The app requests authorization only when needed, and it re-registers for the `.providesAppNotificationSettings` option so the system can expose an in-app notification settings entry point.

## About section
- Version (includes build number)

## Action links
- Contact Us
- Visit Our Website
- Terms of Service
- Privacy Policy
- Source Code
- Notification Settings

## Danger Zone actions
- **Reset Settings**
- **Remove All Accounts**

Reset Settings restores the app's own stored preferences, including:
- notification toggles
- automatic switching toggle
- menu bar visibility
- menu bar icon
- local sort preferences

Remove All Accounts deletes every account record from the device and from CloudKit sync.

---

## iPhone application walkthrough

The iPhone app is intentionally designed as a sync-first companion.

## iPhone root account browser
The root screen uses a native SwiftUI navigation model:
- compact layout uses a `NavigationStack`
- regular-width layout uses a `NavigationSplitView`

### Root features
- searchable account list
- sort menu
- Settings button
- editable multi-select delete flow
- swipe-to-delete
- context menu pin/remove
- custom-order reordering when Custom sort is active and search is empty

### Empty state
When there are no synced accounts, the app explains the intended workflow:

> Accounts captured in Codex Switcher on your Mac appear here through iCloud.

That sentence is effectively the product model for iPhone.

### Sorting on iPhone
The iPhone app uses `CloudSortPreferences`, which sync sort criterion and direction through:
- local `UserDefaults`
- `NSUbiquitousKeyValueStore`

That means iPhone and Apple Watch can stay in sync about list ordering even though macOS keeps its own local preference store.

### Edit mode
In editing mode, the app uses explicit checkbox-style row selection so multi-delete and reorder behavior remain reliable and predictable.

## iPhone account detail screen
Each account detail screen includes:

### Account section
- Name editor
- Icon picker
- Last Login

### Rate Limits section
- 5-Hour Remaining
- 5-Hour Reset
- 7-Day Remaining
- 7-Day Reset

The reset rows can toggle between:
- relative time
- absolute timestamp

### Toolbar actions
- Share `.cxa` archive, if export is currently possible on this device
- Pin / Unpin in the overflow menu

### Danger Zone
- Remove Account

### Archive sharing behavior
If the account is not yet exportable on the iPhone, the detail view explains why instead of pretending the archive is available. The common reason is that metadata has synced but the full snapshot has not yet arrived via iCloud Keychain.

## iPhone settings
The iPhone settings surface is intentionally smaller than macOS settings.

### Notifications
- 5-Hour Limit Reset
- 7-Day Limit Reset

There is no separate iPhone account-switch notification toggle because iPhone does not directly perform desktop auth switching.

### About
- Version (includes build number)

### Actions
- Contact Us
- Visit Our Website
- Terms of Service
- Privacy Policy
- Source Code
- More Settings (deep link to iOS Settings)

### Danger Zone
- Reset Settings
- Remove All Accounts

Reset Settings on iPhone only resets the iPhone's settings surface values.  
Remove All Accounts deletes all local/iCloud-synced account records reachable from this device.

## Home Screen quick actions
The iPhone app can publish up to **four** Home Screen quick actions based on the current account ordering. Tapping one opens directly to that account's detail view.

## Background App Refresh
The iPhone app registers a background refresh task and reuses the same rate-limit refresh engine used in the foreground, with a background-specific policy.

Key behavior:
- earliest requested begin interval is **15 minutes**
- only one freshest pending refresh request is kept scheduled
- the background refresh publishes a fresh widget snapshot after updating tracked accounts

## iPhone widget families
The iPhone widget target focuses on rate-limit visibility.

Available widget families:
- systemSmall
- systemMedium
- systemLarge
- accessoryCircular
- accessoryRectangular

These are covered in detail later in the widget section.

---

## Apple Watch application walkthrough

The watch app mirrors the iPhone companion model, but with a simpler UI suited to short interactions.

## Apple Watch root account browser
The watch root screen provides:
- searchable account list
- Sort button
- Settings button
- pull to refresh
- synced ordering through the same `CloudSortPreferences` mechanism used by iPhone

Each row shows:
- icon
- display name
- compact 5-hour remaining summary
- compact 7-day remaining summary

## Apple Watch account detail screen
On watch, the detail screen includes:

### Account section
- Name
- Icon
- Last Login

### Rate Limits section
- 5-Hour Remaining
- 5-Hour Reset
- 7-Day Remaining
- 7-Day Reset

Reset rows can toggle between relative and absolute time just like on iPhone.

### Live refresh footer states
The watch detail screen explicitly communicates whether live refresh is possible:
- **Waiting for iCloud Keychain to sync this account**
- **Live refresh isn't available for API-key accounts**

### Pull-to-refresh
The detail view itself is refreshable, so the user can force an immediate live rate-limit refresh.

### Danger Zone
- Remove Account

## Watch settings
The watch settings view includes:
- version display (includes build number)
- Remove All Accounts

The watch settings surface is intentionally minimal.

## Watch complications
The watch companion ships dedicated complications for:
- rate limit visibility
- app launcher

Families:
- accessoryCircular
- accessoryCorner

---

## Widgets, complications, and controls

Codex Switcher has several different widget surfaces, and they do not all behave the same way.

## Shared widget model
All widget-like surfaces consume a shared `SharedCodexState` snapshot from the App Group container, with an `NSUbiquitousKeyValueStore` mirror as a fallback. This matters because:

- widgets can launch before the full app does
- iPhone/watch widgets can appear before CloudKit has replayed the database locally
- extensions need a sync-safe representation that does not require direct SwiftData access

If the local shared-state file is temporarily unavailable or stale, widgets can fall back to the mirrored ubiquitous snapshot and prefer the freshest non-empty state by timestamp.

## macOS desktop widgets

### Saved Account widget
Families:
- `systemSmall`
- `systemMedium`

Behavior:
- shows one configured saved account
- displays icon, name, and subtitle
- if switching is available, shows **Log In** or **Current**
- if switching is not available, shows **Open**

This is a switch-focused widget, not a rate-limit overview surface.

### Rate Limits widget
Families:
- `systemSmall`
- `systemMedium`
- `systemLarge`

Behavior:
- shows one, two, or five accounts depending on family
- each account shows both 5h and 7d remaining windows
- empty configuration slots automatically fill from the shared stored account order
- missing configured accounts are rendered as **Missing Account**
- empty overall state renders **No Synced Accounts**

### Open Codex Switcher control
A control widget that simply launches the app.

### Switch Codex Account control
A control-widget toggle that acts like an exclusive selector:
- turning it on switches to that account
- turning the already-active account off is a no-op
- disabled unless the configured account exists and has a local snapshot
- designed to work without opening the full app UI

## iPhone Home Screen and Lock Screen widgets

### Rate Limits overview widget
Families:
- `systemSmall`
- `systemMedium`
- `systemLarge`

The iPhone overview widget uses the same underlying overview provider and account resolution rules as the desktop overview widget.

### Lock Screen rate-limit widget
Families:
- `accessoryCircular`
- `accessoryRectangular`

Configuration:
- one account
- one window (`5h` or `7d`)
- account can be left empty to use Automatic

## Apple Watch complications

### Rate Limit complication
Families:
- `accessoryCircular`
- `accessoryCorner`

Configuration:
- one account or Automatic
- one window (`5h` or `7d`)

### Open Codex Switcher complication
Families:
- `accessoryCircular`
- `accessoryCorner`

This is a launch surface rather than a data surface.

## Widget configuration semantics
Widget account selection uses a dedicated widget entity model.

Important details:
- widgets expose an explicit **Automatic** entity
- leaving a slot empty also behaves like Automatic
- overview widgets can take up to five accounts
- accessory widgets and watch complications take one account plus one window
- missing configured accounts are preserved as missing placeholders rather than silently replaced with the wrong account

## Widget timeline refresh behavior
Widget timelines are not constantly reloaded. Instead:

- the next reload is scheduled around the next reset boundary when one is known
- a minimum reload spacing is enforced
- if no future reset is known, the timeline falls back to a broader reload interval

This keeps widgets responsive around actual reset events without causing unnecessary churn.

---

## Notifications

Codex Switcher supports two notification classes.

## 1. Account switch notifications
These are primarily intended for:
- background switches
- automatic switches
- extension-driven switches

User-initiated in-app switches do **not** intentionally spam you with banners.

Notification content:
- title: **Account Switched**
- body: `Now using "<account name>".`

Two importance modes exist internally:
- passive background confirmation
- more attention-grabbing recovery notifications

## 2. Rate-limit reset notifications
These are scheduled when all of the following are true:
- the relevant preference is enabled
- the metric status is `exact`
- remaining percent is below `100`
- a future reset date exists
- notification delivery is authorized

Windows:
- 5-Hour Rate Limit Reset
- 7-Day Rate Limit Reset

Body format:
- `<account> is back to 100% for its 5-hour window.`
- `<account> is back to 100% for its 7-day window.`

The scheduler removes stale managed notifications before rescheduling the current set.

---

## Rate-limit tracking

Rate-limit tracking is one of the most technical parts of the app.

## Primary source: remote usage API
For ChatGPT-backed accounts, Codex Switcher queries:

```text
https://chatgpt.com/backend-api/wham/usage
```

using:
- a bearer access token
- optional `ChatGPT-Account-Id`
- an ephemeral `URLSession`

The session is configured with:
- no persistent cache
- short timeouts
- per-platform timeout tuning
- `Accept: application/json`
- `User-Agent: Codex Switcher`

## Fallback source: Codex session logs
If the remote read fails and the request is for the **current account on macOS**, the app can fall back to recent local session files under Codex's session-log area.

The session-log reader:
- reads the newest session files first
- inspects up to five files
- tails up to roughly `512 KB`
- scans JSONL events for token-count data
- infers the 5-hour and 7-day windows from observed durations

This fallback gives the app a usable picture even when the live endpoint is unavailable.

## Metric states
Each window is stored independently as:
- `exact` — fresh, trustworthy value
- `cached` — old value preserved because refresh failed or data was partial
- `missing` — no value to show

Widgets use this status to decide whether to apply semantic color or neutral gray fallback rendering.

## Backoff behavior
The app is intentionally conservative under failure.

It handles:
- `401` / `403` unauthorized
- `429` rate limiting with `Retry-After`
- transient network failures
- cancellation
- invalid payloads

The refresh engine applies:
- minimum request spacing
- per-minute request limiting
- transient backoff growth
- longer authorization backoff for invalid credentials

## Reset-boundary normalization
If a stored reset date has already passed, the app locally normalizes the corresponding remaining value to `100%`. That means stale-but-reasonable data can still behave correctly around reset boundaries even before the next network refresh arrives.

## Best-account ranking
When choosing the "best" account, Codex Switcher prefers accounts with complete 5h + 7d data and ranks them by remaining headroom, not by raw last-refresh recency.

The effective ranking logic is:
1. complete metrics before incomplete metrics
2. higher primary remaining headroom
3. higher secondary remaining headroom
4. pinned / stored order as tie breakers where appropriate

For widgets and automation, "best" means "best current operational headroom," not "most recently used."

---

## Automatic Switching ("Autopilot")

Autopilot is a macOS-only feature.

When enabled, Codex Switcher runs a background evaluation loop and attempts to switch to the account with the most remaining headroom.

## What Autopilot does
- refreshes rate limits for relevant accounts
- waits for recent Codex session activity to go quiet before reacting
- avoids switching while another switch is in progress
- avoids pointless work if the best account is already active

## Session quiet window
Codex can emit multiple session updates while work is still in flight. Autopilot therefore waits for a short quiet period after recent session activity before reevaluating, so it prefers switching **after** a task has finished rather than in the middle of one.

## Power and system-state behavior
Periodic background timers are intentionally paused when:
- the system is sleeping
- screens are sleeping
- Low Power Mode is enabled
- battery charge is critically low

Important nuance: **explicit user actions and activation-triggered refreshes still run.**  
Only unattended periodic background timers are suppressed.

## Current-account prioritization
During Autopilot refresh passes, the current account is prioritized so the app can quickly confirm whether a switch is actually necessary.

## Notification behavior
Autopilot-triggered switches can produce switch notifications if the shared notification preference is enabled.

---

## Account archives (`.cxa`)

Codex Switcher supports a portable archive format for moving accounts between devices or backing them up manually.

## What an archive contains
A `.cxa` archive preserves:
- name
- icon
- identity key
- auth mode
- email hint
- account identifier
- the full auth snapshot contents

It can contain either:
- one account
- multiple accounts

## Format details
The current archive format is:
- binary container version marker: `CXA` + version byte
- archive payload version: `2`
- compression: **zlib**
- filename extension: `.cxa`

The archive is intentionally compressed so Finder / Quick Look do not show readable plaintext just by peeking at the file.

> [!WARNING]
> `.cxa` archives are **compressed, not encrypted**.  
> They should be treated as sensitive secrets because they contain the auth snapshot needed to recreate an account.

## Import behavior
Archive import exists on:
- macOS
- iPhone

Supported entry points include:
- file importers
- dropped URLs
- shared/opened file URLs
- Files / Finder sharing

On import:
- the archive is decoded
- the contained snapshot is parsed
- the archive identity, if present, is validated against the parsed snapshot identity
- existing accounts are updated in place
- new accounts are inserted if no match exists

## Export behavior
Archive export exists on:
- macOS
- iPhone

Export requires a **local full snapshot** on the current device.  
That is why an account may be visible through CloudKit metadata but not yet exportable on iPhone/watch-derived surfaces.

## Multiple-account export
The macOS drag/export path can package multiple selected accounts into one archive bundle.

## Suggested filenames
Archive filenames are generated from:
- account name
- then email
- then account identifier
- then a fallback if nothing else is available

Filenames are sanitized so repeated exports, drag promises, and share operations remain clean and predictable.

---

## Data storage architecture

One of the design goals of Codex Switcher is: **do not put the wrong data in the wrong place**.

The app separates:
- synced metadata
- full secrets
- minimal synced refresh credentials
- device-local snapshot availability
- shared widget/intent state
- bookmark and command-routing infrastructure

## Storage layers overview

| Layer | Technology | Sync behavior | Secret-bearing | Purpose |
|---|---|---:|---:|---|
| Account metadata | SwiftData + CloudKit | Cross-device | No | Names, icons, order, rate-limit snapshots, last login, display hints |
| Full account snapshots (device-local copy) | Keychain in App Group access group | This device only | Yes | Local switching, extensions, export |
| Full account snapshots (synchronizable copy) | Synchronizable Keychain | Cross-device via iCloud Keychain | Yes | Make accounts usable/exportable on other devices |
| Minimal rate-limit credentials | Synchronizable Keychain | Cross-device via iCloud Keychain | Yes, but deliberately narrow | Live usage API refresh on iPhone/watch |
| Shared widget/intent snapshot | App Group JSON + ubiquitous mirror | Local + ubiquitous fallback | No | Widgets, complications, controls, intents |
| Local snapshot availability file | App Group JSON | Device-local | No | Tracks whether a full snapshot is actually usable on this device |
| Linked folder bookmark | Local defaults + App Group bookmark file | Mac-local/shared-with-extensions | Capability, not auth secret | Restore access to linked Codex folder |
| Command queue / result store | App Group JSON files | Device-local | No | Intent-to-app mutation routing |

## SwiftData model (`StoredAccount`)
The primary synced model stores metadata such as:
- `identityKey`
- `name`
- `createdAt`
- `lastLoginAt`
- `customOrder`
- `isPinned`
- `authModeRaw`
- `emailHint`
- `accountIdentifier`
- 5-hour remaining percentage
- 7-day remaining percentage
- 5-hour reset time
- 7-day reset time
- rate-limit observation timestamp
- metric display/version fields
- icon symbol name

Important security detail:
- older schema compatibility fields still exist
- full auth contents are **not** used as the active storage path anymore
- legacy fields are normalized away so secrets do not keep living in CloudKit-synced model rows

## Keychain snapshot store
Full snapshots are stored in Keychain under the account identity key, with two copies:

### Device-local App Group copy
- accessible while unlocked
- **ThisDeviceOnly**
- shared with app/extension surfaces on that device

### Synchronizable copy
- accessible while unlocked
- synchronizable through iCloud Keychain

When loading a snapshot, the store can opportunistically repair missing copies by recreating whichever side is absent.

## Local snapshot availability store
A small App Group JSON file tracks which identity keys have a usable local full snapshot on the current device.

This file is intentionally **not** synced through CloudKit, because "snapshot exists on this device" is local state, not shared metadata.

On iPhone/watchOS, the file is protected with:

```text
completeUntilFirstUserAuthentication
```

so widgets/companions can still read after the first unlock following boot.

## Minimal synced rate-limit credential store
For ChatGPT-backed accounts, the app exports only:
- identity key
- auth mode
- account ID
- access token
- export timestamp

API-key accounts do **not** get this export, because there is no access-token-based remote usage API path to call.

This minimal payload lives in a synchronizable Keychain store dedicated to rate-limit refresh and lets companion devices refresh usage data without requiring the full `auth.json` snapshot first.

That payload is intentionally narrow and does **not** try to be a general secret backup of the account.

## Shared widget / intent state
The app publishes a portable `SharedCodexState` snapshot that includes:
- auth state
- linked folder path (where relevant)
- current account identity
- selected account identity
- whether selection is live
- account list with display metadata
- rate-limit metrics and statuses
- local snapshot availability flags
- update timestamp

This is saved in:
- `SharedCodexState.json` in the App Group container
- mirrored data in `NSUbiquitousKeyValueStore`

The ubiquitous mirror exists so widgets can recover if the App Group file is missing, stale, or temporarily unreadable.

## App Group files
The shared container contains several purpose-specific files, including:

- `SharedCodexState.json`
- `LocalSnapshotAvailability.json`
- `LinkedCodexFolderShared.bookmark`
- `LinkedCodexFolder.bookmark` (legacy)
- `PendingCodexAppCommands.json`
- `PendingCodexAppCommandResults.json`
- `PendingCodexAccountOpenRequest.json`
- `CodexAccountSwitch.lock`

This is the backbone for extension safety and cross-surface coordination.

---

## How iCloud sync works

Codex Switcher uses **multiple Apple sync mechanisms**, each for a different class of data.

## 1. CloudKit via SwiftData
The `StoredAccount` metadata database is backed by SwiftData with automatic CloudKit integration in production builds.

This syncs things like:
- account names
- icons
- pinned state
- order
- last login
- rate-limit snapshots
- email hints / identifiers

This is why accounts captured on a Mac can later appear on iPhone and Apple Watch.

## 2. iCloud Keychain
Full snapshots and minimal rate-limit credentials propagate via synchronizable Keychain.

This is why a companion device may go through a sequence like:

1. account metadata appears first
2. account row is visible
3. widgets can already show metadata
4. full export/snapshot-driven features remain unavailable
5. later, iCloud Keychain finishes syncing
6. export/live-refresh capability becomes available

That staged behavior is intentional and accurately reflects which secret layers have arrived.

## 3. NSUbiquitousKeyValueStore
Codex Switcher also uses ubiquitous key-value storage for:
- shared widget state mirroring
- iPhone/watch sort preferences

This gives very lightweight sync for small values that do not belong in the main database.

## What syncs and what stays local

### Syncs across devices
- account metadata
- names
- icons
- order
- pin state
- rate-limit data
- full snapshots (through iCloud Keychain)
- minimal rate-limit credentials (through iCloud Keychain)
- iPhone/watch sort preferences
- mirrored shared state snapshot

### Stays local to a device
- whether a local full snapshot is already usable on that device
- security-scoped folder access capability
- the active live `auth.json` file on a specific Mac
- command queues / result queues
- in-memory refresh backoff state
- app-instance coordination state

## Sync conflict handling
Several design choices exist specifically to make sync safer:

- account identity is semantic, not UUID-based
- local-only fields are normalized away from CloudKit rows
- shared widget state prefers the freshest timestamped state
- empty local snapshots do not automatically override a richer fallback snapshot
- remote deletion cleanup removes lingering secrets only when the last metadata row for an identity disappears

## Deletion cleanup
When a synced account row is removed, the macOS app processes SwiftData history and, if no rows for that identity remain, deletes:
- the full Keychain snapshot
- the synced minimal rate-limit credential

This prevents "ghost secrets" from surviving indefinitely after remote deletion.

---

## Security and privacy design

Security is central to the architecture, because the app is effectively managing login material.

## Sandboxing
The macOS app is sandboxed and only receives disk access through:
- user-selected folder access
- security-scoped bookmarks

It does not need blanket filesystem access.

## Security-scoped bookmarks
The linked folder bookmark is used so the app can continue accessing the chosen Codex folder across launches. The app maintains:
- a local app-scoped security bookmark
- a shared implicit bookmark for extension surfaces

If a bookmark becomes stale but still resolves, Codex Switcher refreshes the stored bookmark data.

## Coordinated file IO
Reads and writes use `NSFileCoordinator` so account switching behaves correctly around sandboxed file access and avoids sloppy direct file replacement logic.

## Write verification
Switching does not stop at "write succeeded."  
After writing `auth.json`, the app reads it back and reparses the result. If the resulting identity does not match the intended target, the switch is treated as failed.

## Restrictive file permissions
After a successful write, the app attempts to restore `0600` permissions on `auth.json`.

## Secret minimization
The architecture intentionally minimizes where secrets travel.

### Full snapshot
Stored only in Keychain, not SwiftData / CloudKit.

### Minimal live-refresh credential
A separate smaller payload exists only because iPhone/watch need live rate-limit refresh. It is intentionally narrower than a full snapshot.

### Widget and intent state
Contains no full auth snapshot.

## Legacy schema repair
The project contains migration/repair logic specifically to:
- scrub legacy secret-bearing fields from synced rows
- normalize legacy local-only fields that should never have been CloudKit data

This is one of the most important implementation details in the codebase. It is what keeps the current architecture from inheriting the wrong trust boundaries from earlier schemas.

## Notification privacy
Notifications intentionally contain concise account-switch or reset information. They do not expose full credential payloads.

## Archive caution
`.cxa` archives are portable and convenient, but because they contain auth snapshots, they should be handled like secret material. Compression is **not** encryption.

---

## App Intents, Shortcuts, and automation

Codex Switcher has a surprisingly rich automation surface.

## App Shortcuts
The app exposes shortcuts such as:
- Open App
- Open Account
- Switch Account
- Best Account
- Current Account
- Add Account

## Query intents
Codex Switcher can return:
- selected account
- current account
- all accounts
- best account
- current account rate limits
- one account's rate limits
- best-account rate limits

## Search intents
It can search by:
- name
- email hint
- account identifier

through:
- Find Codex Account
- Find Codex Accounts

## Mutation intents
The app supports:
- Add Current Codex Account
- Switch Codex Account
- Switch to Best Codex Account
- Remove Codex Account
- Quit Codex Switcher

## Settings intents
There are also intent-driven settings toggles:

### macOS-only
- Set Notifications
- Set Menu Bar Visibility
- Set Launch at Login

### Cross-platform / shared
- Set Automatically Switch Account

## Why some intents are app-owned
Some mutation intents deliberately run through the main macOS app rather than trying to mutate state directly from an extension context. That is because the main app owns:
- the durable security-scoped folder bookmark
- the authoritative SwiftData context
- safe quit behavior
- the switch/write pipeline

To make that work, intents can enqueue commands into a shared App Group command queue and optionally wait for results.

## Command queue architecture
The queue supports actions such as:
- capture current account
- switch account
- switch best account
- remove account
- quit application

Command execution results are written to a separate result store, and foreground intents wait until those results are available before returning. That prevents later Shortcuts steps from reading stale state.

## Current vs selected vs best in automation
The app deliberately models these concepts separately:
- **current** — what Codex is actively using
- **selected** — what the UI is highlighting right now
- **best** — the account with the strongest rate-limit headroom

That separation makes intents much more useful than a single overloaded "active account" concept.

## Spotlight
When the build enables account Spotlight indexing, saved accounts are published as searchable app entities. That lets Spotlight open directly into a specific account.

## iPhone quick actions
The iPhone app also publishes up to four Home Screen quick actions based on account ordering.

---

## Sorting, ordering, and presentation rules

Codex Switcher uses consistent display logic across platforms.

## Display name resolution
If a custom name is empty or missing, the app falls back through:
1. custom name
2. email hint
3. account identifier
4. identity key
5. `Unnamed Account`

## Sort criteria
- Name
- Date Added
- Last Login
- Rate Limit
- Custom

## Direction rules
- Name / Date Added / Last Login / Rate Limit: Ascending or Descending
- Custom: internally normalized to Ascending

## Search rules
Search matches:
- account name
- email hint
- account identifier

## Pinned precedence
Pinned always comes before unpinned.

## Shared/widget comparator
Widget and automation surfaces use a dedicated shared-account comparator so:
- pinned accounts stay first
- stable order is preserved
- entities remain predictable across sync and widget refreshes

---

## Build from source

Codex Switcher is a multi-target Apple-platform project with shared code across:
- macOS app
- iPhone app
- Apple Watch app
- macOS widget/control extension
- iPhone widget extension
- watch widget extension
- shared core modules

## Requirements
You need a recent version of Xcode that supports:
- SwiftUI
- SwiftData
- CloudKit-backed SwiftData
- WidgetKit
- App Intents
- modern Apple platform deployment targets used by the project

For exact deployment targets, refer to the Xcode project settings in `CodexSwitcher.xcodeproj`.

## Basic build steps
1. Open `CodexSwitcher.xcodeproj`
2. Configure signing for all targets
3. Build the macOS app
4. Build the iPhone and watch targets if you want companion surfaces
5. Run the macOS app, link a real Codex folder, and capture an account

## Important signing / entitlement note for forks
If you are forking or re-signing the project under a different team or bundle namespace, you will need to update the shared capability identifiers consistently across targets, including:

- App Group: `group.com.marcel2215.codexswitcher`
- iCloud container: `iCloud.com.marcel2215.codexswitcher`
- ubiquity key-value identifier
- any related provisioning/signing setup for widgets and companions

If those identifiers diverge across targets, sync and shared-state behavior will break.

## Why CloudKit and App Group setup matters
Without the correct entitlements:
- companion devices will not see the database
- widgets will not see the shared state
- synchronizable Keychain flows may not behave correctly
- control/intent/widget features may silently lose access to the same shared storage layers

---

## Repository structure

The repository is organized around target folders, with reusable storage, model, sync, and intent code flattened into the iPhone app folder and reused from there across targets.

```text
CodexSwitcher/                  macOS app
CodexSwitcherApp/               iPhone companion app plus reused cross-target support sources
CodexSwitcherWatchApp/          Apple Watch companion app
CodexSwitcherMacWidgets/        macOS widgets and control widgets
CodexSwitcherWidgets/           iPhone widgets
CodexSwitcherWatchWidgets/      watch complications
```

This layout keeps platform UI thin while the parsing, state, switching, refresh, archive, and widget-support layers stay reusable across targets.

---

## Tests

The repository includes:
- macOS unit tests
- macOS UI tests
- iPhone unit tests
- iPhone UI tests
- watch tests
- watch UI tests

There are also dedicated tests around areas such as:
- single-instance coordination
- archive import/export
- iOS rate-limit refresh behavior
- reset-notification scheduling

For a utility app that touches secrets, sync, widgets, and background behavior, that test coverage is an important part of keeping regressions under control.

---

## Limitations and important behavior notes

- **macOS is required for direct Codex switching.**
- **Only file-backed auth is supported for switching.**
- **API-key accounts do not support live remote usage API refresh.**
- An account can appear on iPhone/watch before its full snapshot becomes locally exportable.
- Widget/configured control switching requires a local snapshot on the current machine.
- iPhone/watch companion apps do not link desktop filesystem paths.
- Automatic Switching is paused by sleep and battery-saving conditions for unattended timers.
- Notification permissions are required before notification toggles can actually produce banners.
- Archive files are portable and sensitive; compression does not make them safe to share casually.

---

## Troubleshooting

## “Link Codex Folder”
The app has no usable bookmark yet.  
Open settings or use the banner link action and choose the Codex folder.

## “No auth.json”
Possible causes:
- Codex is logged out
- you linked the wrong directory
- Codex is using a different `CODEX_HOME`
- Codex is configured for a non-file credential store

## “Permission Needed”
The stored bookmark no longer grants access.  
Relink the folder.

## “Codex Folder Missing”
The previously linked folder is no longer available at that path.

## “Invalid auth.json”
The file is either:
- not valid UTF-8 / JSON
- or it does not contain a supported Codex account payload

## “Unsupported Credential Store”
Your `config.toml` indicates `keyring` or `auto`.  
Codex Switcher only supports file-backed switching.

## iPhone says an account is not exportable yet
The metadata synced, but the full snapshot has not yet arrived locally through iCloud Keychain.  
Open Codex Switcher on the originating device after updating, wait a moment, or import the `.cxa` archive manually.

## Watch says it is waiting for iCloud Keychain
The watch sees the account record but not yet the synced minimal credential or full snapshot needed for live refresh.

## Widgets show “No Synced Accounts”
Open the main app so CloudKit and the shared-state snapshot can refresh.

## Automatic Switching is not doing anything
Check:
- the linked folder is valid
- the credential store is file-backed
- rate-limit data exists
- the machine is not sleeping
- Low Power Mode / critical battery are not pausing periodic timers
- the currently active account is not already the best candidate

---

## Why the architecture is split this way

The codebase makes several deliberate trade-offs:

### Secrets are not CloudKit metadata
Full `auth.json` snapshots are too sensitive and too device-capability-specific to live in the synced database model.

### Sync still needs to be useful before full secrets arrive
That is why the app syncs metadata separately, mirrors shared state for widgets, and syncs a narrow rate-limit credential payload independently.

### Widgets and intents need a stable, portable snapshot
That is why `SharedCodexState` exists instead of having every extension poke directly at SwiftData.

### Switching must be verified, not assumed
That is why writes are coordinated, read back, reparsed, and compared to the intended target identity.

### Device-local availability matters
That is why "has a local snapshot here" is tracked separately from "this account exists in the synced library."

Those design choices make Codex Switcher more complex than a naive file replacer, but they are exactly what make the app usable across macOS, iPhone, Apple Watch, widgets, and automation surfaces.

---

## In practice

If you want the shortest practical description of the app, it is this:

Codex Switcher is a **native multi-platform account manager for Codex** that safely captures and restores file-backed `auth.json` identities on macOS, syncs the account library across your Apple devices, tracks live rate-limit headroom, and exposes the whole system through widgets, watch complications, notifications, and App Intents.

If you want the more technical description, it is this:

Codex Switcher is a **SwiftUI + SwiftData + CloudKit + Keychain + WidgetKit + App Intents** architecture that separates synced metadata from secret snapshots, uses security-scoped bookmarks to own a real Codex folder, publishes a shared portable state model for extensions, and turns a single mutable `auth.json` into a robust multi-account workflow.

---

## Summary

Use Codex Switcher if you want:

- fast switching between saved Codex accounts on macOS
- a synced account library on iPhone and Apple Watch
- visibility into remaining 5h / 7d headroom
- background automatic switching to the best available account
- widgets and complications for at-a-glance status
- Shortcuts / App Intents / control-widget automation
- secure separation between synced metadata and secret auth material
- portable account export/import through `.cxa`

And avoid it if your Codex setup depends on non-file credential stores like `keyring` or `auto`, because the app is intentionally built around safe control of file-backed `auth.json`.

---
