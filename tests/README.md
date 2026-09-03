# Tests

Android device probes live under `Android` and are built through scripts rather
than the desktop solution.

`Android/SmokeMod` contains the minimal Mod used by the startup smoke workflow.
It logs deterministic markers for initialization, scene load, first Update, and
first LateUpdate. Add a marker here before claiming another Android lifecycle
path as supported.

The remaining Android projects are focused host-side regressions for CoreCLR
embedding, Harmony resolver precedence, MonoMod dynamic methods, and IL2CPP
injection behavior. Run them through the corresponding scripts in
`scripts/test`; they are not packaged into releases.
