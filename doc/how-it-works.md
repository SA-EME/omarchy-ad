# omarchy-ad: how it works

This document explains how `omarchy-ad` works: the components, what is called at each step, every file created or modified, and how to troubleshoot.
Domain, group and machine names are examples: `example.corp`, `EXAMPLE.CORP`, `Allowed-AD-Group`, `WS01`.

---

## 1. Overview

### 1.1 What the package does

| Need | Solution | File or tool |
|---|---|---|
| Join the workstation to AD | `realmd` + `adcli` + `sssd` | `omarchy-setup-ad join` |
| Log in with an AD account | SSSD plugged into PAM and NSS | `sssd.conf`, `sssd-arch`, `nsswitch.conf` |
| Create the home on first login | `pam_mkhomedir` | `/etc/pam.d/sssd-arch` |
| Choose or type the user | SDDM theme | `omarchy-users` |
| Unlock the screen (`Super+L`) with an AD account | `pam_sss` added | `/etc/pam.d/omarchy-lock-password` |
| `su` with an AD account | `system-auth` included | `/etc/pam.d/su` |
| sudo for AD administrators | sudoers rule on a group | `/etc/sudoers.d/50-ad-admins` |
| Authorization dialog (polkit) for AD administrators | polkit rule on a group | `/etc/polkit-1/rules.d/50-ad-admins.rules` |
| Restrict access to a group | `access_provider = simple` | `sssd.conf` |
| Survive an Omarchy update | pacman hook + systemd unit | `reapply` |

### 1.2 What happens at boot

1. **LUKS password**: asked before Linux starts. It is tied to no user and has nothing to do with AD.
2. **SDDM** starts with the `omarchy-users` theme (keyboard and monitors set by `/etc/sddm-hyprland.lua`).
3. The user chooses or types a **name**, then a password.
4. **PAM** checks the password: `pam_sss` asks SSSD, which asks AD over Kerberos. For a local account, SSSD does not know it and `pam_unix` takes over.
5. First login of an AD account: **`pam_mkhomedir`** creates `/home/<user>`.
6. The **Omarchy session** (uwsm + Hyprland) starts.
7. `Super+L`: the lock screen uses **its own PAM file**, fixed by the tool.

---

## 2. Components

| Component | Role |
|---|---|
| **AD (domain controllers)** | Directory of users, groups and passwords. Speaks LDAP and Kerberos. |
| **Kerberos (`krb5`)** | AD's authentication protocol. The password is checked by the domain controller (KDC) and never stored in clear text. |
| **`realmd` / `adcli`** | **Setup** tools: join the machine (computer account, keytab) and generate the SSSD configuration. They are no longer needed afterwards. |
| **`sssd`** | **Permanent** service: provides users and groups (NSS) and checks passwords (PAM). |
| **NSS** (`/etc/nsswitch.conf`) | Tells Linux where to look up users and groups. `passwd: files systemd sss`: local files first, then SSSD. |
| **PAM** (`/etc/pam.d/*`) | Module chain that accepts or refuses a login. Each service (sddm, sudo, su, lock screen) has its own file. |
| **SDDM** | Graphical login manager. |
| **Hyprland + uwsm** | Omarchy's compositor and session launcher. |
| **`/etc/krb5.keytab`** | The machine's own "password", created at join time. SSSD uses it to query AD. |
| **systemd** | `.path` units (file watching) and `.service` units. |
| **pacman (libalpm)** | Hooks in `/usr/share/libalpm/hooks` run after a transaction. |

### 2.1 SSSD processes

| Process | Role |
|---|---|
| `sssd` | Supervisor: reads `sssd.conf`, starts the others. |
| `sssd_be` | Backend: talks to AD (LDAP for identities, Kerberos for authentication). Starts `krb5_child` (password check) and `ldap_child`. |
| `sssd_nss` | Answers `id`, `ls -l`, `sudo` requests: "who is UID X?". |
| `sssd_pam` | Answers `pam_sss.so` requests. |
| `sssd_pac` | Reads group information provided by Kerberos. |

Logs: `/var/log/sssd/`. Cache: `/var/lib/sss/db/`.

---

