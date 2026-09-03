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
│   ├── addkey.sh         # append config.sh's SSH keys to local authorized_keys
│   ├── riexec.sh         # open an interactive ssh session to one host
│   └── test_tui.sh       # verify dialog/ncurses works on a remote host
├── rscripts/             # remote payloads (executed on the remote host)
│   ├── proxy.bash        # set apt + bashrc proxy
│   ├── apt.bash          # apt-get update + upgrade
│   ├── snapstrap.bash    # set snap proxy
│   ├── k8strap.bash      # install the k8s snap through the local proxy
│   ├── addkey.bash       # append $PASSVAR to remote authorized_keys
│   ├── dialog.bash       # dialog connection test
│   └── reboot.bash       # reboot the remote host
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

## Running scripts remotely

`rexec.sh` ships an rscript to a remote host and executes it:

```bash
bin/rexec.sh <host>           <rscript>
bin/rexec.sh <host-list-file> <rscript>
```

- Every variable defined in `config.sh` (`REMOTE_PROXY_IP`, `SNAP_PROXY_IP`,
  `SSHKEYS`, …) is exported to the remote shell, so rscripts can use them.
- If the first argument is an existing file, it is treated as a host list
  (`rhosts/*.txt`); blank lines and `#` comments are skipped.

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

# Reboot after strapping
bin/rexec.sh rhosts/list1.txt rscripts/reboot.bash
```

Typical fresh-host bring-up order: proxy → apt → snapstrap → k8strap →
addkey → reboot.

## Interactive helpers

```bash
bin/riexec.sh <host> [<ssh-args...>]      # interactive ssh to one host
bin/test_tui.sh <host>                    # dialog/ncurses smoke test on remote
```

## Configuration (config.sh)

| Variable            | Used by                        |
|---------------------|--------------------------------|
| `REMOTE_PROXY_IP` / `REMOTE_PROXY_PORT`   | `rscripts/proxy.bash` (on-host proxy) |
| `SNAP_PROXY_IP` / `SNAP_PROXY_PORT`       | `rscripts/snapstrap.bash` (local snap proxy) |
| `K8S_PROXY_IP` / `K8S_PROXY_PORT`         | `rscripts/k8strap.bash` (local proxy for the snap install) |
| `SSHKEYS`                 | `bin/addkey.sh` (local) and `rscripts/addkey.bash` (remote) |

`config.sh` is generated from `config.sh.example` by `bin/configstrap.sh`
and is git-ignored; keep secrets out of the example.
