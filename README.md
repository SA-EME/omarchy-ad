# omarchy-ad

Join an **Omarchy** (Arch Linux) workstation to Active Directory and enable a multi-user login screen, with one command.

What the package installs:

- `omarchy-setup-ad`: join and configuration command (`join`, `sudo`, `login`, `all`, `reapply`, `status`, `undo`);
- an SDDM theme, `omarchy-users` (user name field, account list, show-password eye, loading screen);
- the PAM fix for Omarchy's lock screen (`Super+L`) so AD accounts can unlock it;
- **automatic re-application** after an Omarchy update (pacman hook + systemd unit).

Detailed documentation (how it works, files, call chains, troubleshooting): [`doc/how-it-works.md`](doc/how-it-works.md).

## Requirements

| Requirement | Detail |
|---|---|
| Omarchy 4 | Arch Linux, SDDM, Hyprland |
| DNS | The workstation resolves the domain (DNS points to a domain controller) |
| Clock | Less than 5 minutes of drift (Kerberos) |
| Join account | An AD account allowed to join computers (`--join-user`) |
| Local fallback account | Keep one (login without AD) |
| Host name | The short name matches the computer account in AD |

The host name must be an FQDN: `WORKSTATION-NAME.example.corp`.

## Installation (new workstation)

```bash
# 1. AUR dependencies (not in the official repositories)
yay -S --needed realmd adcli

# 2. Host name
sudo hostnamectl set-hostname WORKSTATION-NAME.example.corp

# 3. Build and install the package
git clone https://github.com/SA-EME/omarchy-ad.git omarchy-ad && cd omarchy-ad
makepkg -si

# 4. Join AD and enable the login screen
sudo omarchy-setup-ad all \
  --domain example.corp \
  --join-user join.account \
  --allowed-group "Allowed-AD-Group"

# 5. Check
sudo omarchy-setup-ad status
```

The command asks for the join account's password. It does not store it anywhere.
If the workstation is already joined to the domain, the join is skipped (`Already joined`).

Before rebooting: everything must show `[ ok ]` in `status`, and `id some-ad-account` must answer.
Keep a rescue terminal available (`Ctrl+Alt+F3`, log in with the local account).

## Commands

| Command | Purpose |
|---|---|
| `omarchy-setup-ad join` | Join the domain; SSSD (short names, `/home/%u`, allowed group), `su`, `nsswitch`, lock screen |
| `omarchy-setup-ad sudo` | sudo and polkit rules for the administrator group |
| `omarchy-setup-ad login` | Multi-user login screen (theme, autologin off, keyboard, monitors) |
| `omarchy-setup-ad all` | `join` + `sudo` + `login` |
| `omarchy-setup-ad reapply` | Re-apply what an Omarchy update may have overwritten (run automatically) |
| `omarchy-setup-ad autologin on <account>` | Turn automatic login on for one account (the login screen is then skipped) |
| `omarchy-setup-ad autologin off` | Turn automatic login back off (login screen with user choice) |
| `omarchy-setup-ad status` | Check everything |
| `omarchy-setup-ad undo [--leave]` | Remove what the tool added (`--leave` also leaves the domain) |

### Options

| Option | Purpose |
|---|---|
| `--domain <dns-name>` | AD domain (saved in `/etc/omarchy-ad.conf`) |
| `--join-user <account>` | AD join account (asked if omitted) |
| `--allowed-group <group[,…]>` | AD group(s) allowed to log in (`simple_allow_groups`) |
| `--admin-group <group>` | AD group that gets sudo (default: the allowed group) |
| `--no-sudo-rules` | Do not create sudo or polkit rules |
| `--kb-layout <layout>` | Login screen keyboard layout (default: the system one, `/etc/vconsole.conf`) |
| `--login-monitor <auto\|all\|output>` | Login screen monitors (see below) |
| `--leave` | With `undo`: also leave the domain |
| `--autologin-user <account>` | With `undo`: restore automatic login for this account when no backup of the old setting exists |
| `--yes` | Do not ask for confirmation |

### Monitors at the login screen