## 3. Call chains

### 3.1 Graphical login of an AD account

```
Boot
 └─ sddm.service
     ├─ reads /etc/sddm.conf.d/*.conf   (zz-* last: they take priority)
     ├─ greeter compositor: start-hyprland -- --config /etc/sddm-hyprland.lua
     └─ sddm-greeter-qt6, omarchy-users theme
          └─ Main.qml  (imports Users.js for the account list)

Name and password typed, Enter
 └─ Main.qml: doLogin() → sddm.login(user, password, session)
     └─ the greeter sends "Login" to the sddm daemon
         └─ sddm-helper opens a PAM context, service "sddm"
              /etc/pam.d/sddm
               └─ include system-login
                   └─ include system-auth
                       └─ include sssd-arch
                           └─ pam_sss.so   (auth sufficient)
                               └─ sssd_pam → sssd_be → krb5_child
                                   └─ Kerberos request to the domain controller
                                       ├─ valid password: success, the chain stops (sufficient)
                                       ├─ "Preauthentication failed": wrong password
                                       └─ "credentials have been revoked": account locked/disabled
               └─ "account" phase: pam_sss checks authorization
                    (access_provider = simple: the user must be in simple_allow_groups)
               └─ "session" phase:
                    ├─ pam_mkhomedir.so: creates /home/<user> (copy of /etc/skel, mode 0700)
                    └─ pam_systemd: registers the session
     └─ sddm-helper starts the session:
          /usr/share/sddm/scripts/wayland-session "uwsm start -g -1 -e -D Hyprland hyprland.desktop"
```

For a **local** account, the journal first shows `pam_sss … User not known to the underlying authentication module`, then `pam_unix`: this is normal.

### 3.2 A command such as `id user`

```
id user
 └─ libc reads /etc/nsswitch.conf: "passwd: files systemd sss"
     ├─ files / systemd: local users
     └─ sss: libnss_sss → sssd_nss
          └─ SSSD cache, otherwise sssd_be → LDAP to a domain controller
               (authenticated with the machine key, /etc/krb5.keytab)
          └─ UID computed from the AD SID (ldap_id_mapping = True): around 100 million
```

**Important consequence**: if `sss` disappears from `nsswitch.conf`, SSSD runs and is online, but `id` answers "no such user", the allowed group no longer resolves and `pam_acct_mgmt` answers "User not known". This happened after an Omarchy update (`omarchy-settings`), hence `patch_nss` and the watching of that file.

### 3.3 Lock and unlock (`Super+L`)

```
Super+L
 └─ omarchy-shell (Quickshell), lock plugin: /usr/share/omarchy/shell/plugins/lock/Service.qml
     └─ locks the session (ext-session-lock)
     └─ when the password is typed: PamContext, config "omarchy-lock-password"
          └─ /etc/pam.d/omarchy-lock-password   (Omarchy's own file, owned by no package)
               ├─ auth  pam_sss.so  (ADDED)  → AD, domain accounts
               ├─ auth  pam_unix.so          → local passwords
               └─ account … system-local-login (+ pam_sss ADDED before it)
```

Without the fix, an AD account could log in but could not unlock the screen.

### 3.4 `sudo` and `su`

```
sudo <command>
 ├─ /etc/pam.d/sudo → system-auth → sssd-arch → pam_sss: checks the password
 └─ /etc/sudoers.d/50-ad-admins:  %Allowed-AD-Group ALL=(ALL:ALL) ALL
      The group is resolved by NSS (sss): the user must be a member in AD.

su - user
 └─ /etc/pam.d/su → include system-auth (modified) → sssd-arch → pam_sss
    (originally pam_unix only: the password never reached AD)
```

### 3.5 "Authorize running …" dialog (polkit)

```
omarchy-theme-set-browser-policy <color>     (at session start)
 ├─ local account: passwordless sudo rule (/etc/sudoers.d/omarchy-theme-browser)
 └─ AD account: no sudo rule → falls back to pkexec → polkit
      /etc/polkit-1/rules.d/50-ad-admins.rules: the group counts as "administrators"
      → the dialog asks for the AD user's own password (not the local account's)
```

