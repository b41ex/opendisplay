"""Inspect and restore Receiver artifacts exclusively on a GitHub macOS runner."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import sys
import tempfile


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def run(*args):
    return subprocess.check_output(args, text=True)


def version(value):
    parts = tuple(map(int, value.split(".")))
    return parts + (0,) * (3 - len(parts))


def inventory(app):
    """Include link targets, all permission bits and hashes without following links.

    https://docs.python.org/3.14/library/os.html#os.walk
    https://docs.python.org/3.14/library/stat.html#stat.S_IMODE
    """
    entries = {}
    paths = [app]
    for root, directories, files in os.walk(app, followlinks=False):
        paths.extend(Path(root) / name for name in directories + files)
    for path in paths:
        entry = {"mode": stat.S_IMODE(path.lstat().st_mode)}
        if path.is_symlink():
            entry["link"] = os.readlink(path)
        elif path.is_file():
            entry["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        else:
            entry["directory"] = True
        entries[str(path.relative_to(app))] = entry
    return entries


def macos_minimum(binary, arch):
    # Swift back-deployment libraries also have Mac Catalyst load commands.
    # Only macOS commands apply here; don't mistake Catalyst minima for macOS.
    # https://github.com/apple-oss-distributions/cctools/blob/main/misc/vtool.c
    output = run("xcrun", "vtool", "-arch", arch, "-show-build", str(binary))
    minima = []
    for command in re.split(r"Load command\s+\d+\s*\n", output):
        if re.search(r"cmd\s+LC_VERSION_MIN_MACOSX\b", command):
            minima.append(re.search(r"\bversion\s+([\d.]+)", command).group(1))
        elif re.search(r"cmd\s+LC_BUILD_VERSION\b", command) and re.search(
            r"platform\s+MACOS\s*$", command, re.MULTILINE
        ):
            minima.append(re.search(r"\bminos\s+([\d.]+)", command).group(1))
    require(len(minima) == 1, f"Expected one macOS minimum: {binary} ({arch})\n{output}")
    return minima[0]


require(os.environ.get("GITHUB_ACTIONS") == "true" and sys.platform == "darwin",
        "Artifact validation must run on a GitHub macOS runner")
mode, source, manifest_path = sys.argv[1:]
manifest_path = Path(manifest_path)
if mode == "bundle":
    app = Path(source)
    requested = set(os.environ.get("ARCHITECTURES", "x86_64").split())
    limits = {"x86_64": "10.15.7", "arm64": "11.0"}
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    require(info["LSMinimumSystemVersion"] == "10.15.7", "Incorrect bundle minimum")
    tree = inventory(app)
    binaries = {}
    main = "Contents/MacOS/" + info["CFBundleExecutable"]
    for relative, entry in tree.items():
        binary = app / relative
        if "sha256" not in entry or "Mach-O" not in run("file", "-b", str(binary)):
            continue
        architectures = set(run("lipo", "-archs", str(binary)).split())
        require(requested <= architectures, f"Missing slice in {relative}: {architectures}")
        if relative == main:
            require(architectures == requested, f"Incorrect app slices: {architectures}")
            require(entry["mode"] & 0o111, "App executable lost executable bits")
        binaries[relative] = {}
        for arch in sorted(architectures):
            require(arch in limits, f"Unexpected architecture {arch} in {relative}")
            minimum = macos_minimum(binary, arch)
            require(version(minimum) <= version(limits[arch]), f"Incompatible {relative}: {arch} {minimum}")
            if relative == main:
                require(version(minimum) == version(limits[arch]), f"Incorrect app minimum: {arch} {minimum}")
            binaries[relative][arch] = minimum
    require(main in binaries, "App Mach-O executable missing")
    manifest_path.write_text(json.dumps({"app": app.name, "tree": tree, "macho": binaries}, indent=2))
    print(f"Verified {len(binaries)} embedded Mach-O files and all macOS slices")
elif mode == "zip":
    manifest = json.loads(manifest_path.read_text())
    with tempfile.TemporaryDirectory(prefix="receiver-zip-") as directory:
        run("ditto", "-x", "-k", source, directory)
        restored = inventory(Path(directory) / manifest["app"])
        expected = manifest["tree"]
        differences = [name for name in sorted(expected.keys() | restored.keys())
                       if expected.get(name) != restored.get(name)]
        require(not differences, f"ZIP changed files, symlinks or modes: {differences}")
    print(f"Verified ZIP restoration: {len(restored)} entries, symlinks, modes and SHA-256 hashes")
else:
    raise ValueError(f"Unknown validation mode: {mode}")
