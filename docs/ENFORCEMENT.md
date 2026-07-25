# Enforcement roadmap (Endpoint Security)

How FreshLock moves from Phase 0 overlays toward the strongest **public-API**
enforcement ceiling, without private APIs or malware techniques.

Read [THREAT_MODEL.md](THREAT_MODEL.md) first. This file is the engineering plan.

---

## Kernel extensions vs System Extensions (answer to "can't we make a kext?")

| Mechanism | Status on modern macOS | Fit for FreshLock |
|-----------|------------------------|-------------------|
| **Kernel extension (kext)** | Deprecated / heavily restricted. Third-party kexts are not a viable shipping path on current macOS (user approval era ended; SIP + notarization + Apple policy). | **Wrong vehicle.** We will not ship a kext. |
| **System Extension** (Endpoint Security) | Supported public API. Userland client; **kernel holds** `AUTH_EXEC` until allow/deny. | **Correct vehicle.** This is what Phase 1 builds. |
| NetworkExtension / DriverKit | Supported, but wrong plane (network / device I/O). | Not used for app locking. |

**System Extensions exist for this class of problem:** defensive security products get a privileged userland agent with kernel-enforced AUTH decisions. That *is* what we can and should build. It is not a classic kext, and it is **not** MagSafe admin-proof: an admin can still uninstall the host, revoke Full Disk Access, or deactivate the extension on an unsupervised Mac.

---

## Ceiling (honest)

| Goal | Public-API result |
|------|-------------------|
| Kernel-held deny of locked app **exec** | **Yes** - `ES_EVENT_TYPE_AUTH_EXEC` via Endpoint Security system extension |
| Third-party code in the kernel (kext) | **No** - deprecated; ES clients are userland |
| Admins cannot uninstall / revoke | **No** on personally owned / unsupervised Macs |
| Mac App Store distribution of ES AUTH client | **Not realistic** |

---

## Phase 0 (shipping)

See [ARCHITECTURE.md](ARCHITECTURE.md). Userland only:

`NSWorkspace` → overlay → `LocalAuthentication` → PID-scoped grant.

`Scripts/build-app.sh` default path does **not** embed a system extension.

---

## Phase 1 (in-tree; not shipping by default)

### Code layout

| Path | Role |
|------|------|
| `Sources/FreshLockEnforce/` | Pure policy: signing-ID matching, allow/deny, allowlist + locked-set stores, paths. Unit-tested; no ES link. |
| `Sources/FreshLockEnforceExtension/` | ES client: `es_new_client`, `AUTH_EXEC`, allow/deny. Links `EndpointSecurity`. Exits cleanly if not entitled. |
| `Sources/FreshLockEngine/Services/EnforcePolicySync.swift` | After LA unlock / config change, writes locked set + allowlist the extension reads. |
| `Sources/FreshLock/Managers/SystemExtensionRegistrar.swift` | `OSSystemExtensionRequest` activate/deactivate scaffolding (Preferences → Developer mode). |
| `Packaging/EnforceExtension-*` | `.systemextension` Info.plist + entitlements |
| `Scripts/build-systemextension.sh` | Assembles `gg.tame.freshlock.enforce.systemextension` |
| `EMBED_SYSTEM_EXTENSION=1` | Optional flag on `Scripts/build-app.sh` to embed the sysext (off by default) |

### Build / test the extension (no Apple approval required to *compile*)

```bash
# Policy unit tests (no entitlement)
swift test

# Build the ES client binary
swift build --product FreshLockEnforceExtension

# Assemble a real .systemextension bundle
Scripts/build-systemextension.sh

# Optional: embed into the app (still won't AUTH without entitlement + FDA + approval)
EMBED_SYSTEM_EXTENSION=1 Scripts/build-app.sh

# Default Phase 0 app build (unchanged for users without the entitlement)
Scripts/build-app.sh
```

Standalone run of the extension binary without entitlement / root / FDA: logs
`ES client unavailable` and **exits 0** (fail-clean). There is no kernel gate to
"fail closed" without a successful `es_new_client`.

### Policy algorithm (AUTH_EXEC)

1. Extract target identity from `es_process_t` (`signing_id`, `team_id`, optional path).
2. If signing ID is **not** in the protected/locked set → `ALLOW` (cache when safe).
3. If signing ID is protected **and** present on the unlock allowlist → `ALLOW`.
4. Otherwise → `DENY` (kernel never starts the image).
5. Always `ALLOW` FreshLock's own signing IDs; mute noisy system path prefixes.

Unlock still happens in the host/helper via LocalAuthentication. On success,
`EnforcePolicySync` updates the allowlist files the extension reloads
(`enforce-allowlist.json` / `enforce-locked.json` under Application Support).

### Identity caveat

ES does not expose "bundle identifier" as a first-class field. Modern apps
usually have `signing_id` equal to `CFBundleIdentifier`. Helpers, scripts,
`open`, and renamed copies need explicit policy coverage - a main-app-only
deny list can leak. Phase 1 docs and code call this out; do not claim perfect
coverage of every launch path on day one.

### Prerequisites to activate (SIP-on)

1. Request Apple entitlement:
   [System Extension request](https://developer.apple.com/contact/request/system-extension/)
   for `com.apple.developer.endpoint-security.client`.
2. Host entitlement: `com.apple.developer.system-extension.install`
   (`Packaging/FreshLock-SystemExtension-Host.entitlements`).
3. Package as Endpoint Security system extension; user (or MDM) approval.
4. Full Disk Access for the extension / host as required by TCC.
5. Developer ID signing + notarization.
6. Unlock grants already sync to the allowlist via `EnforcePolicySync`.
7. Optionally set `NSEndpointSecurityEarlyBoot` so non-platform exec waits at boot.

Development without the entitlement typically requires SIP off (and possibly
AMFI boot-args). That is for developers only - never a user instruction for
"more security."

### Entitlement status

**Not granted in-tree.** Entitlement plists are ready; Apple must whitelist the
team. Consumer "app locker" use may be **declined**. Treat Phase 1 as contingent;
do not advertise kernel enforcement as shipping until approved and tested on
SIP-on machines.

---

## Phase 2 (enterprise)

MDM payloads: PPPC (FDA), Allowed System Extensions, supervised restrictions,
ADE. Documented in THREAT_MODEL; not implemented in this repo yet.

---

## References

- [Endpoint Security](https://developer.apple.com/documentation/endpointsecurity)
- [ES event types](https://developer.apple.com/documentation/endpointsecurity/es_event_type_t)
- [ES client entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.endpoint-security.client)
- [System Extensions](https://developer.apple.com/system-extensions/)
- [WWDC20: Build an Endpoint Security app](https://developer.apple.com/videos/play/wwdc2020/10159/)
- `man 7 EndpointSecurity` (early boot, etc.)