By default (`auto`), **only the laptop's built-in panel** (`eDP-*`, `LVDS-*`, `DSI-*`) stays on at the login screen. Every other monitor is turned off by a catch-all rule, whatever their number or names. They come back with the user's session (each user's `~/.config/hypr/monitors.lua` applies).

- Desktop without a built-in panel: no rule is written, all monitors stay on.
- Keep all monitors: `--login-monitor all`.
- Force a specific monitor: `--login-monitor DP-1`.

## FAQ

**Does it work on any workstation?**
Yes, on an Omarchy 4 machine. No machine-specific value is hard-coded: domain, groups, keyboard and monitors are options or detected.

**Do I have to create the computer account in AD first?**
Not required: `realm join` reuses an existing account, or creates one if the join account is allowed to. To place it in a specific OU, run `realm join --computer-ou=…` by hand before `omarchy-setup-ad all`. Depending on your AD policy, your IT team may prefer to pre-create the account.

**Is the `--allowed-group` a computer group?**
No: it is a **user** group. It decides *who can open a session* on the workstation. Membership of the computer in a workstation group (for example WORKSTATION) is handled in AD, not by this tool.

**What happens after an Omarchy update?**
A pacman hook and a systemd unit run `omarchy-setup-ad reapply`. Then check with `sudo omarchy-setup-ad status`.

## Automatic login

`login` turns automatic login off so the login screen can show the user choice. The previous setting is saved in `/var/lib/omarchy-ad/autologin.conf.bak` (a setting you had already moved to `/root/autologin.conf.bak` is imported too).

```bash
sudo omarchy-setup-ad autologin on <account>   # skip the login screen for this account
sudo omarchy-setup-ad autologin off            # back to the login screen
```

`reapply` leaves automatic login alone while it is on. With the disk encrypted, anyone who knows the disk password then starts that account's session.

## Disk encryption password (LUKS)

The password asked at boot, before Linux starts, unlocks the encrypted disk (LUKS). It belongs to no user and has nothing to do with AD. **This tool never touches it.**

Making it the same as a local account's password (the stock Omarchy behavior: one password for everything) is possible with `cryptsetup luksChangeKey`, but it is deliberately **not automated** here:

- it means handling passwords in clear text and changing the disk encryption: a change that stops half way can lose data (Omarchy's own multi-user work, PR #16100, is very careful about this: recovery journal, tests on real LUKS volumes);
- it is a security decision for each workstation.

If you want to change it, do it by hand, afterwards:

```bash
sudo cryptsetup luksChangeKey /dev/<luks-partition>   # old password, then the new one twice
sudo cryptsetup luksDump /dev/<luks-partition> | grep -i keyslot
```

You type the passwords yourself and nothing is stored. Keep the old password until you have confirmed a reboot works. Never use `luksFormat`: it wipes the disk.

From a security point of view, a disk password **different** from any account password is safer. Choose a strong one. With automatic login on, anyone who knows the disk password also starts that account's session.

## Home directories after `undo`

`undo` removes the configuration, **not the data**. The home directories of AD accounts that logged in (`/home/<account>`) stay in place:

- deleting them automatically would be destructive and irreversible;
- they are not local accounts: they belong to AD UIDs, so they are inactive once AD is no longer configured, and usable again with their files as soon as the tool is set up again;
- they do no harm.

To delete one on purpose, do it by hand, after checking that nobody needs the files (this is final):

```bash
sudo rm -rf /home/<account>
```

## Rolling back

```bash
sudo omarchy-setup-ad undo --yes          # removes theme, PAM, sudo changes; restores autologin from the saved setting
sudo omarchy-setup-ad undo --yes --autologin-user <local-account>   # same, and restores autologin for that account if nothing was saved
sudo omarchy-setup-ad undo --leave --yes  # same, and leaves the domain
sudo systemctl restart sddm               # closes the current graphical session
```

## Limitations

- The `omarchy-users` theme is a copy: it does not follow changes to the original Omarchy theme.
- An AD account appears in the login screen list only **after its first login**; the first time, type the name.
- Automatic re-application after an update covers the cases observed (lock screen PAM, `nsswitch.conf`, autologin); it has not been proven on every version.
- The encrypted disk (LUKS) has its own password, independent of AD (see above).
- `undo` keeps users' home directories.

## Repository contents

```
omarchy-setup-ad                  main script (installed in /usr/bin)
known-users                       generates the theme's account list
omarchy-ad-known-users.{path,service}   updates the list when /home changes
omarchy-ad-reapply.{path,service}       re-applies after Omarchy changes files
omarchy-ad.hook                   pacman hook (after omarchy, pam, filesystem updates)
Main.qml, user.png, Users.js      omarchy-users SDDM theme
PKGBUILD                          package build
doc/how-it-works.md               detailed documentation
```
