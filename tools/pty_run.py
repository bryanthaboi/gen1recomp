import os
import pty
import signal
import sys


def main():
    argv = sys.argv[1:]
    if not argv or argv[0] in ("-h", "--help"):
        text = (
            "usage: python3 tools/pty_run.py <command> [args...]\n"
            "Runs the command on a pty in its own session, kills that process group\n"
            "on SIGALRM/SIGTERM/SIGINT/SIGHUP (exit 124 on alarm, 128+sig otherwise)\n"
            "and passes the child's exit status through. Typical use:\n"
            "  perl -e 'alarm 300; exec @ARGV' python3 tools/pty_run.py love .\n"
        )
        if argv:
            sys.stdout.write(text)
            sys.exit(0)
        sys.stderr.write(text)
        sys.exit(2)
    pid, fd = pty.fork()
    if pid == 0:
        try:
            os.execvp(argv[0], argv)
        finally:
            os._exit(127)

    def reap(signum, _frame):
        try:
            os.killpg(pid, signal.SIGKILL)
        except OSError:
            pass
        try:
            os.waitpid(pid, 0)
        except OSError:
            pass
        sys.stdout.write("\npty_run: %s killed %s after signal %d\n" % (argv[0], pid, signum))
        sys.stdout.flush()
        os._exit(124 if signum == signal.SIGALRM else 128 + signum)

    for sig in (signal.SIGALRM, signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, reap)

    out = sys.stdout.buffer
    while True:
        try:
            chunk = os.read(fd, 4096)
        except InterruptedError:
            continue
        except OSError:
            break
        if not chunk:
            break
        out.write(chunk)
        out.flush()
    _, status = os.waitpid(pid, 0)
    try:
        os.killpg(pid, signal.SIGKILL)
    except OSError:
        pass
    if os.WIFEXITED(status):
        sys.exit(os.WEXITSTATUS(status))
    if os.WIFSIGNALED(status):
        sys.exit(128 + os.WTERMSIG(status))
    sys.exit(1)


if __name__ == "__main__":
    main()
