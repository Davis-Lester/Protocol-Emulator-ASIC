# Local and ECE server setup

## Repository and remotes

This checkout is independent of Omni. An origin remote is now configured for Davis-Lester/Protocol-Emulator-ASIC. Check `git remote -v` and the remote's actual state before changing it; no push or Actions result is verified here. For a new checkout that has no remote, the commands are:

```sh
git remote add origin <YOUR_REPOSITORY_URL>
git push -u origin main
```

On the ECE server, use the university's supported SSH access and an approved compute host. Clone your own repository URL, not the template URL:

```sh
git clone <YOUR_REPOSITORY_URL> protocol-emulator-asic
cd protocol-emulator-asic
git switch -c server/environment
python3 scripts/workflow.py doctor
```

Authenticate through your normal Git credential or SSH setup; never put tokens in URLs or project files. Use tmux for long interactive sessions if permitted. Use the university scheduler when required; do not run heavy jobs on login nodes. Remote desktop is useful for visually reviewing custom layout.

## Import the official flow

```sh
python3 scripts/workflow.py bootstrap-template
```

The importer fetches official main, records the resolved commit, retains the upstream license and workflows, and sets info.yaml tiles to 8x4. It refuses to overwrite existing files. It does not install EDA software, run the flow or commit changes. Review its diff and commit the imported baseline. Later upstream changes require deliberate review, not rerunning the bootstrap over existing files.

Consult the imported documentation for the actual pinned Tiny Tapeout dependencies, actions and local flow commands. Do not guess a LibreLane invocation or install unpinned latest dependencies. On Windows use a supported Linux environment for the ASIC flow; verify whether ECE supports the required container/environment tooling.

## Server inventory

Run doctor after sourcing the institution-provided tool setup, then record in docs/HANDOFF.md: host class, tool versions, license smoke-test outcomes, supported job submission, exact CMOS5L PDK revision, model and stream-map compatibility, DRC/LVS/extraction decks, and available storage/backups. Record paths through local configuration, without committing licensed contents or credentials. Executable presence alone proves none of these.

Verify Virtuoso, Spectre, Questa, optional Vivado, and whichever DRC/LVS/PEX products are actually licensed. Genus/Innovus are optional exploration tools; the competition flow remains authoritative. Test one CMOS5L cell and one imported custom macro before committing to a larger custom block.

## Collaboration

Use local/<task> and server/<task> branches. Commit small changes, push the task branch and review before merging. Record the exact commit and acceptance criteria when handing work over. Do not pull into an active dirty EDA workspace or run concurrent agents against one database.

Keep the active Cadence database in ignored cadence-work/ on the server. Coordinate consistent backups through server-approved storage. Commit reproducible SKILL/OCEAN/Tcl scripts and redistributable exported macro views, with provenance. Do not assume a live OpenAccess database is safely Git-mergeable.

## First checks

After template import, run its documented RTL tests and the official GDS/precheck workflow. Record actual results. Questa-specific scripts should be added once source lists and a non-cocotb or compatible harness are established. Vivado needs a board-specific wrapper and constraints; do not reuse FPGA timing results as ASIC closure evidence.
