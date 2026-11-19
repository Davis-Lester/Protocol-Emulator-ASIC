"""Portable starter checks and non-destructive official-template import."""
import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = "https://github.com/TinyTapeout/ttihp-verilog-template.git"


def check():
    required = ["README.md", "AGENTS.md", ".gitignore", "docs/SETUP.md",
                "docs/PLAN.md", "docs/HANDOFF.md", "scripts/workflow.py"]
    missing = [p for p in required if not (ROOT / p).is_file()]
    if missing:
        raise RuntimeError("Missing starter files: " + ", ".join(missing))
    compile(Path(__file__).read_text(encoding="utf-8"), str(__file__), "exec")
    lock = ROOT / "config/template-lock.json"
    if lock.exists():
        data = json.loads(lock.read_text(encoding="utf-8"))
        if data["url"] != UPSTREAM or not re.fullmatch(r"[0-9a-f]{40}", data["commit"]):
            raise RuntimeError("Invalid template provenance")
        text = (ROOT / "info.yaml").read_text(encoding="utf-8")
        if not re.search(r'^\s*tiles:\s*[\"\']?8x4[\"\']?\s*(?:#.*)?$', text, re.M):
            raise RuntimeError("Expected 8x4 tiles in info.yaml")
        print("PASS: starter structure and template provenance; EDA checks not run")
    else:
        print("PASS: starter structure; official template NOT imported; EDA checks not run")


def doctor():
    print("Python:", sys.version.split()[0])
    print("Executable discovery only; licenses and PDK compatibility are unverified.")
    for name in ["git", "make", "iverilog", "verilator", "vsim", "vlog", "vivado",
                 "virtuoso", "spectre", "calibre", "pvs", "pegasus", "klayout",
                 "yosys", "openroad", "librelane", "docker", "nix", "squeue"]:
        print(f"{name}: {shutil.which(name) or 'NOT FOUND'}")
    print("Template:", "imported" if (ROOT / "config/template-lock.json").exists() else "NOT imported")


def test_model():
    """Software functional tests only; these do not simulate RTL."""
    subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "verification",
                    "-p", "test_*.py", "-v"], cwd=ROOT, check=True)


def demo():
    """Assemble and execute the timed-pulse example with CSV/VCD outputs."""
    subprocess.run([sys.executable, "-m", "tools.assembler", "programs/pulse.asm",
                    "-o", "runs/pulse.hex"], cwd=ROOT, check=True)
    subprocess.run([sys.executable, "-m", "model.engine", "runs/pulse.hex",
                    "--trace", "runs/pulse.csv", "--vcd", "runs/pulse.vcd"],
                   cwd=ROOT, check=True)
    print("Software demo outputs: runs/pulse.hex, runs/pulse.csv, runs/pulse.vcd")


def bootstrap():
    if (ROOT / "config/template-lock.json").exists():
        raise RuntimeError("Template already imported; review upstream updates manually")
    with tempfile.TemporaryDirectory(prefix="protocol-template-") as tmp:
        source = Path(tmp) / "template"
        subprocess.run(["git", "clone", "--depth", "1", "--branch", "main", UPSTREAM, str(source)], check=True)
        commit = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
        planned = []
        for src in source.rglob("*"):
            rel = src.relative_to(source)
            if ".git" in rel.parts or not src.is_file():
                continue
            if rel.as_posix() == "README.md":
                rel = Path("README.tinytapeout.md")
            if rel.as_posix() == ".gitignore":
                rel = Path("config/template.gitignore")
            planned.append((src, ROOT / rel))
        collisions = [str(dst.relative_to(ROOT)) for _, dst in planned if dst.exists()]
        if collisions:
            raise RuntimeError("Import refused; existing paths: " + ", ".join(collisions))
        info = (source / "info.yaml").read_text(encoding="utf-8")
        info, count = re.subn(r'^(\s*tiles:)\s*[^\n]*', r'\1 "8x4"', info, flags=re.M)
        if count != 1:
            raise RuntimeError("Template info.yaml format changed; inspect before importing")
        # All collision and format checks happen before copying any template files.
        for src, dst in planned:
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
        (ROOT / "info.yaml").write_text(info, encoding="utf-8")
        upstream_ignore = ROOT / "config/template.gitignore"
        if upstream_ignore.exists():
            with (ROOT / ".gitignore").open("a", encoding="utf-8") as stream:
                stream.write("\n# Imported upstream exclusions\n" + upstream_ignore.read_text(encoding="utf-8"))
        (ROOT / "config/template-lock.json").write_text(
            json.dumps({"url": UPSTREAM, "branch": "main", "commit": commit}, indent=2) + "\n", encoding="utf-8")
    print("Imported official template at", commit)
    print("Review git diff, metadata and upstream documentation. No flow has run.")
    check()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["check", "doctor", "bootstrap-template", "test-model", "demo"])
    args = parser.parse_args()
    try:
        {"check": check, "doctor": doctor, "bootstrap-template": bootstrap,
         "test-model": test_model, "demo": demo}[args.command]()
    except (RuntimeError, OSError, subprocess.CalledProcessError, KeyError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
