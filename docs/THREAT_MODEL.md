# Threat model

This document is the authoritative statement of what FreshLock **can** and
**cannot** guarantee on macOS 15+. It deliberately separates today's shipping
controls (Phase 0) from the strongest realistic public-API path (Phase 1+) and
from claims that are **impossible** for a third-party Mac app.

> **Hard truth:** On a personally owned Mac, a third-party app **cannot**
> guarantee "admins cannot bypass." Absolute non-bypassability requires org
> ownership of the device trust root (supervised MDM / ADE), not a consumer
> Developer ID or Mac App Store product.

Related: [ARCHITECTURE.md](ARCHITECTURE.md), [ENFORCEMENT.md](ENFORCEMENT.md),
[SECURITY.md](../SECURITY.md).

---

## 1. Assets

| Asset | Why it matters |
|-------|----------------|
| Privacy of protected apps' on-screen UI | Casual shoulder-surfing / brief physical access |
| Privacy of protected apps' in-memory / on-disk data **while the Mac is unlocked** | Opportunistic browsing of Messages, banking, mail, etc. |
| Unlock grants (in-memory, PID-scoped) | Must not silently persist across quit/relaunch |
| Configuration (protected app list) | Tampering changes what is locked; not a secret store |

FreshLock does **not** protect: FileVault keys, Keychain items belonging to other
apps, network traffic, or data at rest when the disk is unlocked.

---

## 2. Adversaries

### In scope (what we design against)

| Adversary | Capabilities | Goal |
|-----------|--------------|------|
| **Casual / opportunistic user** | Brief physical access to an unlocked, logged-in session; no admin password | Open a protected app and read it |
| **Standard (non-admin) local user** | Normal user rights; cannot install system software or change SIP | Same, plus limited process tampering |

### Out of scope (explicitly not promised)

| Adversary | Why out of scope |
|-----------|------------------|
| **Local administrator / device owner** | Owns the Mac; can uninstall software, revoke TCC, use Recovery |
| **SIP off / Recovery Mode operator** | Can disable Endpoint Security integrity, wipe, reinstall |
| **Malware with root already** | Already past FreshLock's trust boundary |
| **MDM / org admin** | Can remove management profiles and enrolled software |
| **Forensic disk access with FileVault key** | At-rest encryption is FileVault's job, not FreshLock's |

---

## 3. Trust boundaries

