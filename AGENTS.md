# Protocol emulator agent instructions

Read README.md, docs/SETUP.md, docs/PLAN.md and docs/HANDOFF.md first.

This is an independent ASIC repository, not the surrounding Omni project. Do not modify the parent repository. Keep the official Tiny Tapeout flow authoritative. Target IHP CMOS5L and 8x4 tiles; verify current competition requirements before submission.

Do not invent tool success, timing results, licenses, PDK compatibility or completed RTL. Report absent tools and blocked runs explicitly. Start with the unchanged official template, then a functional RTL baseline, then custom macros.

Use separate branches/worktrees per active task. Local Codex owns specifications, model, software and review by default; server Codex owns EDA environment and execution by default. Make ownership changes explicit in docs/HANDOFF.md. Do not edit the same branch concurrently.

Keep live OpenAccess databases in one server workspace. Never merge or concurrently synchronize live databases. Back up consistent checkpoints and export portable views. Exclude credentials, licensed PDKs, machine settings, waveforms and generated output from commits. Do not commit downloaded foundry/reference libraries.

For custom macros, prove integration early: logical and simulation models, power/pin contract, LEF, GDS, timing and verification views as required by the selected flow. Do not assume SG13G2 and CMOS5L are interchangeable. Verify stream maps, devices and rule decks.

Every EDA run must record source commit, tool/PDK versions, command, exit status and parsed pass/fail criteria. DRC/LVS, timing and assertions require inspecting results, not just process exit codes. Preserve full logs in ignored runs/ and commit concise reviewed summaries when useful.

Run python scripts/workflow.py check after infrastructure edits and appropriate functional checks after RTL/model changes. Never label infrastructure checks as design verification. Do not auto-publish or create remote repositories unless requested. Document AI contributions for the competition write-up.
