#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
import json
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src/macos-p0"))
from session import Session


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def tests(out, record, sign, *, gui=False, faults=False, cycles=2):
    app = out / "Husk P0 Runner.app"
    executable = app / "Contents/MacOS/NativeRunner"
    apk = out / "fixtures.apk"
    sessions = out / "sessions"

    def new(**kwargs):
        return Session(executable, apk, sessions, test_controls=True, show_window=gui, **kwargs)

    def check(name, fn):
        begin = time.monotonic()
        try:
            detail = fn()
        except BaseException:
            record.append(dict(name=name, passed=False, seconds=round(time.monotonic() - begin, 3)))
            print(f"FAIL {name}", flush=True)
            raise
        record.append(dict(name=name, passed=True, seconds=round(time.monotonic() - begin, 3), detail=detail))
        print(f"PASS {name}", flush=True)

    def normal():
        with new() as s:
            s.start()
            # Activation is asynchronous; observe the actual AppKit state.
            deadline = time.monotonic() + 3
            while True:
                s.send("status")
                window = s.wait_for(event="window")
                if not gui or all(window[k] for k in ["visible", "key", "main", "active", "menu"]):
                    break
                assert time.monotonic() < deadline, window
                time.sleep(0.05)
            assert window["ownerPID"] == s.process.pid
            if gui:
                assert window["windowNumber"] > 0 and not window["headless"]
            else:
                assert window["headless"] and window["windowNumber"] == 0
                assert not any(window[k] for k in ["visible", "key", "main", "active", "menu"])
            s.send("menu-pause" if gui else "pause")
            paused = s.wait_for(state="paused", event="state")
            time.sleep(0.2)
            s.send("status")
            assert s.wait_for(event="window")["ticks"] == paused["ticks"]
            s.send("resume")
            s.wait_for(state="running", event="state")
            time.sleep(0.1)
            s.send("status")
            assert s.wait_for(event="window")["ticks"] > paused["ticks"]
            s.send("stop", session="old-session")
            s.wait_for(event="rejected")
            assert s.state == "running"
            assert not s.accept(dict(session="old-session", event="state", state="exited"))
            assert s.state == "running" and s.discarded == 1
            s.stop()
            assert s.state == "exited" and s.saved and not s.forced
            assert not alive(s.process.pid)
            assert not list(s.directory.glob("*.tmp"))
            return dict(session=s.id, pid=s.process.pid, window=window, log=str(s.directory.relative_to(out)))
    check(f"runner-{'window-menu' if gui else 'headless'}-pause-resume-stale-checkpoint", normal)

    def stop_starting():
        with new() as s:
            s.stop()
            assert s.state == "exited" and s.saved and not s.forced
            return dict(session=s.id, states=[e["state"] for e in s.events if e["event"] == "state"])
    check("runner-stop-during-startup", stop_starting)

    for command in (["window-close", "menu-quit"] if gui else []):
        def close_action(command=command):
            with new() as s:
                s.start(); s.send(command)
                assert s.wait_exit() == 0 and s.state == "exited" and s.saved
                assert s.events[-1]["reason"] == command
                return dict(session=s.id, reason=command)
        check(f"runner-{command}", close_action)

    def crash():
        with new() as s:
            s.start(); s.send("crash")
            assert s.wait_exit() != 0 and s.state == "failed" and not s.saved
            pid = s.process.pid
        with new() as again:
            again.start(); again.stop()
            assert again.process.pid != pid and again.state == "exited"
            return dict(crashed_pid=pid, restarted_pid=again.process.pid)
    if faults:
        check("runner-crash-isolation-restart", crash)

    def hung():
        with new() as s:
            s.start(); s.send("hang-stop"); s.wait_for(event="test-armed")
            begin = time.monotonic(); s.stop(timeout=0.5)
            assert s.forced and s.state == "failed" and not s.saved
            assert s.process.returncode == -9 and time.monotonic() - begin < 3
            assert not alive(s.process.pid)
            return dict(session=s.id, forced=True, exit=s.process.returncode)
    if faults:
        check("runner-stop-timeout-term-kill-reap", hung)

    def failed_save():
        with new(checkpoint=out / "nonexistent-parent/checkpoint.json") as s:
            s.start(); s.stop()
            assert s.state == "failed" and not s.saved and not s.forced
            assert s.events[-1]["reason"] == "checkpoint-failed"
            return dict(session=s.id, exit=s.process.returncode)
    check("runner-checkpoint-failure", failed_save)

    def missing_permission():
        target = out / "NativeRunner-without-entitlement"
        shutil.copy2(executable, target)
        sign(target, out / "jit.plist")
        with Session(target, apk, sessions) as s:
            assert s.wait_exit() == 70 and s.state == "failed" and not s.saved
            assert s.events[-1]["reason"] == "missing-unsigned-executable-memory-entitlement"
            return dict(session=s.id, graceful=True)
    check("runner-entitlement-preflight", missing_permission)

    for hung_main in ([False, True] if faults else []):
        def parent_exit(hung_main=hung_main):
            # A separate controller process dies without a cleanup handler.
            parent = subprocess.Popen([sys.executable, __file__, "--orphan", str(executable), str(apk),
                str(sessions), str(int(hung_main))], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            pid = None
            try:
                with selectors.DefaultSelector() as sel:
                    sel.register(parent.stdout, selectors.EVENT_READ)
                    assert sel.select(15), "orphan controller did not start"
                    line = parent.stdout.readline()
                    if not line:
                        parent.wait(timeout=3)
                        diagnostic = parent.stderr.read().decode()
                        (out / "orphan-controller-failure.log").write_text(diagnostic)
                        raise AssertionError(diagnostic)
                    started = json.loads(line)
                pid = started["pid"]
                parent.kill(); parent.wait(timeout=3)
                until = time.monotonic() + 5
                while alive(pid) and time.monotonic() < until:
                    time.sleep(0.05)
                assert not alive(pid), "orphan Runner survived parent death"
                checkpoint = Path(started["checkpoint"])
                assert checkpoint.exists() != hung_main
                return dict(pid=pid, hung_main=hung_main, checkpoint=checkpoint.exists())
            finally:
                if parent.poll() is None:
                    parent.kill(); parent.wait(timeout=3)
                if pid and alive(pid):
                    os.kill(pid, 9)
                parent.stdin.close(); parent.stdout.close(); parent.stderr.close()
        check(f"runner-parent-death-{'hung' if hung_main else 'normal'}", parent_exit)

    def start_stop_cycles():
        ids, pids = set(), []
        for _ in range(cycles):
            with new() as s:
                s.start(); s.stop()
                assert s.state == "exited" and s.saved and not s.forced
                assert s.id not in ids
                ids.add(s.id); pids.append(s.process.pid)
        assert len(ids) == cycles and all(not alive(pid) for pid in pids)
        return dict(cycles=cycles, headless=not gui, pids=pids, remaining=0)
    check(f"runner-{cycles}-start-stop-cycles", start_stop_cycles)


if __name__ == "__main__" and sys.argv[1] == "--orphan":
    _, _, executable, apk, directory, hung = sys.argv
    s = Session(executable, apk, directory, test_controls=True)
    s.start()
    if hung == "1":
        s.send("hang-main"); s.wait_for(event="test-armed")
    print(json.dumps(dict(pid=s.process.pid, checkpoint=str(s.checkpoint))), flush=True)
    sys.stdin.buffer.read(1)
    os._exit(0)
