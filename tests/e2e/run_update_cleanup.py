#!/usr/bin/env python3
"""End-to-end tests for the update and cleanup scripts.

This harness drives the *real* entrypoints -- ``scripts/update.sh`` /
``scripts/cleanup.sh`` on Linux, ``scripts/update.ps1`` / ``scripts/cleanup.ps1``
on Windows -- against throwaway ``$HOME`` directories and real local git
remotes. It runs unchanged on Linux (locally and inside the E2E container) and
on ``windows-latest``.

By default it is fully offline: the update scenarios use a controlled fixture
bootstrap, and the cleanup scenarios synthesize ``.dotfiles_backup_*``
directories. ``--real-bootstrap`` additionally runs the repository's real
``bootstrap.sh`` against a fake ``HOME`` to create genuine backups; because that
installs packages/CLIs it needs network and belongs in the weekly/manual
container job, not on ordinary pull requests.

Nothing is ever written outside a per-run temp directory, and the real ``$HOME``
and real backups are never touched.
"""

from __future__ import annotations

import argparse
import itertools
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
IS_WINDOWS = os.name == "nt"

# Reparse points (symlinks/junctions) we create. They are removed before the
# temp tree is deleted so a recursive delete can never traverse them.
CREATED_REPARSE: list[Path] = []

_counter = itertools.count()


class E2EFailure(Exception):
    pass


def log(message: str) -> None:
    print(f"[e2e] {message}", flush=True)


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr, flush=True)
    raise E2EFailure(message)


