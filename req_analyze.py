#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = ["packaging>=23"]
# ///
"""
Pick shared dependencies for a common Python base image.

  scan     uv run req_analyze.py scan <requirements files...> [--min 2] [--pypi] [--py 312] [--emit base.in]
  measure  python req_analyze.py measure [--top 40]      # run INSIDE a linux image: installed size per dist
"""
import argparse
import json
import os
import re
import sys
import urllib.request
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor

GENERIC_DIRS = {"app", "src", "requirements", "deploy", "docker"}


def norm(name):
    return re.sub(r"[-_.]+", "-", name).lower()


def project_of(path):
    parts = [p for p in os.path.normpath(path).split(os.sep) if p not in ("", ".")][:-1]
    while len(parts) > 1 and parts[-1] in GENERIC_DIRS:
        parts.pop()
    return parts[-1] if parts else path


def parse(path, seen=None):
    from packaging.requirements import InvalidRequirement, Requirement

    seen = set() if seen is None else seen
    path = os.path.abspath(path)
    if path in seen:
        return []
    seen.add(path)
    out = []
    for raw in open(path, encoding="utf-8"):
        line = re.split(r"\s+#", raw, maxsplit=1)[0].strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith(("-r ", "--requirement ")):
            out += parse(os.path.join(os.path.dirname(path), line.split(None, 1)[1]), seen)
            continue
        if line.startswith("-"):  # -i / --extra-index-url / -e / -c / --hash ...
            print(f"  skip option  {project_of(path)}: {line}", file=sys.stderr)
            continue
        try:
            out.append(Requirement(line))
        except InvalidRequirement:
            print(f"  skip invalid {project_of(path)}: {line}", file=sys.stderr)
    return out


def wheel_ok(tag, py):
    plat = tag.platform == "any" or (
        tag.platform.endswith("x86_64") and tag.platform.startswith(("manylinux", "linux"))
    )
    if not plat:
        return False
    if tag.interpreter in (f"cp{py}", f"py{py}", "py3"):
        return True
    return tag.abi == "abi3" and tag.interpreter.startswith("cp3") and int(tag.interpreter[3:]) <= int(py[1:])


def pypi_info(name, spec, py):
    """Highest non-prerelease version satisfying `spec`, and its cp{py} manylinux x86_64 wheel size."""
    from packaging.utils import parse_wheel_filename
    from packaging.version import InvalidVersion, Version

    try:
        with urllib.request.urlopen(f"https://pypi.org/pypi/{name}/json", timeout=20) as r:
            releases = json.load(r)["releases"]
    except Exception as e:  # private package / network
        return "ERR", None, type(e).__name__
    best = None
    for v, files in releases.items():
        try:
            ver = Version(v)
        except InvalidVersion:
            continue
        if ver.is_prerelease or not files or all(f.get("yanked") for f in files):
            continue
        if spec.contains(ver) and (best is None or ver > best[0]):
            best = (ver, files)
    if best is None:
        return None, None, "no version satisfies all specifiers"
    size, sdist_only = None, True
    for f in best[1]:
        if f["packagetype"] != "bdist_wheel":
            continue
        sdist_only = False
        try:
            tags = parse_wheel_filename(f["filename"])[3]
        except Exception:
            continue
        if any(wheel_ok(t, py) for t in tags):
            size = max(size or 0, f["size"])
    note = "sdist only (needs compiler)" if sdist_only else ("" if size else f"no cp{py} linux wheel")
    return str(best[0]), size, note


