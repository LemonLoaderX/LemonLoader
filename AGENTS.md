# Repository agent rules

Read the [task index](docs/README.md) and the relevant build, test or
contract guide before changing code. Commands run from this repository root;
the parent folder and Patcher checkout are not required build inputs.

- Preserve unrelated edits. Create commits only when requested by the maintainer;
  do not push, publish or change signing state without explicit authorization.
- Fix behavior in its owning repository. Dependency changes belong in reviewed
  source forks, not binary rewriting. Never switch a shared checkout automatically.
- Keep production logs actionable. Do not add installed-file inventories or
  routine corruption scans; use ordinary loading errors and retained crash logs.
- Retain ZIP path/duplicate safety, download and Release hash/signature checks,
  ABI checks, native-name collision checks and runtime-pack completeness.
  Mutable installed-payload digests are not game-startup admission checks.
- Change format versions only when old consumers cannot interpret new semantics;
  tolerate unknown additive fields. Remove private/build-only inputs at producers.
- Use the smallest relevant regression, inspect the diff and outputs, then broaden
  verification for the affected boundary. Host tests do not qualify devices.
- Never uninstall applications, clear app data or change package names for routine
  tests. Do not traverse output links or clean another repository's sources.
- Keep APKs, generated Interop, packs, symbols, secrets, signing material and
  private evidence outside Git and public releases. Local job/build/acceptance
  status belongs in ignored output, never tracked documentation or design notes.
- Record stable commands, root causes and constraints in the relevant guide;
  nontrivial decisions belong in .agents/notes, updating an existing topic first.