This is not the disk decryption, despite what the message may suggest.

### 3.6 Re-application after an Omarchy update

```
Update of omarchy / omarchy-settings / pam / filesystem
 └─ pacman: hook /usr/share/libalpm/hooks/90-omarchy-ad.hook   (PostTransaction)
      └─ /usr/bin/omarchy-setup-ad reapply

A watched file is replaced (omarchy-lock-password or nsswitch.conf)
 └─ systemd: omarchy-ad-reapply.path  (PathChanged)
      └─ omarchy-ad-reapply.service
           └─ /usr/bin/omarchy-setup-ad reapply
```

`reapply` does nothing if `/etc/omarchy-ad.conf` does not exist (tool never configured). Otherwise it replays, idempotently: `patch_nss`, `patch_su`, `patch_lock`, then, if the login screen is enabled: rebuilds the theme, regenerates the SDDM Lua file, removes a re-created autologin.

### 3.7 Login screen account list

```
An AD account logs in for the first time
 └─ pam_mkhomedir creates /home/<user>              (the content of /home changes)
     └─ omarchy-ad-known-users.path: PathChanged=/home
         └─ omarchy-ad-known-users.service
              └─ /usr/lib/omarchy-ad/known-users
                   └─ rewrites Users.js (owners of the /home folders)
                        └─ the list contains the account the next time the screen opens
```

Why this mechanism: SDDM only lists accounts whose UID is between 1000 and 60000. AD accounts have a UID around 100 million, so they never appear in `userModel`. Enabling `enumerate = true` in SSSD would load the whole directory: not recommended.

---

## 4. The `omarchy-setup-ad` script

It must run as root: if started as a normal user, it re-launches itself with `sudo`.
Options are saved in `/etc/omarchy-ad.conf` (`DOMAIN`, `ALLOWED_GROUP`, `ADMIN_GROUP`, `KB_LAYOUT`, `LOGIN_MONITOR`, `LOGIN_ENABLED`, `SUDO_RULES`, `AUTOLOGIN_USER`), so `reapply` can replay the configuration without arguments.

### 4.1 Subcommands

| Command | Functions called |
|---|---|
| `join` | `cmd_join`: domain discovery, `realm join`, `sssd_set`, `ensure_mkhomedir`, `patch_nss`, `patch_su`, `patch_lock`, SSSD start, `sss_cache -E` |
| `sudo` | `cmd_sudo`: sudoers rule validated by `visudo -cf`, polkit rule |
| `login` | `cmd_login`: `legacy_cleanup`, `build_theme`, `zz-users.conf`, `write_sddm_lua`, `zz-wayland-login.conf`, `disable_autologin`, enables `omarchy-ad-known-users.path` |
| `all` | `join` + `sudo` + `login` |
| `reapply` | `cmd_reapply` (see 3.6) |
| `autologin` | `cmd_autologin`: `on <account>` writes `autologin.conf` (`write_autologin`); `off` moves it away (`disable_autologin`) |
| `status` | `cmd_status`: a series of `check` calls |
| `undo` | `cmd_undo`: removes what the tool added |

After each configuration command, `finalize` saves `/etc/omarchy-ad.conf` and enables `omarchy-ad-reapply.path`.

### 4.2 Main functions

