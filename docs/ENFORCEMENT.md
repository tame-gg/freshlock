# Enforcement roadmap (Endpoint Security)

How FreshLock moves from Phase 0 overlays toward the strongest **public-API**
enforcement ceiling, without private APIs or malware techniques.

Read [THREAT_MODEL.md](THREAT_MODEL.md) first. This file is the engineering plan.

---

## Ceiling (honest)

| Goal | Public-API result |
|------|-------------------|
| Kernel-held deny of locked app **exec** | **Yes** - `ES_EVENT_TYPE_AUTH_EXEC` via Endpoint Security |
| Third-party code in the kernel | **No** - ES clients are userland; kernel only holds the gate |
| Admins cannot uninstall / revoke | **No** on personally owned Macs |
| Mac App Store distribution of ES AUTH client | **Not realistic** |

NetworkExtension and DriverKit are the wrong planes (network / device I/O).
They are not used for app locking.

---

## Phase 0 (shipping)

See [ARCHITECTURE.md](ARCHITECTURE.md). Userland only:

`NSWorkspace` → overlay → `LocalAuthentication` → PID-scoped grant.

---

## Phase 1 (scaffolded in-tree)

### Code layout

| Path | Role |
|------|------|
| `Sources/FreshLockEnforce/` | Pure policy: signing-ID matching, allow/deny decisions, unlock allowlist snapshot. Unit-tested; no ES link required. |
| `Sources/FreshLockEnforceExtension/` | ES client scaffolding: `es_new_client`, subscribe `AUTH_EXEC`, respond allow/deny. Links `EndpointSecurity`. |
| `Packaging/EnforceExtension-*.plist` / entitlements | Bundle metadata for a future `.systemextension` |

`Scripts/build-app.sh` does **not** embed the system extension yet. Shipping Phase 0
is unchanged until Apple grants the entitlement and packaging is wired.

### Policy algorithm (AUTH_EXEC)

1. Extract target identity from `es_process_t` (`signing_id`, `team_id`, optional `cdhash`).
2. If signing ID is **not** in the protected/locked set → `ALLOW` (cached when safe).
3. If signing ID is protected **and** present on the unlock allowlist → `ALLOW`.
4. Otherwise → `DENY` (kernel never starts the image).
5. Always `ALLOW` FreshLock's own signing ID and critical platform paths as needed;
   mute self-generated noise via ES mute APIs.

Unlock still happens in the host/helper via LocalAuthentication. On success the
host updates the allowlist the extension reads (file and/or XPC - see
`EnforceAllowlistStore` / `EnforceControlXPC`).

### Identity caveat

ES does not expose "bundle identifier" as a first-class field. Modern apps
usually have `signing_id` equal to `CFBundleIdentifier`. Helpers, scripts,
`open`, and renamed copies need explicit policy coverage - a main-app-only
deny list can leak. Phase 1 docs and code call this out; do not claim perfect
coverage of every launch path on day one.

### Prerequisites to activate

1. Request Apple entitlement:
   [System Extension request](https://developer.apple.com/contact/request/system-extension/)
   for `com.apple.developer.endpoint-security.client`.
2. Host entitlement: `com.apple.developer.system-extension.install`.
3. Package as Endpoint Security system extension; user (or MDM) approval.
4. Full Disk Access for the extension / host as required by TCC.
5. Developer ID signing + notarization.
6. Wire `LockCoordinator` grant/revoke to the allowlist the ES client consults.
7. Optionally set `NSEndpointSecurityEarlyBoot` so non-platform exec waits at boot.

Development without the entitlement typically requires SIP off (and possibly
AMFI boot-args). That is for developers only - never a user instruction for
"more security."

### Entitlement risk

Apple targets ES at EDR/AV-class products. A consumer app locker may be
**declined**. Treat Phase 1 as contingent; do not advertise it as shipping until
approved and tested on SIP-on machines.

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
