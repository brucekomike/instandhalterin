# One host inventory: unifying the inventories that describe the same fleet

Status: **proposal, partially superseded.** Written after a read-only census of every SSH alias in
use, followed by an append-only key run and a drift report. Owner decision 2026-11-25: membership is
shared by reading the backup tool's per-host conf file names directly (`bin/backup-hosts.sh`,
`@group` in rexec/riexec) instead of building a separate registry; the per-host record registry
below remains the reference design for the checks that direct reading does not cover (reverse
coverage, key convergence, login_user policy).

**This document carries no site data on purpose.** This repository is public and ships the
*shape* of a fleet; the addresses, alias names and instance identifiers of a real deployment
live in the private inventory of record. Concrete values that motivated each rule are kept out
of the public tree deliberately — the first draft of this document contained them, which is the
incident §10 describes. Where a rule needs an example, the example is a placeholder.

---

## 1. The problem

Four inventories described the same machines and agreed only because a human kept them aligned
by hand:

| # | Inventory | Shape | Was authoritative for |
|---|---|---|---|
| a | `conf/<group>/<alias>.conf` in the backup tool | one file per host; **filename IS the ssh target** | what a backup collects |
| b | `ubuntu/rhosts/*.txt` in this repo | one alias per line, per group | which hosts a fleet command hits |
| c | `~/.ssh/config.d/*` on the control host | `Host` blocks, **including wildcards** | how a host is actually reached |
| d | the docs of record | prose tables, and the declared source of the operator key list | the human-readable record |

Four failure classes fell out of that split, all measured rather than hypothetical:

1. **Configured hosts in no group at all.** The ssh config declared materially more explicit
   `Host` names than the group lists covered. The unlisted remainder included active
   **root-login** machines, and some of those had no maintenance account at all. They were
   invisible to the fleet run because the run built its target set *from the group lists* —
   the circularity itself, not bad luck.
2. **Hosts that inherited reachability from a wildcard.** A block like `Host <prefix>-*` gives
   any matching name a jump host, a user and an identity file without that name appearing in
   any list. Such a host is reachable, usable, and unmanaged.
3. **A recently provisioned set in a worse state.** A datastore pair and a cluster sat at
   **1 of N** operator keys with **no maintenance user**, while every grouped host had both.
   Standing practice says every new machine gets key bootstrap plus the maintenance account;
   the omission is visible directly in the key state, and nothing checked for it.
4. **The key list had no versioned home.** The active configuration (mode 600, gitignored)
   held the only copy of the fleet's authorized keys, and its own declared upstream — a table
   in the docs — disagreed with it. The newest key existed on **zero** hosts.

## 2. Proposal: one registry of per-host records; everyone else derives

**Source of truth: one file per host, keyed by SSH alias**, in a private inventory of record.

Why a registry rather than crowning one of the four: the four answer different questions, but
only one of them — membership — is duplicated four times. Make membership a property of a host
record and everything else becomes either a projection or an assertion.

Why one file per host: it matches the shape the backup tool already proved (`<alias>.conf`,
filename = target), keeps diffs per-host, and makes "what changed about this machine" one
`git log` query.

Field set (only `alias` and `group` are required):

```
alias=<ssh alias>
group=<role name>            # NOT a cloud object name — see §9
nat_entry=<entry EIP>
reaches=<network role>
login_user=<ubuntu|root|…>   # a policy field, see §5
host_kind=<vm|bmi|container>
key_class=<operator|operator+machine>
backup=<yes|no>
note=<one line>
```

Consumers then become derived or validated, never hand-maintained:

- **group lists → generated.** `bin/inventory-rgroups.sh` (in this branch) emits one file per
  group by selecting on `group=`. Hand-editing membership stops being a thing.
- **ssh config → validated only.** The operator owns those files; a checker asserts each
  registry alias resolves to an explicit `Host` block with the expected user/port/jump, and
  that no reachable alias exists *only* via a wildcard.
- **backup scope → validated only.** Its per-host files stay where they are; see §8.
- **docs tables → generated.** So the record cannot disagree with the tool.

## 3. The key list needs the same treatment

The active config copied the key list *by hand* out of a Markdown table. Fix: two tracked
lists in the private inventory — operator identities, and machine/service keys with their
scope — and the generated config sources them instead of duplicating them:

```bash
SSHKEYS="$(cat "$here/keys/operators.keys")"
```

The generated config stays gitignored; the lists become versioned, reviewable and restorable.
Whether publishing public keys is safe is a separate question from whether publishing a
*fleet* is — see §10.

## 4. What this branch actually ships

| Piece | File | Purpose |
|---|---|---|
| generator | `ubuntu/bin/inventory-rgroups.sh` | registry → `rhosts/<group>.txt`; `--check` reports drift |
| shape templates | `ubuntu/rhosts/*.example` | the committed contract for a group file |
| ignore guard | `ubuntu/rhosts/.gitignore` | real lists ignored; `!*.example` re-admits the templates |
| **gate** | `ubuntu/tests/no-host-identifiers_test.sh` | fails anything that carries site data |
| revocation | `ubuntu/rscripts/prune-keys.bash` | fingerprint-scoped key removal, dry-run by default |
| opt-in dedup | `ubuntu/rscripts/addkey.bash` | appending a key no longer rewrites the file |