| Function | Role |
|---|---|
| `sssd_set key value` | Sets a key in `[domain/<domain>]` of `sssd.conf` (awk), idempotently and without touching other sections. |
| `patch_nss` | Adds `sss` to the `passwd`, `group`, `shadow`, `gshadow` lines of `nsswitch.conf` if missing. |
| `patch_su` | Replaces the `pam_unix.so` lines of `/etc/pam.d/su` with `include system-auth`. |
| `patch_lock` | Adds `pam_sss` (auth and account) to `omarchy-lock-password` if missing; warns if the file has an unknown layout. |
| `ensure_mkhomedir` | Adds `pam_mkhomedir` to `system-login` **only if it is configured nowhere** (`sssd-arch` does it on Arch). |
| `cmd_sudo` | Writes the sudoers rule to a temporary file, validates it with `visudo -cf`, then installs it with mode `0440`. Spaces in the group name are escaped. |
| `detect_internal_panel` | Looks in `/sys/class/drm` for an `eDP-*`, `LVDS-*` or `DSI-*` output. |
| `login_monitor_rules` | Writes the monitor rules of the SDDM Lua file (see 5.3). |
| `write_sddm_lua` | Copies `/usr/share/sddm/hyprland.lua` and appends the keyboard and monitor rules. |
| `build_theme` | Copies the `omarchy` theme, overlays `Main.qml`, `user.png`, `Users.js`, then generates the account list. |
| `disable_autologin` | Moves `autologin.conf` to `/var/lib/omarchy-ad/autologin.conf.bak`. If the file was already moved by hand to `/root/autologin.conf.bak`, that copy is imported instead. |
| `restore_autologin` | Used by `undo`: puts the saved setting back; otherwise writes one for `--autologin-user`; otherwise warns. |
| `write_autologin` | Writes `autologin.conf` (`[Autologin] User=…`, `Session=omarchy.desktop`) after checking that the account exists. |
| `backup_once` | Saves the original version of a file in `/var/lib/omarchy-ad/backup/` (only once). |

### 4.3 `status` checks

| Check | Verifies |
|---|---|
| joined to the domain | `realm list` contains the domain |
| sssd is running | `systemctl is-active sssd` |
| nsswitch.conf uses sss | `sss` on `passwd`, `group`, `shadow` |
| sssd.conf not readable by everyone | no "other" permission |
| allowed group resolves | `getent group <group>` (fails if NSS is broken) |
| no debug_level left | no `debug_level` in `sssd.conf` |
| su accepts AD accounts | no `pam_unix` `required` left in `su` |
| lock screen PAM has pam_sss | `auth` and `account` lines present |
| sudo and polkit rules present | files present and `visudo -c` valid |
| login theme installed / selected, autologin disabled | theme, `zz-users.conf`, no `autologin.conf` |
| user list refresh active | `omarchy-ad-known-users.path` active |
| re-apply watcher active | `omarchy-ad-reapply.path` active |

---

## 5. Files

### 5.1 Files installed by the package

| File | Role |
|---|---|
| `/usr/bin/omarchy-setup-ad` | Main script |
| `/usr/lib/omarchy-ad/known-users` | Generates `Users.js` |
| `/usr/share/omarchy-ad/theme/{Main.qml,user.png,Users.js}` | Theme sources |
| `/usr/lib/systemd/system/omarchy-ad-known-users.{path,service}` | Updates the account list |
| `/usr/lib/systemd/system/omarchy-ad-reapply.{path,service}` | Re-application after file changes |
| `/usr/share/libalpm/hooks/90-omarchy-ad.hook` | Re-application after a pacman update |

Dependencies: `bash sssd krb5 samba realmd adcli sudo polkit sddm omarchy`.

### 5.2 Files created or modified on the workstation

| File | Action | Content / effect |
|---|---|---|
| `/etc/omarchy-ad.conf` | created | Saved options |
| `/var/lib/omarchy-ad/` | created | Backups (`backup/*.orig`, `autologin.conf.bak`) |
| `/etc/sssd/sssd.conf` | modified | `use_fully_qualified_names = False`, `fallback_homedir = /home/%u`, `access_provider = simple`, `simple_allow_groups = <group>` (no "other" permission) |
| `/etc/nsswitch.conf` | modified if needed | `sss` on `passwd`, `group`, `shadow`, `gshadow` |
| `/etc/pam.d/su` | modified | `include system-auth` |
| `/etc/pam.d/omarchy-lock-password` | modified | `auth sufficient pam_sss.so forward_pass` and `account [success=done default=ignore] pam_sss.so` |
| `/etc/pam.d/system-login` | modified only if `pam_mkhomedir` is missing everywhere | line tagged `# omarchy-ad` |
| `/etc/sudoers.d/50-ad-admins` | created (`0440`) | `%<group> ALL=(ALL:ALL) ALL` |
| `/etc/polkit-1/rules.d/50-ad-admins.rules` | created | `polkit.addAdminRule(...)` for `unix-group:<group>` |
| `/usr/share/sddm/themes/omarchy-users/` | created | Theme (copy of the `omarchy` theme + our files) |
| `/etc/sddm.conf.d/zz-users.conf` | created | `[Theme] Current=omarchy-users` |
| `/etc/sddm.conf.d/zz-wayland-login.conf` | created | `[Wayland] CompositorCommand=start-hyprland -- --config /etc/sddm-hyprland.lua` |
| `/etc/sddm-hyprland.lua` | created | Greeter Hyprland config: keyboard and monitors |
| `/etc/sddm.conf.d/autologin.conf` | moved | As long as it exists, SDDM logs an account in without showing the login screen |