```
┌─────────────────────────────────────────────────────────────────┐
│  Kernel / SIP / Apple platform binaries                         │
│  (Endpoint Security hold points live here; third-party code     │
│   does NOT run in-kernel)                                       │
└────────────────────────────▲────────────────────────────────────┘
                             │ AUTH allow/deny (Phase 1 only)
┌────────────────────────────┴────────────────────────────────────┐
│  Privileged userland                                            │
│  • ES system extension / root ES client (Phase 1)               │
│  • TCC Full Disk Access                                         │
└────────────────────────────▲────────────────────────────────────┘
                             │ policy / unlock allowlist (XPC/file)
┌────────────────────────────┴────────────────────────────────────┐
│  FreshLock userland (Phase 0 today)                             │
│  • FreshLock.app + FreshLockHelper (Login Item)                 │
│  • NSWorkspace monitor → overlay → LocalAuthentication          │
│  • Accessibility (AX) for window geometry                       │
└────────────────────────────▲────────────────────────────────────┘
                             │
┌────────────────────────────┴────────────────────────────────────┐
│  Protected apps (other processes)                               │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. Enforcement phases

### Phase 0 — Userland deterrent (**shipping**)

| Control | Mechanism |
|---------|-----------|
| Detect launch / activate | `NSWorkspace` notifications (**after** launch begins) |
| Cover UI | Top-most overlay + Accessibility / `CGWindowList` |
| Authenticate | `LocalAuthentication` (`deviceOwnerAuthentication`) only |
| Persist protection without GUI | `SMAppService` helper running `LockEngine` |
| Relock | Sleep, screen lock, policy timers, switch-away, quit→new PID |

**What Phase 0 guarantees**

- A strong **deterrent** against casual access on a logged-in Mac.
- No password/secret handling by FreshLock (LA returns success/failure only).
- Quit → relaunch of a protected app requires a new auth (PID-scoped grants).

**What Phase 0 does *not* guarantee**

- Pre-exec veto (the process may start and draw before the overlay).
- Mission Control / Spaces / Exposé / Stage Manager preview scrubbing.
- Survival against admin kill / uninstall / TCC revoke / Recovery.
- Kernel-held enforcement of any kind.

**Do not call Phase 0 "kernel enforced."** Overlays are userland UI.

### Phase 1 — Endpoint Security `AUTH_EXEC` (**scaffolded; not shipping**)

Public API path toward **kernel-held** launch denial:

| Requirement | Notes |
|-------------|--------|
| Managed entitlement `com.apple.developer.endpoint-security.client` | Apple approval; may be declined for consumer "app locker" use |
| System extension (preferred) or root daemon | SIP protects sysexts better than a plain LaunchDaemon |
| Full Disk Access (TCC) | Required to create an ES client |
| Developer ID + notarization | Not Mac App Store compatible for this model |
| Match on `signing_id` / `team_id` / `cdhash` | Bundle ID is not a first-class ES field; signing ID usually aligns |

On `ES_EVENT_TYPE_AUTH_EXEC`, the kernel **holds** exec until the client
responds `ALLOW` or `DENY`. That is real pre-userland enforcement for the
exec gate - still with a **userland policy agent**, not third-party code in
the kernel.

**What Phase 1 can add**

- Locked apps do not run userland code until policy allows (no overlay race for
  the main executable path, modulo helpers / interpreters - see ENFORCEMENT.md).
- Optional `NSEndpointSecurityEarlyBoot` so third-party exec waits for the
  client at boot.

**What Phase 1 still cannot claim**

- "Admins cannot bypass" - an admin can uninstall the host app (Finder),
  revoke FDA, deactivate the extension, or use Recovery.
- "Root cannot touch this" - SIP-on makes casual `kill`/`unload` hard for a
  proper sysext; SIP-off / Recovery / supported uninstall paths remain.

Apple may reject the ES entitlement for a consumer locker. Phase 1 ships only
if approved; scaffolding lives in-tree so the design is reviewable now.

### Phase 2 — Supervised / MDM fleet (**enterprise only**)

| Control | Effect |
|---------|--------|
| PPPC profiles forcing FDA | Users cannot casually revoke access |
| Allowed System Extension payload | Auto-approve ES extension |
| Supervised restrictions | Limit software removal / enrollment escape |
| ADE / Apple Business Manager | Org owns activation trust |

Stronger against **managed end users**. Still bypassable by the **MDM admin**
and by anyone who can erase / reassign the device outside org policy.

### Impossible claims (do not market)

| Claim | Reality |
|-------|---------|
| "Admins cannot bypass on a personal Mac" | **False** with any public API |
| "As strong as iOS Screen Time against the device owner" | Screen Time is Apple's first-party stack; not available as a general third-party locker API |
| "Mac App Store + ES AUTH_EXEC" | Distribution / entitlement model conflict |
| "Works without Apple's ES entitlement" | Production ES clients require the managed entitlement (SIP-on) |
| "Third-party code in the kernel" | DriverKit / ES replace kexts; app lock does not get a custom kext |
| "NetworkExtension / DriverKit locks apps" | Wrong enforcement plane (network / device I/O only) |

---

## 5. Attack / bypass catalogue

| Bypass | Phase 0 | Phase 1 (SIP on) | Phase 2 (supervised) |
|--------|---------|------------------|----------------------|
| Wait for overlay race / Mission Control preview | Works | Mitigated for exec; previews N/A if never launched | Same as Phase 1 |
| Force-quit FreshLock / helper | Works | Sysext may keep denying exec | Same; MDM may reinstall |
| Uninstall via Finder (admin auth) | Works | Works (supported uninstall) | Often blocked by MDM |
| Revoke Accessibility / FDA | Degrades / stops | Stops ES client | PPPC can force FDA |
| `csrutil disable` / Recovery | Full bypass | Full bypass | Org recovery procedures |
| Boot external OS / Target Disk | If FV unlocked | Same | Same |
| Separate standard user (no admin) | Stronger residual risk | Strong residual resistance if admin installed ES | Best residual |

---

## 6. Guarantees summary

| Statement | Status |
|-----------|--------|
| Casual deterrent on unlocked session (Phase 0) | **Yes** - shipping |
| Never handles passwords; uses LocalAuthentication only | **Yes** |
| Kernel-held `AUTH_EXEC` deny for locked signing IDs (Phase 1) | **Feasible** with Apple entitlement + sysext; **scaffolded, not shipping** |
| Survives GUI quit (helper / later sysext) | **Yes** (helper today) |
| Non-admin cannot easily remove Phase 1 once admin-installed | **Often true** in practice; not a formal guarantee |
| Admin / owner cannot bypass | **No - impossible** for third-party on personally owned Macs |
| Equivalent to supervised MDM binary allowlists | **No** - that is org MDM policy, not this app |

---

## 7. Recommended user guidance

For stronger separation than any app locker:

1. **FileVault** on
2. **Separate macOS user accounts** (standard vs admin)
3. Lock the screen when stepping away
4. Prefer apps' own lock features where they exist
5. For org devices: **supervised MDM**, not a consumer locker alone

FreshLock remains valuable as an iOS-like app lock **deterrent**. Phase 1, if
Apple entitles it, raises the bar to **kernel-held exec denial** without
changing the ownership reality that admins can remove the product.