def scan(a):
    from packaging.specifiers import SpecifierSet

    pyv = f"{a.py[0]}.{a.py[1:]}"
    env = {
        "sys_platform": "linux", "platform_system": "Linux", "platform_machine": "x86_64",
        "os_name": "posix", "implementation_name": "cpython",
        "platform_python_implementation": "CPython",
        "python_version": pyv, "python_full_version": f"{pyv}.0",
    }
    table = defaultdict(dict)  # pkg -> {project: Requirement}
    for f in a.files:
        proj = project_of(f)
        for req in parse(f):
            if req.marker and not req.marker.evaluate(env):
                continue
            table[norm(req.name)][proj] = req

    rows = []
    for pkg, by in table.items():
        spec = SpecifierSet()
        for req in by.values():
            spec &= req.specifier
        pins = {s.version for req in by.values() for s in req.specifier
                if s.operator == "==" and "*" not in s.version}
        extras = sorted(set().union(*(req.extras for req in by.values())))
        if any(req.url for req in by.values()):
            status = "url"
        elif pins and not any(spec.contains(p, prereleases=True) for p in pins):
            status = "CONFLICT"
        elif len(spec) == 0:
            status = "unpinned"
        else:
            status = "ok"
        rows.append(dict(pkg=pkg, by=by, spec=spec, extras=extras, status=status,
                         ver=None, size=None, note=""))

    cand = [r for r in rows if len(r["by"]) >= a.min and r["status"] in ("ok", "unpinned")]
    if a.pypi and cand:
        with ThreadPoolExecutor(16) as ex:
            for r, (ver, size, note) in zip(cand, ex.map(lambda r: pypi_info(r["pkg"], r["spec"], a.py), cand)):
                r["ver"], r["size"], r["note"] = ver, size, note
                if ver is None:
                    r["status"] = "CONFLICT"

    rows.sort(key=lambda r: (-len(r["by"]), -(r["size"] or 0), r["pkg"]))
    print(f"{'package':<28}{'n':>3}{'wheel':>9}  {'resolved':<12}{'status':<10}per-project")
    print("-" * 110)
    for r in rows:
        size = f"{r['size'] / 2**20:.1f}M" if r["size"] else "-"
        per = "  ".join(f"{p}:{str(q.specifier) or '*'}" for p, q in sorted(r["by"].items()))
        ver = r["ver"] if r["ver"] not in (None, "ERR") else ("?" if r["ver"] == "ERR" else "-")
        name = r["pkg"] + (f"[{','.join(r['extras'])}]" if r["extras"] else "")
        print(f"{name:<28}{len(r['by']):>3}{size:>9}  {ver:<12}{r['status']:<10}{per}"
              + (f"   # {r['note']}" if r["note"] else ""))

    if a.emit:
        with open(a.emit, "w") as fh:
            fh.write(f"# generated by req_analyze.py  (shared by >= {a.min} projects, no conflicts)\n")
            for r in sorted(cand, key=lambda r: r["pkg"]):
                if r["status"] == "CONFLICT":
                    continue
                name = r["pkg"] + (f"[{','.join(r['extras'])}]" if r["extras"] else "")
                pin = f"=={r['ver']}" if r["ver"] not in (None, "ERR") else str(r["spec"])
                fh.write(f"{name}{pin}\n")
        print(f"\nwrote {a.emit}", file=sys.stderr)


def measure(a):
    from importlib.metadata import distributions

    rows = []
    for d in distributions():
        total = 0
        for f in d.files or []:
            try:
                total += os.path.getsize(d.locate_file(f))
            except OSError:
                pass
        rows.append((total, d.metadata["Name"], d.version))
    rows.sort(reverse=True)
    for total, name, ver in rows[: a.top]:
        print(f"{total / 2**20:9.1f} MB  {name}=={ver}")
    print(f"{sum(r[0] for r in rows) / 2**20:9.1f} MB  TOTAL ({len(rows)} dists)")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("scan")
    s.add_argument("files", nargs="+")
    s.add_argument("--min", type=int, default=2, help="min number of projects sharing a package")
    s.add_argument("--pypi", action="store_true", help="resolve common version + wheel size via PyPI")
    s.add_argument("--py", default="312", help="target CPython, e.g. 312")
    s.add_argument("--emit", help="write candidate base.in")
    m = sub.add_parser("measure")
    m.add_argument("--top", type=int, default=40)
    a = ap.parse_args()
    scan(a) if a.cmd == "scan" else measure(a)


if __name__ == "__main__":
    main()
