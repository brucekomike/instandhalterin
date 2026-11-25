# instandhalterin

Remote strapping toolbox: bootstrap fresh Ubuntu worker machines from a
single control host. It pushes proxy settings, apt upgrades, snap
configuration, SSH keys, and Kubernetes installs to one host or a whole
fleet of hosts over plain `ssh`, with no agent on the remote side.

Everything lives in [`ubuntu/`](ubuntu/); run scripts as `ubuntu/bin/<name>.sh`
from the `ubuntu/` directory.

## Layout

```
ubuntu/
├── config.sh.example     # template for the active configuration
├── config.sh             # active configuration (generated, git-ignored)
├── bin/                  # local driver scripts (run on the control host)
│   ├── configstrap.sh    # create config.sh from the example
│   ├── rexec.sh          # run an rscript on a remote host (or host list)
│   ├── backup-hosts.sh   # resolve host names from a backup-scripts conf/ tree
│   ├── addkey.sh         # append config.sh's SSH keys to local authorized_keys
│   ├── riexec.sh         # open an interactive ssh session to one host
│   └── test_tui.sh       # verify dialog/ncurses works on a remote host
├── rscripts/             # remote payloads (executed on the remote host)
│   ├── apt-proxy.bash     # write the apt proxy config
│   ├── pkg.bash           # apt-get update + upgrade + autoremove
│   ├── snapstrap.bash     # set snap proxy
│   ├── k8strap.bash       # install the k8s snap through the local proxy
│   ├── addkey.bash        # append $SSHKEYS to the operator's authorized_keys
│   ├── om-user.bash       # create $MAINT_USER with sudo + its own keys
│   ├── nisudo.bash          # grant the connecting user NOPASSWD sudo
│   ├── dialog.bash        # dialog connection test
│   └── reboot.bash        # reboot the remote host
├── rcommands/            # one-off remote commands (no env setup)
│   └── k8strap.bash      # plain `snap install k8s --classic`
└── rhosts/               # host lists, one hostname per line (# comments ok)
    └── list1.txt
```

## Quick start

```bash
cd ubuntu/

# 1. Create the active configuration (only done once)
bin/configstrap.sh

# 2. Edit config.sh: proxy IPs/ports and your real SSH keys

# 3. Make the control host reachable (optional, for your own access)
bin/addkey.sh                        # keys from config.sh -> local ~/.ssh/authorized_keys
```

### Where the configuration lives

Each checkout reads its config dir in this order:

1. `$IH_CONFIG` (explicit override),
2. `.config/ihconfig` **beside the checkout** (`<checkout>/../.config/ihconfig`),
3. legacy: files installed inside `ubuntu/` itself.

The config dir holds `config.sh`, `rhosts/*.txt` and `tests/host-identifiers.local`.
It is normally a symlink into a private per-fleet config repo, so one tool repo
serves several fleets: each checkout's `ihconfig` link selects that fleet's
folder, and `readlink` shows which one. The public repo never carries the config
itself — only `config.sh.example` and the `rhosts/*.example` shapes.

## Running scripts remotely

`rexec.sh` ships an rscript to a remote host and executes it:

```bash
bin/rexec.sh <host>           <rscript>
bin/rexec.sh <host-list-file> <rscript>
bin/rexec.sh @<group>         <rscript>   # hosts from backup-scripts conf/<group>/
```

- Every variable defined in `config.sh` (`REMOTE_PROXY_IP`, `SNAP_PROXY_IP`,
  `SSHKEYS`, …) is exported to the remote shell, so rscripts can use them.
- If the first argument is an existing file, it is treated as a host list
  (`rhosts/*.txt`); blank lines and `#` comments are skipped. The last line
  does not need a trailing newline.
- `@<group>` (or a conf group directory) resolves its hosts from the
  backup-scripts `conf/<group>/*.conf` **file names** — the backup tool's rule
  that the filename IS the ssh target makes its scope a host list this tool
  can read. One membership source for deployment runs and backups; no second
  list to keep aligned. `BACKUP_CONF` in `config.sh` points at that `conf/`
  directory. `*.conf.disabled` hosts are reported as comments, never executed.
  The `@` marker is required because a group name can collide with a host
  alias; a bare name always stays a single host. `riexec.sh` accepts `@group`
  in script mode the same way.

Examples:

```bash
# Route apt/snap traffic through the on-host proxy
bin/rexec.sh rhosts/list1.txt rscripts/proxy.bash

# Freshen the fleet
bin/rexec.sh rhosts/list1.txt rscripts/apt.bash

# Install the k8s snap (needs the local snap proxy from config.sh running)
bin/rexec.sh rhosts/list1.txt rscripts/k8strap.bash

# Distribute your SSH key to every worker
bin/rexec.sh rhosts/list1.txt rscripts/addkey.bash

# Create the sudo maintenance user on every worker (idempotent)
bin/rexec.sh rhosts/list1.txt rscripts/om-user.bash

# Give the connecting user passwordless sudo (run interactively when prompted)
bin/riexec.sh <host|host-list-file> rscripts/nisudo.bash

# Reboot after strapping
bin/rexec.sh rhosts/list1.txt rscripts/reboot.bash
```

Typical fresh-host bring-up order: proxy → apt → snapstrap → k8strap →
addkey → om-user → reboot.

`nisudo.bash` skips users that already have a `NOPASSWD`
sudo rule. Otherwise, the connecting user must already be allowed to use
`sudo`; run it with a terminal (`ssh -t`) if sudo needs a password prompt.
It grants `NOPASSWD:ALL` through a validated `/etc/sudoers.d/` drop-in and
will not overwrite an existing file at that path.

## Interactive helpers

```bash
bin/riexec.sh <host|host-list-file> <rscript> [<script-args...>] # run payload with a TTY
bin/riexec.sh <host> [<ssh-args...>]      # interactive ssh passthrough
bin/test_tui.sh <host>                    # dialog/ncurses smoke test on remote
```

In script mode, `riexec.sh` stages the payload before opening the TTY, so
interactive commands such as `sudo` can prompt for a password. Host-list
entries run sequentially and may each require interaction.

## Configuration (config.sh)

| Variable            | Used by                        |
|---------------------|--------------------------------|
| `REMOTE_PROXY_IP` / `REMOTE_PROXY_PORT`   | `rscripts/proxy.bash` (on-host proxy) |
| `SNAP_PROXY_IP` / `SNAP_PROXY_PORT`       | `rscripts/snapstrap.bash` (local snap proxy) |
| `K8S_PROXY_IP` / `K8S_PROXY_PORT`         | `rscripts/k8strap.bash` (local proxy for the snap install) |
| `SSHKEYS`                 | `bin/addkey.sh` (local) and `rscripts/addkey.bash` (remote) |
| `MAINT_USER`              | `rscripts/om-user.bash` (user to create; default `maintainer`) |
| `MAINT_SSHKEYS`           | `rscripts/om-user.bash` (keys for that user; falls back to `SSHKEYS`) |

Only the variables listed in the remote-execution scripts' allowlists (`APT_PROXY`,
`DEFAULT_PROXY`, `SSHKEYS`, `MAINT_USER`, `MAINT_SSHKEYS`) are exported to the
remote shell — when an rscript reads a new `config.sh` variable, add it there
too, otherwise it arrives empty.

`config.sh` is generated from `config.sh.example` by `bin/configstrap.sh`
and is git-ignored; keep secrets out of the example.
