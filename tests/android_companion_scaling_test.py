"""Run the companion's ROM-free Java geometry, filter and routing checks."""
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
JAVA = ROOT / "mobile/android/love/src/main/java/org/love2d/android"
CASES = ("FramePlacement", "FrameFilter", "SecondaryFrameRouter")


def main():
    with tempfile.TemporaryDirectory(prefix="companion-scaling-") as output:
        sources = [str(JAVA / f"{case}.java") for case in CASES]
        sources += [str(ROOT / "tests/android" / f"{case}Test.java") for case in CASES]
        subprocess.run(["javac", "-d", output, *sources], check=True)
        for case in CASES:
            subprocess.run(["java", "-cp", output, f"org.love2d.android.{case}Test"], check=True)


if __name__ == "__main__":
    main()
