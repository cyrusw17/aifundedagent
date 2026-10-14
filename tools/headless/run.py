#!/usr/bin/env python3
"""Boots the whole Needlewood server outside Roblox and reports every runtime error with its src file and line.

    python3 tools/headless/run.py [path/to/luau] [--play SECONDS] [--selftests] [--keep] [--timeout SECONDS]

Run from anywhere; paths are relative to this file. Needs the plain luau CLI (github.com/luau-lang/luau).
Bundles mock.luau + mock_instances.luau + mock_services.luau (a Roblox API stand-in), every source file under src/
mounted where default.project.json puts it, and scenario.luau (boot Main.server.luau, a player joins, picks save
slot 1, plays, leaves, shutdown). Exit code 1 on any uncaught error, 0 otherwise. See README.md.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
MOCK_FILES = ["mock.luau", "mock_instances.luau", "mock_services.luau"]
# Folders whose modules the scenario requires at the end even if nothing reached them (server side only).
PRELOAD = ("src/server/", "src/shared/")
SKIP_PRELOAD = ("src/shared/UI/",)


def project_mounts():
    """(rojo path, src dir) pairs from default.project.json."""
    tree = json.load(open(os.path.join(ROOT, "default.project.json")))["tree"]
    out = []

    def walk(node, path):
        for key, child in node.items():
            if key.startswith("$") or not isinstance(child, dict):
                continue
            here = path + [key]
            if "$path" in child:
                out.append((".".join(here), child["$path"]))
            walk(child, here)

    walk(tree, [])
    return out


def script_entries():
    """Every .luau/.lua file as (instance full name, class, src path)."""
    entries = []
    for mount, src_dir in project_mounts():
        base = os.path.join(ROOT, src_dir)
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames.sort()
            rel_dir = os.path.relpath(dirpath, base)
            parts = [] if rel_dir == "." else rel_dir.split(os.sep)
            for name in sorted(filenames):
                if not (name.endswith(".luau") or name.endswith(".lua")):
                    continue
                stem = re.sub(r"\.luau?$", "", name)
                cls = "ModuleScript"
                if stem.endswith(".server"):
                    cls, stem = "Script", stem[: -len(".server")]
                elif stem.endswith(".client"):
                    cls, stem = "LocalScript", stem[: -len(".client")]
                names = parts + ([] if stem == "init" else [stem])
                full = ".".join([mount] + names)
                rel = os.path.relpath(os.path.join(dirpath, name), ROOT).replace(os.sep, "/")
                entries.append((full, cls, rel))
    return entries


def long_string(text):
    level = 1
    while ("]" + "=" * level + "]") in text:
        level += 1
    eq = "=" * level
    return f"[{eq}[\n{text}]{eq}]"


MOCK_LINES = []  # (first bundle line, file) for mapping bundle line numbers back to the mock files


def bundle(options):
    out = []
    line = 2  # after "SOURCES = {}"
    for f in MOCK_FILES:
        text = open(os.path.join(HERE, f)).read()
        MOCK_LINES.append((line + 1, f))
        out.append(f"do -- {f}\n{text}\nend")
        line += text.count("\n") + 2
    mounts = []
    for full, cls, rel in script_entries():
        source = open(os.path.join(ROOT, rel)).read()
        # `script` is the instance passed to the chunk; prefixed on line 1 so line numbers stay true.
        source = "local script = ...; " + source
        out.append(f'SOURCES[{json.dumps(full)}] = {{ path = {json.dumps(rel)}, source = {long_string(source)} }}')
        preload = cls == "ModuleScript" and rel.startswith(PRELOAD) and not rel.startswith(SKIP_PRELOAD)
        mounts.append(f'{{ name = {json.dumps(full)}, class = "{cls}", preload = {"true" if preload else "false"} }}')
    out.append("MOUNTS = {\n\t" + ",\n\t".join(mounts) + "\n}")
    opts = [f"play = {options.play}", f"settle = {options.settle}", f"selfTests = {'true' if options.selftests else 'false'}", f"poke = {'false' if options.no_poke else 'true'}", f"deferred = {'true' if options.deferred else 'false'}"]
    out.append("OPTIONS = { " + ", ".join(opts) + " }")
    tail_name = "mocktest.luau" if options.mock_test else "scenario.luau"
    head = "SOURCES = {}\n" + "\n".join(out) + "\n"
    MOCK_LINES.append((head.count("\n") + 1, tail_name))
    return head + open(os.path.join(HERE, tail_name)).read()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("luau", nargs="?", default="luau", help="path to the luau CLI (default: luau on PATH)")
    ap.add_argument("--play", type=float, default=60, help="simulated seconds the player stays (default 60)")
    ap.add_argument("--settle", type=float, default=10, help="simulated seconds after boot before the join (default 10)")
    ap.add_argument("--selftests", action="store_true", help="set Workspace.RunSelfTests (physics-based checks will FAIL headless)")
    ap.add_argument("--keep", action="store_true", help="keep the bundle (tools/headless/.headless_bundle.luau) for debugging")
    ap.add_argument("--no-poke", action="store_true", help="skip the poke phase (swing tools, use every prompt and click detector)")
    ap.add_argument("--deferred", action="store_true", help="run signal handlers deferred (Workspace.SignalBehavior = Deferred) instead of immediately")
    ap.add_argument("--mock-test", action="store_true", help="run mocktest.luau (checks the mock itself) instead of the boot scenario")
    ap.add_argument("--bundle-only", action="store_true", help="write tools/headless/.headless_bundle.luau and stop (for luau --profile)")
    ap.add_argument("--timeout", type=float, default=600, help="real seconds before the run is killed as hung (default 600)")
    options = ap.parse_args()

    path = os.path.join(HERE, ".headless_bundle.luau" if options.bundle_only or options.keep else f".headless_bundle.{os.getpid()}.luau")
    with open(path, "w") as f:
        f.write(bundle(options))
    if options.bundle_only:
        print(path)
        return
    try:
        cmd = [options.luau, path]
        if shutil.which("stdbuf"):
            cmd = ["stdbuf", "-oL"] + cmd  # line-buffered, so progress shows while it runs
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, cwd=ROOT)
        lines = []
        hung = []
        watchdog = threading.Timer(options.timeout, lambda: (hung.append(True), proc.kill()))
        watchdog.start()
        bundle_re = re.compile(r"\S*\.headless_bundle[.\d]*luau:(\d+)")

        def to_mock(m):
            n = int(m.group(1))
            name, first = "bundle", 1
            for start, f in MOCK_LINES:
                if n >= start:
                    name, first = "tools/headless/" + f, start
            return f"{name}:{n - first + 1}"

        for line in proc.stdout:
            line = bundle_re.sub(to_mock, line)
            print(line, end="", flush=True)
            lines.append(line)
        proc.wait()
        watchdog.cancel()
        if hung:
            print(f"\nHUNG: killed after {options.timeout:.0f} s (a thread is probably looping without yielding)")
            sys.exit(1)
    finally:
        if not options.keep:
            os.remove(path)
    text = "".join(lines)
    result = re.search(r"HEADLESS_RESULT errors=(\d+)", text)
    if proc.returncode != 0 or not result:
        print(f"\nHARNESS CRASH: luau exited {proc.returncode} before the summary (see the last lines above)")
        sys.exit(1)
    sys.exit(1 if int(result.group(1)) > 0 else 0)


if __name__ == "__main__":
    main()