Two of these exist because of a defect the design has to own. `inventory-rgroups.sh`
**refuses to write a path that git tracks**, and the gate **fails when a per-host list is
tracked**. The same invariant is encoded in two places on purpose, because an invariant stated
once in a comment is exactly what failed.

## 5. `login_user` is a policy field, not an accident

The census split hosts by the account the operator actually logs in as. The classes behave
differently and must not be batched together:

- **Ordinary-user hosts** are safe to batch: key append is idempotent, a second account (the
  maintenance user) exists as a fallback path, and a mistake costs one host.
- **root-login hosts** have no fallback identity — the operator *is* root, so a write to
  `$HOME/.ssh/authorized_keys` there is a write to root's file.
- **The jump host** is the worst case: it is the sole entry for its whole group, so a bad
  write costs the group, not a host.

Adopted rule for root and jump hosts: **one host at a time, keep a live session open, and
prove the new key authenticates from a second connection before closing anything.** Encoding
`login_user=` in the registry is what lets a checker enforce different procedures per class
instead of assuming fleet-uniformity. A batch that "succeeded on every host" is not evidence
the risky class was handled — it may be evidence the risky class was never distinguished.

Also found: some aliases referenced identity files that do not exist on the control host. They
authenticated only because `IdentitiesOnly` was unset, so the agent key was offered anyway.
Dead config lines that become hard failures the moment anyone sets that option — the kind of
latent breakage a registry should record explicitly rather than leave to a wildcard's defaults.

## 6. Fingerprints are the only stable identifier

Three consequences of measuring keys properly:

- **Comments are not identifiers.** One operator's key appeared under the *same comment* with
  **two different fingerprints**: a rotation changed the key material and both lines stayed
  live, on most of the fleet. Anything keyed on a comment silently undercounts. The fingerprint
  is the only stable handle, so reports, allowlists and revocation lists must use it.
- **A dedup step cannot fix drift.** Deduplicating identical lines does not touch a rotated
  key, because different material means different lines. "We dedupe" was never a revocation
  story.
- **Line counts are unsound without fingerprint counts.** Key tooling silently skips
  unparseable lines, so the count of *keys* and the count of *lines* differ wherever junk
  exists. A validator must assert both, and report the unparseable count, or it passes while
  reporting the wrong number.

Junk is real: the census found placeholder-shaped lines that no key parser accepts — blob
lengths far too short for the declared key type. They cannot authenticate, so they are dead
weight rather than exposure, but they skew naive counting and no fingerprint-based tool can
remove them safely.

## 7. Revocation was the missing half

The bootstrap tool only ever adds. With a superseded key live on most of the fleet, the repo
could produce a drift report it had no way to act on. `prune-keys.bash` closes that gap and is
deliberately hard to fire:

- requires an explicit fingerprint list; refuses without one;
- **never removes a fingerprint present in the operator list** — the config is the allowlist,
  so a typo cannot delete a key the fleet still needs;
- dry-run by default; an apply flag to change anything;
- dated `0600` backup first; refuses to install a result containing no key lines, so a bug
  cannot lock out the operator;
- reports removals as fingerprint plus comment, never as key material;
- leaves lines it cannot fingerprint alone and says so — junk needs a human decision, not a
  pattern match.

Because the exec wrapper exports a fixed variable allowlist, this payload cannot even receive
its arguments until someone adds them there on purpose. Revocation stays the owner's decision;
the tool makes it possible and auditable. **It has not been run anywhere.**

## 8. Backup scope stays where it is

The backup tool's per-host files stay the home of backup knowledge — paths, database hooks,
size notes. What should *leave* them is the fleet metadata they duplicate in comments (ssh
alias, login user, instance name), which becomes a registry read. A validator asserts: every
conf basename exists in the registry with the same group; every `backup=yes` host has a conf
file; and disabled files are reported rather than silently skipped — a disabled-and-unreachable
host is a state no current check notices.

Renaming those directories to match role names would break historical backup paths. Deferred
deliberately: it buys naming consistency at the cost of the history that makes drift
auditable.

## 9. Naming by role, and the mixed-state reality

Object names drift independently: one rename may be API-able while the matching subnet and
gateway updates are console-only, so **an estate in a mixed naming state is normal**. Rules:

- name inventories and registry fields by **role** (`group=`, `nat_entry=`, `reaches=`);
- never make a cloud object name load-bearing — group files key on aliases, and aliases built
  from port + IP survive any rename;
- when a consumer resolves a network **by ID** rather than by name, say so explicitly, because
  it changes the risk assessment: a rename cannot break a value that is never referenced;
- bucket every occurrence of an obsolete label into **(a)** safe to change now, **(b)** must
  wait for the rename, **(c)** historical, keep — dated results, finished reports, log paths;