The `zz-` prefix makes these files load last: they override `10-theme.conf` and `10-wayland.conf`.

### 5.3 `/etc/sddm-hyprland.lua`

Copy of `/usr/share/sddm/hyprland.lua`, extended:

```lua
hl.config({ input = { kb_layout = "fr" } })
hl.monitor({ output = "", disabled = true })
hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = 1 })
```

- **Keyboard**: `--kb-layout`, otherwise `XKBLAYOUT` from `/etc/vconsole.conf`, otherwise `us`. The greeter does not read the user's configuration.
- **Monitors**: the first rule (`output = ""`) applies to any output without its own rule and disables it. The second keeps the built-in panel. The number or names of external monitors therefore do not matter. Values of `--login-monitor`:
  - `auto` (default): built-in panel detected; with no built-in panel (desktop), no rule is written;
  - `all`: no rule, all monitors stay on;
  - a name (`DP-1`): only that monitor.

  The syntax was validated with `Hyprland --verify-config`, but **the real behavior of the catch-all rule on the login screen has not been proven on several configurations**: on a black screen, use `--login-monitor all`.

### 5.4 The `omarchy-users` theme

- `Main.qml`: clock and date, logo, user field (icon, chevron and list; "+ New user" clears the field), password field (padlock, eye or F2 key to show the password), "Invalid username or password" and "Caps Lock is on" messages, machine name, Restart and Shut down buttons, "Signing in as …" loading screen (the first login is slow: home creation).
- `user.png`: user icon, same size as the padlock.
- `Users.js`: account list (`var list = ["a","b"]`), generated.
- The other files (`logo.png`, `entry.png`, `lock.png`, `bullet.png`) come from the Omarchy theme.

Risk-free test, from the graphical session (Enter does not really log in in test mode):
```bash
sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/omarchy-users
```

### 5.5 `sssd.conf`

```ini
[sssd]
domains = example.corp
config_file_version = 2
services = nss, pam

[domain/example.corp]
default_shell = /bin/bash
krb5_store_password_if_offline = True
cache_credentials = True
krb5_realm = EXAMPLE.CORP
realmd_tags = manages-system joined-with-adcli
id_provider = ad
fallback_homedir = /home/%u
ad_domain = example.corp
use_fully_qualified_names = False
ldap_id_mapping = True
access_provider = simple
simple_allow_groups = Allowed-AD-Group
```

| Line | Role |
|---|---|
| `id_provider = ad` | Identities read from AD |
| `krb5_realm`, `ad_domain` | Kerberos realm and domain |
| `ldap_id_mapping = True` | UIDs computed from the SID (hence very high UIDs) |
| `cache_credentials`, `krb5_store_password_if_offline` | Offline login with the last known password |
| `use_fully_qualified_names = False` | Log in as `john` instead of `john@example.corp` |
| `fallback_homedir = /home/%u` | Home `/home/john` (default is `/home/%u@%d`) |
| `access_provider = simple` | Authorization from a local list |
| `simple_allow_groups` | Groups allowed to open a session; **applies to all AD accounts**, not to local accounts |

With short names, two accounts from different domains could clash: not an issue with a single domain.
`sssd.conf` must not be world-readable, otherwise SSSD refuses to start.

### 5.6 PAM on Arch after `realm join`

- `/etc/pam.d/system-auth`: `auth`, `password`, `session` include `sssd-arch` at the top.
- `/etc/pam.d/sssd-arch`:
  ```
  auth sufficient pam_sss.so forward_pass
  password sufficient pam_sss.so use_authtok
  session required pam_mkhomedir.so skel=/etc/skel/ umask=0077
  session optional pam_sss.so
  ```
  `sufficient`: if the AD password is valid, the chain stops; otherwise `pam_unix` tries the local account.

