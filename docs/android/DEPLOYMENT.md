# Packaged deployment

This document defines the layout v8 deployment contract for files preloaded below the
runtime MelonLoader base directory. It is the design authority for deployment
profiles, per-file policies, ownership state, and failure recovery.

## Packaging interface

Deployment profiles (`development`, `production`, `locked`) control installed
file policies. They are independent of the runtime profile (`android`, `bionic`)
and the build's development-source switch. Choosing a deployment policy neither
changes the runtime nor qualifies a development build for release.

Developers select one profile and may add a small number of exact-file or
`directory/**` overrides. LemonLoader.Patcher resolves those rules at package
time and writes one concrete policy for every file in `payload.json`. Native
code never reimplements profile defaults.

Rule precedence is exact file, longest matching directory, profile default,
then `seed`. Paths are case-sensitive normalized relative paths. File/directory
target conflicts and paths reserved by the bootstrap are rejected before the
APK is produced.

| Profile | Mods, Plugins, UserLibs | UserData | Other directories |
| --- | --- | --- | --- |
| `development` | `seed` | `seed` | `seed` |
| `production` | `refresh` | `upgrade` | `seed` |
| `locked` | `enforce` | `upgrade` | `seed` |

The manifest keeps two independent hashes:

- `deploymentSha256` proves the deployment asset tree's paths and bytes.
- `deploymentRevisionSha256` also includes every effective file policy. It is
  the rollout identity used by `refresh` and obsolete-file handling.

Changing only a profile label without changing any effective file policy does
not create a new rollout.

## File policies

`seed` installs a missing file and otherwise preserves the destination.

`upgrade` replaces an existing file only when it still matches the hash from
the last package that managed it. A user-modified file is preserved.

`refresh` replaces a mismatching file once when the deployment revision
changes. ADB or user changes made after that rollout survive later launches
until another deployment revision is installed.

`enforce` restores the packaged bytes on every launch when the destination is
missing or has a different hash.

Files not represented in deployment state are never removed. When a previously
managed file disappears from a new manifest, `seed` preserves it, `upgrade`
removes it only if it is unchanged, and `refresh` or `enforce` removes it on the
new rollout. Every replacement or removal is backed up first.

## Ownership state

State is stored below `.lemonloader-deployment-state` in the MelonLoader base
directory. A file becomes managed when the bootstrap installs or replaces it,
or when an existing file already equals the packaged hash. Merely seeing a
different pre-existing file does not claim it.

State records the last packaged hash and policy, not an assumption that the
current destination is unchanged. This allows `upgrade` to detect user edits
and allows `refresh` to preserve edits until the next rollout.

Layout v4 has no ownership state. On the first v5 launch, `development` keeps
existing files, while `production` and `locked` apply their resolved policies
as a new rollout. No v4 state is guessed. Current startup does not inspect or
delete the old v4 deployment-hash marker; ownership state is authoritative for
the current layout, and historical files are otherwise left untouched.

## Native transaction

After crash-state recovery, a matching deployment revision takes a fast path.
`seed`, `upgrade`, and `refresh` destinations are checked only for existence;
`enforce` destinations additionally require a matching content hash. When every
destination satisfies its policy, startup does not open APK deployment assets,
create staging, read or rewrite per-file state, or scan backup generations.

A new revision, missing destination, or changed `enforce` destination performs
the full deployment transaction:

1. Extract the complete APK deployment tree into bootstrap-owned staging.
2. Validate every path, size, SHA-256, reserved name, and file/directory shape.
3. Read prior ownership state, inspect destinations, and calculate all actions.
4. Preflight parent paths and back up every destination that will change.
5. Apply file changes with sibling temporary files and POSIX rename.
6. Atomically publish the complete next ownership-state tree.
7. Remove staging and prune old backup generations.

State is not changed while files are being applied. If an apply or state-commit
step fails, completed file actions are rolled back in reverse order and the old
state remains authoritative. A later launch can therefore retry from a coherent
starting point. Unknown files and user-owned files are outside the transaction.