def check(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


# --------------------------------------------------------------------------- #
# Subprocess helpers
# --------------------------------------------------------------------------- #

def git_env() -> dict:
    env = os.environ.copy()
    env["GIT_TERMINAL_PROMPT"] = "0"
    env["GIT_EDITOR"] = "true"
    env["GIT_PAGER"] = "cat"
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    return env


def run(cmd, cwd, env=None, check_rc=True, timeout=600):
    try:
        proc = subprocess.run(
            [str(c) for c in cmd],
            cwd=str(cwd),
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        fail(f"command timed out after {timeout}s: {' '.join(str(c) for c in cmd)}")
    out = (proc.stdout or "").replace("\r", "")
    if check_rc and proc.returncode != 0:
        fail(f"command failed (rc={proc.returncode}): {' '.join(str(c) for c in cmd)}\n{out}")
    return proc.returncode, out


def git(args, cwd):
    return run(["git", *args], cwd=cwd, env=git_env())


def git_out(args, cwd) -> str:
    return git(args, cwd)[1].strip()


def which(name: str) -> str | None:
    return shutil.which(name)


# --------------------------------------------------------------------------- #
# Platform runner: drives the .sh or .ps1 scripts
# --------------------------------------------------------------------------- #

class Runner:
    def __init__(self, platform: str):
        self.platform = platform  # "unix" or "windows"
        self.ext = ".ps1" if platform == "windows" else ".sh"
        self.pwsh = os.environ.get("DOTFILES_E2E_PWSH") or which("pwsh") or which("powershell")
        # Wrappers live outside any checkout so they never dirty a git tree.
        self.tmp = Path(tempfile.mkdtemp(prefix="dotfiles-e2e-runner-"))

    def script(self, name: str) -> Path:
        return REPO_ROOT / "scripts" / f"{name}{self.ext}"

    def cleanup(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _ps_wrapper(self, script: Path, args, home: Path) -> Path:
        def ps_quote(value: str) -> str:
            return "'" + str(value).replace("'", "''") + "'"

        def ps_arg(value: str) -> str:
            # Switches must stay unquoted; only quote tokens with whitespace.
            text = str(value)
            if "'" in text or '"' in text or any(ch.isspace() for ch in text):
                return ps_quote(text)
            return text

        argline = " ".join(ps_arg(a) for a in args)
        wrapper = self.tmp / f".e2e-wrapper-{os.getpid()}-{next(_counter)}.ps1"
        wrapper.write_text(
            "$global:LASTEXITCODE = 0\n"
            f"Set-Variable -Name HOME -Value {ps_quote(home)} -Force -Scope Global\n"
            f"& {ps_quote(script)} {argline}\n"
            "exit $LASTEXITCODE\n",
            encoding="utf-8",
        )
        return wrapper

    def invoke(self, script: Path, args, *, home: Path, cwd: Path, timeout=600):
        """Run a real script entrypoint with $HOME pointed at a fake home."""
        env = os.environ.copy()
        env["HOME"] = str(home)
        env["DOTFILES_E2E_HOME"] = str(home)
        env["DOTFILES_ALLOW_ROOT"] = "0"

        if self.platform == "unix":
            cmd = ["bash", script, *[str(a) for a in args]]
            rc, out = run(cmd, cwd=cwd, env=env, check_rc=False, timeout=timeout)
        else:
            check(self.pwsh is not None, "no pwsh/powershell interpreter found")
            wrapper = self._ps_wrapper(script, args, home)
            cmd = [self.pwsh, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", wrapper]
            rc, out = run(cmd, cwd=cwd, env=env, check_rc=False, timeout=timeout)
        return rc, out


# --------------------------------------------------------------------------- #
# Filesystem helpers
# --------------------------------------------------------------------------- #

def set_age_days(path: Path, days: float) -> None:
    stamp = time.time() - days * 86400
    os.utime(path, (stamp, stamp))


def make_reparse(link: Path, target: Path) -> bool:
    """Create a symlink (POSIX) or junction (Windows) named ``link``."""
    if IS_WINDOWS:
        rc, _ = run(["cmd", "/c", "mklink", "/J", link, target], cwd=link.parent, check_rc=False)
        ok = rc == 0
    else:
        try:
            os.symlink(target, link, target_is_directory=True)
            ok = True
        except OSError:
            ok = False
    if ok:
        CREATED_REPARSE.append(link)
    return ok


def remove_reparse(link: Path) -> None:
    try:
        os.unlink(link)
        return
    except OSError:
        pass
    try:
        os.rmdir(link)
    except OSError:
        pass


def safe_rmtree(path: Path) -> None:
    for link in list(CREATED_REPARSE):
        if os.path.lexists(link):
            remove_reparse(link)
    CREATED_REPARSE.clear()
    shutil.rmtree(path, ignore_errors=True)


# --------------------------------------------------------------------------- #
# Update scenarios
# --------------------------------------------------------------------------- #

BASH_BOOTSTRAP = """#!/usr/bin/env bash
set -euo pipefail
home="${DOTFILES_E2E_HOME:?DOTFILES_E2E_HOME not set}"
mkdir -p "$home/.e2e-bootstrap/linked"
printf 'v1\\n' > "$home/.e2e-bootstrap/applied"
"""

PS_BOOTSTRAP = """$ErrorActionPreference = 'Stop'
$fakeHome = $env:DOTFILES_E2E_HOME
if (-not $fakeHome) { throw 'DOTFILES_E2E_HOME not set' }
$dir = Join-Path $fakeHome '.e2e-bootstrap'
New-Item -ItemType Directory -Force -Path (Join-Path $dir 'linked') | Out-Null
Set-Content -Path (Join-Path $dir 'applied') -Value 'v1'
"""


def _applied_marker(home: Path) -> Path:
    return home / ".e2e-bootstrap" / "applied"


def run_update_scenarios(runner: Runner, ws: Path) -> None:
    log("update: setting up local git remote and checkout")
    base = ws / "update"
    bare = base / "remote.git"
    seed = base / "author"
    user = base / "checkout"
    fake_home = base / "home"
    for d in (base, fake_home):
        d.mkdir(parents=True, exist_ok=True)

    git(["init", "--bare", str(bare)], cwd=base)
    git(["-C", str(bare), "symbolic-ref", "HEAD", "refs/heads/main"], cwd=base)
    git(["clone", str(bare), str(seed)], cwd=base)
    git(["-C", str(seed), "config", "user.email", "e2e@example.invalid"], cwd=base)
    git(["-C", str(seed), "config", "user.name", "Dotfiles E2E"], cwd=base)

    # The checkout carries the real scripts under test plus a deterministic
    # fixture bootstrap that records its effect in the fake HOME.
    shutil.copytree(REPO_ROOT / "scripts", seed / "scripts")
    (seed / "config").mkdir(parents=True, exist_ok=True)
    (seed / "config" / "keep.txt").write_text("keep\n", encoding="utf-8")
    (seed / "bootstrap.sh").write_text(BASH_BOOTSTRAP, encoding="utf-8")
    (seed / "bootstrap.sh").chmod(0o755)
    (seed / "bootstrap.ps1").write_text(PS_BOOTSTRAP, encoding="utf-8")
    git(["-C", str(seed), "add", "-A"], cwd=base)
    git(["-C", str(seed), "commit", "-m", "seed checkout"], cwd=base)
    git(["-C", str(seed), "push", "origin", "main"], cwd=base)

    git(["clone", str(bare), str(user)], cwd=base)
    git(["-C", str(user), "config", "user.email", "e2e@example.invalid"], cwd=base)
    git(["-C", str(user), "config", "user.name", "Dotfiles E2E"], cwd=base)
    update = user / "scripts" / f"update{runner.ext}"
    check(update.is_file(), f"update script not found in checkout: {update}")

    def advance(change: str) -> None:
        (seed / f"{change}.txt").write_text(change + "\n", encoding="utf-8")
        git(["-C", str(seed), "add", "-A"], cwd=base)
        git(["-C", str(seed), "commit", "-m", change], cwd=base)
        git(["-C", str(seed), "push", "origin", "main"], cwd=base)

    def head() -> str:
        return git_out(["-C", str(user), "rev-parse", "HEAD"], cwd=base)

    def origin_head() -> str:
        return git_out(["-C", str(seed), "rev-parse", "HEAD"], cwd=base)

    def invoke_update(args, timeout=120):
        return runner.invoke(update, args, home=fake_home, cwd=user, timeout=timeout)

    # --- help exits 0 ----------------------------------------------------- #
    help_arg = "-Help" if runner.platform == "windows" else "--help"
    rc, out = invoke_update([help_arg])
    check(rc == 0, f"update {help_arg} must exit 0 (rc={rc}): {out}")
    check("usage" in out.lower(), f"update {help_arg} did not print usage: {out}")

    # --- origin advances, checkout pulls, bootstrap re-applies ------------ #
    advance("change-1")
    before = head()
    check(before != origin_head(), "test setup: checkout should be behind origin")
    rc, out = invoke_update([])
    check(rc == 0, f"update must succeed (rc={rc}): {out}")
    check(head() == origin_head(), f"update did not fast-forward HEAD to origin\n{out}")
    check(_applied_marker(fake_home).is_file(), "bootstrap did not run during update")

    # --- repeat run is idempotent and re-applies ------------------------- #
    _applied_marker(fake_home).unlink()
    rc, out = invoke_update([])
    check(rc == 0, f"second update must succeed (rc={rc}): {out}")
    check(head() == origin_head(), "a repeat update moved HEAD unexpectedly")
    check(_applied_marker(fake_home).is_file(), "bootstrap was not re-applied on repeat run")

    # --- --no-bootstrap pulls but does not re-apply ----------------------- #
    advance("change-2")
    _applied_marker(fake_home).unlink()
    no_boot = "-NoBootstrap" if runner.platform == "windows" else "--no-bootstrap"
    rc, out = invoke_update([no_boot])
    check(rc == 0, f"update {no_boot} must succeed (rc={rc}): {out}")
    check(head() == origin_head(), "update --no-bootstrap did not pull")
    check(not _applied_marker(fake_home).exists(), "bootstrap ran despite --no-bootstrap")

    # --- refusals bail without pulling ------------------------------------ #
    advance("change-3")
    kept_head = head()
    behind = origin_head()
    check(kept_head != behind, "test setup: checkout should be behind origin for refusal tests")

    # dirty working tree
    (user / "config" / "keep.txt").write_text("dirty\n", encoding="utf-8")
    rc, out = invoke_update([])
    check(rc != 0, "a dirty working tree must be refused")
    check("not clean" in out, f"dirty-tree refusal message missing: {out}")
    check(head() == kept_head, "a refused update with a dirty tree still pulled")
    git(["-C", str(user), "checkout", "--", "config/keep.txt"], cwd=base)

    # wrong branch
    git(["-C", str(user), "checkout", "-b", "sidebranch"], cwd=base)
    rc, out = invoke_update([])
    check(rc != 0, "an unexpected branch must be refused")
    check("expected" in out, f"wrong-branch refusal message missing: {out}")
    check(head() == kept_head, "a refused update on the wrong branch still pulled")
    git(["-C", str(user), "checkout", "main"], cwd=base)

    # detached HEAD
    git(["-C", str(user), "checkout", "--detach"], cwd=base)
    rc, out = invoke_update([])
    check(rc != 0, "a detached HEAD must be refused")
    check("detached" in out, f"detached-HEAD refusal message missing: {out}")
    check(head() == kept_head, "a refused update on a detached HEAD still pulled")
    git(["-C", str(user), "checkout", "main"], cwd=base)

    log("update: all scenarios passed")


# --------------------------------------------------------------------------- #
# Cleanup scenarios
# --------------------------------------------------------------------------- #

def run_cleanup_scenarios(runner: Runner, ws: Path) -> None:
    log("cleanup: setting up fake HOME with backup directories")
    base = ws / "cleanup"
    home = base / "home"
    outside = base / "outside"
    for d in (home / ".config" / "opencode", outside):
        d.mkdir(parents=True, exist_ok=True)

    old_managed = home / ".dotfiles_backup_20200101000000"
    old_suffixed = home / ".dotfiles_backup_20200102000000.1"
    recent_managed = home / ".dotfiles_backup_20260101000000"
    unmanaged = home / ".dotfiles_backup_notes"
    outside_backup = outside / ".dotfiles_backup_20200105000000"
    for d in (old_managed, old_suffixed, recent_managed, unmanaged, outside_backup):
        d.mkdir(parents=True, exist_ok=True)
    set_age_days(old_managed, 100)
    set_age_days(old_suffixed, 100)
    set_age_days(unmanaged, 100)
    set_age_days(outside_backup, 100)
    # recent_managed keeps its just-created mtime (well within the threshold).
    set_age_days(recent_managed, 0)

    opencode = home / ".config" / "opencode" / "opencode.json"
    opencode.write_text('{"keep":true}\n', encoding="utf-8")

    reparse = home / ".dotfiles_backup_20200103000000"
    have_reparse = make_reparse(reparse, recent_managed)
    if not have_reparse:
        log("cleanup: SKIP reparse-point assertions (cannot create symlink/junction)")

    cleanup = runner.script("cleanup")
    check(cleanup.is_file(), f"cleanup script not found: {cleanup}")

    def invoke_cleanup(args, timeout=120):
        return runner.invoke(cleanup, args, home=home, cwd=base, timeout=timeout)

    help_arg = "-Help" if runner.platform == "windows" else "--help"
    apply_arg = "-Apply" if runner.platform == "windows" else "--apply"
    age_flag = "-MinAgeDays" if runner.platform == "windows" else "--min-age-days"

    # --- help exits 0 ----------------------------------------------------- #
    rc, out = invoke_cleanup([help_arg])
    check(rc == 0, f"cleanup {help_arg} must exit 0 (rc={rc}): {out}")
    check("usage" in out.lower(), f"cleanup {help_arg} did not print usage: {out}")

    # --- dry run lists stale dirs and removes nothing --------------------- #
    rc, out = invoke_cleanup([])
    check(rc == 0, f"cleanup dry run must exit 0 (rc={rc}): {out}")
    check("dry run" in out.lower(), f"dry run did not report that nothing was removed: {out}")
    check(old_managed.name in out, "dry run did not list the stale managed backup")
    check(old_suffixed.name in out, "dry run did not list the stale suffixed backup")
    check(recent_managed.name not in out, "dry run listed a too-recent backup")
    check(unmanaged.name not in out, "dry run listed an unrecognized-name directory")
    check(old_managed.is_dir() and old_suffixed.is_dir(), "a dry run removed a directory")

    # --- apply removes only managed dirs older than the threshold --------- #
    rc, out = invoke_cleanup([apply_arg])
    check(rc == 0, f"cleanup {apply_arg} must exit 0 (rc={rc}): {out}")
    check(not old_managed.exists(), "apply did not remove the stale managed backup")
    check(not old_suffixed.exists(), "apply did not remove the stale suffixed backup")
    check(recent_managed.is_dir(), "apply removed a too-recent backup")
    check(unmanaged.is_dir(), "apply removed an unrecognized-name directory")
    check(outside_backup.is_dir(), "apply removed a directory outside HOME")
    if have_reparse:
        check(os.path.lexists(reparse), "apply removed a symlink/junction")
    check(opencode.read_text(encoding="utf-8") == '{"keep":true}\n',
          "cleanup modified a file under ~/.config")

    # --- second apply is idempotent --------------------------------------- #
    rc, out = invoke_cleanup([apply_arg])
    check(rc == 0, f"a second cleanup {apply_arg} must exit 0 (rc={rc}): {out}")
    check("no stale" in out.lower(), f"a second apply run should find nothing: {out}")
    check(recent_managed.is_dir() and unmanaged.is_dir(), "a second apply run removed kept directories")

    # --- age threshold ---------------------------------------------------- #
    aged = home / ".dotfiles_backup_20200104000000"
    aged.mkdir(parents=True, exist_ok=True)
    set_age_days(aged, 100)

    rc, out = invoke_cleanup([apply_arg, age_flag, "3650"])
    check(rc == 0, f"cleanup with a high threshold must exit 0 (rc={rc}): {out}")
    check(aged.is_dir(), "a backup younger than the threshold was removed")

    rc, out = invoke_cleanup([apply_arg, age_flag, "1"])
    check(rc == 0, f"cleanup with a low threshold must exit 0 (rc={rc}): {out}")
    check(not aged.exists(), "a backup older than the threshold was not removed")

    log("cleanup: all scenarios passed")


# --------------------------------------------------------------------------- #
# Optional real-bootstrap scenario (network; container/weekly only)
# --------------------------------------------------------------------------- #

def run_real_bootstrap_scenario(runner: Runner, ws: Path) -> None:
    log("real-bootstrap: running the real bootstrap.sh to create genuine backups")
    check(runner.platform == "unix", "--real-bootstrap is only supported on Linux")
    base = ws / "real-bootstrap"
    home = base / "home"
    (home / ".config" / "Code" / "User").mkdir(parents=True, exist_ok=True)
    (home / ".config" / "opencode").mkdir(parents=True, exist_ok=True)
    (home / ".claude").mkdir(parents=True, exist_ok=True)
    conflicts = {
        home / ".gitconfig": "[user]\n\tname = E2E\n",
        home / ".bashrc": "# pre-existing bashrc\n",
        home / ".bash_aliases": "# pre-existing aliases\n",
        home / ".inputrc": "# pre-existing inputrc\n",
        home / ".config" / "Code" / "User" / "settings.json": "{}\n",
        home / ".config" / "opencode" / "opencode.json": "{}\n",
        home / ".claude" / "settings.json": "{}\n",
    }
    for path, content in conflicts.items():
        path.write_text(content, encoding="utf-8")

    env = os.environ.copy()
    env["HOME"] = str(home)
    env["DOTFILES_E2E_HOME"] = str(home)
    env["DOTFILES_ALLOW_ROOT"] = "0"
    rc, out = run(["bash", REPO_ROOT / "bootstrap.sh"], cwd=REPO_ROOT, env=env,
                  check_rc=False, timeout=2400)
    check(rc == 0, f"real bootstrap.sh failed (rc={rc}):\n{out}")

    backups = sorted(home.glob(".dotfiles_backup_*"))
    check(backups, f"real bootstrap did not create a .dotfiles_backup_* directory under {home}")
    backup = backups[0]
    check(any(backup.rglob("*")), "the real bootstrap backup directory is empty")
    log(f"real-bootstrap: created {backup.name}")

    # Age the genuine backup so cleanup will consider it, then run the real
    # cleanup script against it.
    set_age_days(backup, 100)
    cleanup = runner.script("cleanup")
    rc, out = runner.invoke(cleanup, [], home=home, cwd=base, timeout=120)
    check(rc == 0, f"cleanup dry run on a real backup must exit 0 (rc={rc}): {out}")
    check(backup.name in out, f"cleanup did not list the real backup: {out}")

    apply_arg = "--apply"
    rc, out = runner.invoke(cleanup, [apply_arg], home=home, cwd=base, timeout=120)
    check(rc == 0, f"cleanup apply on a real backup must exit 0 (rc={rc}): {out}")
    check(not backup.exists(), "cleanup did not remove the real bootstrap backup")

    log("real-bootstrap: all scenarios passed")


# --------------------------------------------------------------------------- #
# Entry point
# --------------------------------------------------------------------------- #

def parse_args(argv):
    parser = argparse.ArgumentParser(description="End-to-end tests for the update/cleanup scripts")
    parser.add_argument(
        "--platform",
        choices=["auto", "unix", "windows"],
        default="auto",
        help="Which script family to drive. 'auto' uses .ps1 on Windows, .sh elsewhere.",
    )
    parser.add_argument(
        "--real-bootstrap",
        action="store_true",
        help="Also run the real bootstrap.sh against a fake HOME (needs network; container/weekly only).",
    )
    parser.add_argument(
        "--keep",
        action="store_true",
        help="Keep the temp workspace for debugging.",
    )
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    platform = args.platform
    if platform == "auto":
        platform = "windows" if IS_WINDOWS else "unix"
    runner = Runner(platform)
    log(f"platform={runner.platform} scripts={runner.ext} repo={REPO_ROOT}")
    if runner.platform == "windows":
        check(runner.pwsh is not None, "no pwsh/powershell interpreter found")

    ws = Path(tempfile.mkdtemp(prefix="dotfiles-e2e-"))
    log(f"workspace={ws}")
    failed = True
    try:
        run_update_scenarios(runner, ws)
        run_cleanup_scenarios(runner, ws)
        if args.real_bootstrap:
            run_real_bootstrap_scenario(runner, ws)
        failed = False
    finally:
        if args.keep or failed:
            log(f"keeping workspace: {ws}")
        else:
            safe_rmtree(ws)
        runner.cleanup()

    print(f"PASS: e2e update+cleanup ({runner.platform})", flush=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except E2EFailure:
        sys.exit(1)