---

## 6. Joining the domain, step by step (what `join` automates)

Differences from Debian:

| Step | Debian 11 | Omarchy / Arch |
|---|---|---|
| Packages | `realmd sssd sssd-tools libnss-sss libpam-sss adcli samba-common-bin oddjob oddjob-mkhomedir packagekit` | `sssd krb5 samba` (pacman), `realmd adcli` (AUR) |
| Home creation | `pam-auth-update` + `/usr/share/pam-configs/mkhomedir` | Already in `sssd-arch` |
| PAM / NSS | `pam-auth-update` | `realm join` (realmd's Arch helper script) |
| Login screen | GDM / LightDM | SDDM, single-field Omarchy theme (replaced here) |
| Lock screen | depends on the desktop | `omarchy-lock-password` |
| DNS | `/etc/resolv.conf` | `nmcli` / `systemd-resolved` (the file is rewritten) |

Equivalent manual steps:

```bash
yay -S --needed realmd adcli
sudo hostnamectl set-hostname WS01.example.corp
sudo timedatectl set-ntp true
realm discover example.corp
sudo realm join -v -U join.account example.corp
realm list
```

- `-U` is an **AD account** allowed to join machines, not the Linux user.
- If the computer account already exists: `Found computer account for WS01$`, it is reused.
- For a specific OU: `--computer-ou="OU=...,DC=example,DC=corp"`.
- Normal messages: `Encryption type [1] / [3] not permitted` (old DES algorithms ignored), `Flushing name caches failed`.

`realm join` creates `/etc/krb5.keytab`, generates `sssd.conf`, enables `sssd`, plugs SSSD into PAM and NSS.

### DNS

DNS must point to a domain controller:
```bash
resolvectl status
nmcli connection modify "<connection>" ipv4.dns "<DC_IP>" ipv4.dns-search "example.corp"
nmcli connection up "<connection>"
```

### Allowing users (`realm permit` equivalents)

```bash
sudo realm permit user@example.corp
sudo realm permit -g "Allowed-AD-Group"
sudo realm permit 'Domain Users' 'admin users'
sudo realm permit --all        # not recommended
sudo realm deny --all
```
`realm permit` edits `simple_allow_users` / `simple_allow_groups` in `sssd.conf`: the tool writes the same thing with `--allowed-group`.

### sudo

Always create a file in `/etc/sudoers.d/` (never edit `/etc/sudoers` directly) and validate with `visudo -c`:
```
john                    ALL=(ALL) ALL      # one user
%Allowed-AD-Group       ALL=(ALL) ALL      # one group
%domain\ users          ALL=(ALL) ALL      # not recommended: the whole domain becomes root
```
With `use_fully_qualified_names = True`, you would have to write `john@example.corp`.
**A group rather than the whole domain**: otherwise every new account becomes an administrator of the machine.

---

## 7. Tests and troubleshooting

### 7.1 Tests

```bash
sudo omarchy-setup-ad status
realm list                                        # configured: kerberos-member
systemctl status sssd --no-pager                  # active (running)
id john                                           # AD UID and groups
sudo sssctl domain-status example.corp            # Online status: Online
sudo sssctl user-checks john -a acct -s sddm      # the account is authorized
kinit john@EXAMPLE.CORP                           # one attempt only; realm in uppercase
klist; kdestroy
```

- `kinit` asks for the password and succeeds: account, password and Kerberos are fine.
- `kinit` answers `credentials have been revoked` **before** asking for the password: the account is locked, disabled or expired on the queried controller. These attempts do not count as wrong passwords.
- Real login test without the graphical interface: `Ctrl+Alt+F3` (text terminal), log in with the AD account; go back with `Ctrl+Alt+F1` or `F2`.

### 7.2 Common symptoms

| Symptom | Cause | Fix |
|---|---|---|
| `target not found: realmd` | Not in the official repositories | `yay -S realmd adcli` |
| `realm discover` finds nothing | DNS does not point to AD | Fix DNS (6) |
| `Clock skew too great` | Clock drift > 5 min | `timedatectl set-ntp true` |
| `id`: "no such user" while SSSD is online and `sssctl user-checks` finds the account | `sss` missing from `nsswitch.conf` (Omarchy update) | `sudo omarchy-setup-ad reapply` |
| `sss_cache: Can't access config.ldb` | SSSD stopped | `systemctl start sssd`, then `sss_cache -E` |
| `su - user`: Authentication failure while `kinit` works | `/etc/pam.d/su` without `system-auth` | `reapply` |
| 2nd password screen, or AD account cannot unlock | `omarchy-lock-password` without `pam_sss` | `reapply` |
| `kinit`: `credentials have been revoked` | Account locked, disabled or expired; unlock not yet replicated to this DC | Have IT check `lockoutTime`, `userAccountControl`, `accountExpires`. Do not chain password attempts |
| `kinit`: `Preauthentication failed` | Wrong password (or keyboard) | Check the typing (F2 shows the password on the login screen) |
| No user choice at login | Autologin active, or original theme | `omarchy-setup-ad login` |
| AD account missing from the list | Never logged in yet | Type the name the first time |
| `sudo: not allowed` | No rule for its group, or NSS broken | `omarchy-setup-ad sudo`, `status` |
| "Authorize running omarchy-theme-set-browser-policy" dialog | No sudo rule for the AD account, falls back to `pkexec` | polkit rule (3.5) |
| Slow first login | Home and Omarchy configuration creation | Normal (loading screen) |
| `Dynamic DNS update failed` in SSSD logs | SSSD is not allowed to update AD's DNS | Harmless; to silence it: `dyndns_update = false` |
| Black screen at login | Monitor rule or theme | `Ctrl+Alt+F3`, then `--login-monitor all`, or `undo` |

### 7.3 SSSD debug (temporary)

Add `debug_level = 6` under `[domain/example.corp]` (and a `[pam]` section), then `sudo systemctl restart sssd`. Logs in `/var/log/sssd/`. **Remove it afterwards** (it slows things down and grows the logs); `status` reports a forgotten `debug_level`.

---

## 8. Rolling back

```bash
sudo omarchy-setup-ad undo --yes            # theme, PAM (lock, su), sudo/polkit, autologin restored from the saved setting
sudo omarchy-setup-ad undo --yes --autologin-user <local-account>   # same, restoring autologin for that account if nothing was saved
sudo omarchy-setup-ad undo --leave --yes    # same, and leaves the domain (realm leave)
sudo systemctl restart sddm                 # closes the current graphical session
```

`undo` does not modify `sssd.conf` or `nsswitch.conf` (they are needed for AD login itself). To go back to the original theme only: `sudo rm -f /etc/sddm.conf.d/zz-users.conf` then `sudo systemctl restart sddm`.

From a text terminal (`Ctrl+Alt+F3`, local account), if the login screen is unusable: `sudo omarchy-setup-ad undo --yes`.

Renaming a machine after a mistake: `realm leave`, `hostnamectl set-hostname <name>`, fix `/etc/hosts`, reboot, then join again.

---

## 9. Security and points of attention

- **AD lockout**: do not chain wrong passwords on an AD account (AD will lock it).
- **sudo**: the whole administrator group administers the machine. Validate with your IT team.
- **Restriction**: only members of the allowed group can log in with AD. To add more: `--allowed-group "g1,g2"`.
- **Fallback account**: keep a local account.
- **LUKS**: the disk decryption password is independent; change it with `cryptsetup luksChangeKey <partition>`. Never use `luksFormat` (it wipes the disk).
- **Autologin disabled**: every boot asks for a name and a password. `omarchy-setup-ad autologin on <account>` / `off` switches it; `reapply` leaves it alone while it is on.
- **Copied theme**: `omarchy-users` does not follow changes to the original Omarchy theme.
- **Updates**: after a big Omarchy update, run `sudo omarchy-setup-ad status`.
- **Not proven**: automatic `reapply` across several Omarchy versions, the catch-all monitor rule on several monitor setups, `join` on a workstation never joined with this package.
