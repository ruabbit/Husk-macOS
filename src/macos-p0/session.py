#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""P0 process supervisor. P1 will move this contract into the native main app."""
import argparse
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import time
import uuid


class Session:
    transitions = {None: {"starting"}, "starting": {"running", "stopping", "failed"},
                   "running": {"paused", "stopping", "failed"},
                   "paused": {"running", "stopping", "failed"},
                   "stopping": {"exited", "failed"}, "exited": set(), "failed": set()}

    def __init__(self, executable, apk, directory, *, test_controls=False, checkpoint=None, show_window=False):
        self.id = str(uuid.uuid4())
        self.directory = Path(directory) / self.id
        self.directory.mkdir(parents=True)
        self.checkpoint = Path(checkpoint) if checkpoint else self.directory / "checkpoint.json"
        self.events, self.buffer = [], b""
        self.state, self.sequence, self.discarded = None, 0, 0
        self.saved, self.forced, self.closed = False, False, False
        self.protocol_error = None
        self.error_log = (self.directory / "stderr.log").open("wb")
        env = {k: v for k, v in os.environ.items() if not k.startswith("TL_")}
        args = [str(executable), "--session", self.id, "--apk", str(apk), "--checkpoint", str(self.checkpoint)]
        if test_controls:
            args.append("--test-controls")
        args.append("--show-window" if show_window else "--headless")
        try:
            self.process = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                            stderr=self.error_log, start_new_session=True, env=env)
        except BaseException:
            self.error_log.close()
            raise
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)

    def accept(self, event):
        """Reject late callbacks from another session before touching current state."""
        if not isinstance(event, dict):
            raise RuntimeError("Runner event is not an object")
        if event.get("session") != self.id:
            self.discarded += 1
            return False
        if event.get("protocol") != 1 or event.get("pid") != self.process.pid or event.get("seq") != self.sequence + 1:
            raise RuntimeError("invalid Runner event envelope")
        self.sequence = event["seq"]
        if event.get("event") == "state":
            state = event["state"]
            if state not in self.transitions[self.state]:
                raise RuntimeError(f"invalid Runner transition {self.state} -> {state}")
            self.state = state
        elif event["state"] != self.state:
            raise RuntimeError("event state differs from acknowledged state")
        if event["event"] == "checkpoint":
            data = json.loads(self.checkpoint.read_text())
            if self.state != "stopping" or data.get("session") != self.id or data.get("ticks") != event["ticks"]:
                raise RuntimeError("checkpoint does not match this session")
            self.saved = event.get("saved") is True
        self.events.append(event)
        return True

    def pump(self, timeout=0.1):
        if not self.selector.get_map():
            return []
        incoming = []
        for key, _ in self.selector.select(timeout):
            chunk = os.read(key.fileobj.fileno(), 65536)
            if not chunk:
                self.selector.unregister(key.fileobj)
                if self.buffer:
                    raise RuntimeError("truncated Runner event")
                continue
            self.buffer += chunk
            if len(self.buffer) > 1024 * 1024:
                raise RuntimeError("oversized Runner event")
            while b"\n" in self.buffer:
                line, self.buffer = self.buffer.split(b"\n", 1)
                event = json.loads(line)
                if self.accept(event):
                    incoming.append(event)
        return incoming

    def send(self, command, *, session=None):
        data = {"protocol": 1, "session": session or self.id, "command": command}
        self.process.stdin.write((json.dumps(data) + "\n").encode())
        self.process.stdin.flush()

    def wait_for(self, *, state=None, event=None, timeout=10):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            for message in self.pump(min(0.1, max(0, deadline - time.monotonic()))):
                if (state is None or message["state"] == state) and (event is None or message["event"] == event):
                    return message
            if self.process.poll() is not None:
                self.reap()
                raise RuntimeError(f"Runner exited before {state or event}: {self.process.returncode}")
        raise TimeoutError(f"Runner did not reach {state or event}")

    def start(self):
        try:
            return self.wait_for(state="running", event="state")
        except BaseException:
            self.stop(timeout=1)
            raise

    def reap(self):
        """Only a reaped process plus a matching checkpoint is a clean exit."""
        code = self.process.poll()
        if code is None:
            return None
        # A descendant must not keep supervision blocked by inheriting stdout.
        deadline = time.monotonic() + 0.2
        while self.selector.get_map() and time.monotonic() < deadline:
            self.pump(0.01)
        if code != 0 or self.state != "exited" or not self.saved:
            self.state = "failed"
        return code

    def wait_exit(self, timeout=5):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self.pump(0.05)
            if self.process.poll() is not None:
                return self.reap()
        raise TimeoutError("Runner did not exit")

    def stop(self, timeout=2):
        if self.process.poll() is None:
            try:
                self.send("stop")
                self.wait_exit(timeout)
            except (BrokenPipeError, TimeoutError):
                pass
            except (RuntimeError, ValueError, KeyError) as error:
                self.protocol_error = str(error)
        if self.process.poll() is None:
            self.forced = True
            try:
                os.killpg(self.process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                self.process.wait(timeout=0.5)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(self.process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                self.process.wait(timeout=2)
        try:
            self.reap()
        except (RuntimeError, ValueError, KeyError) as error:
            self.protocol_error = str(error)
        if self.forced or self.protocol_error:
            self.state = "failed"
        return self.state

    def close(self):
        if self.closed:
            return
        try:
            self.stop()
        finally:
            (self.directory / "events.json").write_text(json.dumps(self.events, indent=2) + "\n")
            (self.directory / "result.json").write_text(json.dumps(dict(session=self.id, pid=self.process.pid,
                state=self.state, saved=self.saved, forced=self.forced, exit=self.process.poll(),
                discarded=self.discarded, protocol_error=self.protocol_error), indent=2) + "\n")
            self.selector.close()
            self.process.stdin.close()
            self.process.stdout.close()
            self.error_log.close()
            self.closed = True

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()


def main():
    root = Path(__file__).resolve().parents[2]
    out = root / "build/macos-p0"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=float, default=20)
    parser.add_argument("--show-window", action="store_true", help="Explicitly open and activate one AppKit window")
    args = parser.parse_args()
    with Session(out / "Husk P0 Runner.app/Contents/MacOS/NativeRunner", out / "fixtures.apk", out / "manual", show_window=args.show_window) as session:
        session.start()
        print(f"Runner PID={session.process.pid}, session={session.id}", flush=True)
        until = time.monotonic() + args.seconds
        while time.monotonic() < until and session.process.poll() is None:
            session.pump(0.1)
        session.stop()
        print(f"state={session.state}, checkpoint={session.saved}, logs={session.directory}")


if __name__ == "__main__":
    main()
