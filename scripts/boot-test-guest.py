#!/usr/bin/env python3
"""Runs a shell script inside a running VM and prints what it printed.

Usage: boot-test-guest.py <guest agent socket> <script file> <seconds to wait for the VM> <seconds to wait for the script> [arguments for the script...]

The VM is reached through the QEMU guest agent (the image installs it). QEMU offers the agent
as a socket file on the machine that runs the VM. The script is run as root with bash.

Exit code: the exit code of the script, or 98 when the VM never answered, or 99 when the script
did not end in time.
"""
import base64
import json
import socket
import sys
import time


class Agent:
    def __init__(self, path):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(path)
        self.buffer = b""

    def _read_line(self, timeout):
        """One line from the agent, or None when nothing came in time."""
        deadline = time.monotonic() + timeout
        while b"\n" not in self.buffer:
            left = deadline - time.monotonic()
            if left <= 0:
                return None
            self.sock.settimeout(left)
            try:
                data = self.sock.recv(65536)
            except socket.timeout:
                return None
            if not data:
                time.sleep(0.2)
                continue
            self.buffer += data
        line, self.buffer = self.buffer.split(b"\n", 1)
        return line

    def call(self, execute, arguments=None, timeout=30):
        """Sends one command. Returns its answer, or None when no answer came in time."""
        request = {"execute": execute}
        if arguments is not None:
            request["arguments"] = arguments
        self.sock.sendall(json.dumps(request).encode() + b"\n")
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            line = self._read_line(deadline - time.monotonic())
            if line is None:
                return None
            try:
                # 0xff bytes can come before an answer: they only mark its start
                answer = json.loads(line.replace(b"\xff", b"").decode(errors="replace"))
            except ValueError:
                continue
            if isinstance(answer, dict) and ("return" in answer or "error" in answer):
                return answer
        return None

    def wait_until_up(self, seconds):
        """True when the agent in the VM answers. An old answer is never taken for a new one."""
        deadline = time.monotonic() + seconds
        number = int(time.time()) % 100000
        while time.monotonic() < deadline:
            number += 1
            answer = self.call("guest-sync", {"id": number}, timeout=5)
            # an answer to an earlier try can still be on its way: read until this number comes
            while answer is not None and answer.get("return") != number:
                line = self._read_line(2)
                if line is None:
                    answer = None
                    break
                try:
                    answer = json.loads(line.replace(b"\xff", b"").decode(errors="replace"))
                except ValueError:
                    answer = {}
            if answer is not None:
                return True
            time.sleep(3)
        return False


def main():
    if len(sys.argv) < 5:
        print(__doc__, file=sys.stderr)
        return 2
    path, script_file = sys.argv[1], sys.argv[2]
    wait_vm, wait_script = int(sys.argv[3]), int(sys.argv[4])
    script_arguments = sys.argv[5:]

    agent = Agent(path)
    if not agent.wait_until_up(wait_vm):
        print(f"boot-test-guest: the VM did not answer within {wait_vm} seconds", file=sys.stderr)
        return 98

    with open(script_file, "rb") as handle:
        script = handle.read()

    started = agent.call("guest-exec", {
        "path": "/bin/bash",
        "arg": ["-s", "--"] + script_arguments,
        "input-data": base64.b64encode(script).decode(),
        "capture-output": True,
    })
    if not started or "return" not in started:
        print(f"boot-test-guest: the script could not be started in the VM: {started}", file=sys.stderr)
        return 98
    pid = started["return"]["pid"]

    deadline = time.monotonic() + wait_script
    while time.monotonic() < deadline:
        status = agent.call("guest-exec-status", {"pid": pid})
        if status and status.get("return", {}).get("exited"):
            result = status["return"]
            sys.stdout.write(base64.b64decode(result.get("out-data", "")).decode(errors="replace"))
            sys.stderr.write(base64.b64decode(result.get("err-data", "")).decode(errors="replace"))
            return int(result.get("exitcode", 1))
        time.sleep(5)

    print(f"boot-test-guest: the script did not end within {wait_script} seconds", file=sys.stderr)
    return 99


if __name__ == "__main__":
    sys.exit(main())