- **never sweep on a short word.** The obsolete label shared a substring with an unrelated live
  domain and with generic tooling prose. Sweeping on the word rewrites certificate hostnames
  and test boilerplate. Sweep on the full object tokens.

## 10. The public/private split — and the mistake this section documents

A rule stated as judgement is not a guardrail. The first version of this document was written
into this repository with real addresses, instance identifiers and host lists in it, and pushed.
The warnings that should have stopped it were already in the tree:

- `rhosts/.gitignore` said *"may contain sensitive hostnames"*;
- the repository's baseline content carries **no** site identifiers at all — it is
  deliberately generic, and a grep for such patterns returned nothing before that commit.

Both signals were outweighed by an assertion in a task brief that aliases carry no secrets.
That reasoning is insufficient for two reasons worth keeping:

1. **"No credentials" is not the only disclosure axis.** Entry addresses plus the aliases that
   describe what each machine *does* is a map of a production estate; some aliases name
   security-critical services. The topology itself is the sensitive part.
2. **A repo's own versioned policy outranks a single message about it.** When a committed
   ignore-comment and a claim in a task brief disagree, the committed one is the standing
   position and deserves the benefit of the doubt.

Outcome: **this document is scrubbed, the real lists are gitignored again, and site facts live
in the private docs of record.** Nothing from this branch is pushed; the earlier branch was
deleted and the base branch never contained any of it.

The durable fix is not a note in a document. It is `ubuntu/tests/no-host-identifiers_test.sh`,
which fails on:

- any **publicly routable IPv4** in any tracked file (loopback, RFC1918 and TEST-NET
  documentation ranges excluded, so a placeholder never trips it);
- any **private address in a non-template file** — templates may hold synthetic values; a real
  file holding one means it names a machine;
- **instance-identifier shapes**, which denote one machine rather than a role;
- **private key material**, always;
- a **tracked per-host list** — the structural invariant that actually broke;
- plus **site-specific literal patterns** read from `ubuntu/tests/host-identifiers.local`,
  which is itself gitignored — hardcoding one fleet's alias prefixes into a public repo would
  itself be the leak this gate exists to catch. That file is what makes the gate fleet-aware on
  a real machine without shipping the fleet.

## 11. The validation gate

The checks the census proved necessary, ordered by how much they catch:

1. **Reverse coverage — the one that matters most.** Every alias declared in the ssh config,
   including names reachable *only* through a wildcard, must be in the registry or explicitly
   exempted. A registry→config check passes while ungoverned hosts exist; config→registry is
   the direction that fails when it matters.
2. **Forward resolution.** Every registry alias resolves to an explicit `Host` block whose
   user/port/jump match the record.
3. **Key convergence.** Per host, fingerprints ⊇ operator list, for both the operator account
   and the maintenance account.
4. **Declared extras only.** Every authorized-key fingerprint outside the operator list must be
   declared for that host, or the check fails. This converts drift into policy.
5. **Account shape.** Maintenance user exists, is in the sudo group, and its sudoers drop-in
   validates.
6. **Both counters.** Raw line count *and* fingerprintable-key count against the prior
   snapshot, with the unparseable count reported.
7. **No deletions without a revocation record.** A disappeared fingerprint must have a matching
   dated entry — what makes append-only *provable*. The key run proved it the only way that
   counts: each host diffed against its own backup taken beforehand. **Zero fingerprints lost**,
   additions only, no line count decreased, unparseable count unchanged on every host.
8. **Docs agree.** Generated tables match the registry; a hand-edit that contradicts them fails.
9. **`login_user` policy.** Root and jump hosts excluded from batch operations, reported
   separately.

Checks 1, 7 and 9 are the ones a green suite was missing while all three failure classes sat
undiscovered.

## 12. Open questions

1. Which hosts are missing from the registry today — reverse coverage will name them, and it
   will fail first.
2. Undeclared operator keys found on hosts: promote to the operator list, or queue for
   revocation.
3. Machine/service keys found on hosts: declare with scope, or revoke.
4. Revocation of the superseded rotated key is now possible but unscheduled.
5. Placeholder/junk key lines: cleanup rather than revocation — confirm, since no
   fingerprint-based tool can address them.
6. Disabled-and-unreachable host entries: reclaim, or delete the forwarding rules and conf
   files.
7. Whether per-host lists should ever be committed in a public tool repo. This branch's answer
   is no: `.example` templates plus a generator are the contract.

## 13. Permission hygiene note

Two control paths were found with a **group-writable** `~/.ssh` while all others were `700`.
They were tightened to `700`, one host at a time, in increasing-blast-radius order (a leaf
first, the jump host last), each with a multiplexed control connection held open as the
rollback path and a fresh independent connection as the proof, followed by re-verification
that dependents still route through the jump.

Worth stating plainly because the first draft got it wrong: **`StrictModes yes` accepted the
group-writable directory.** sshd rejects world-writable paths, and group-writable files the
user does not own; it does not reject a group-writable directory owned by the user. The earlier
framing — "one sshd change away from locking out both operators" — was overstated. The change
was correct hygiene, not the prevention of a pending lockout. Reporting the scarier version was
the error; the measurement is the correction.
