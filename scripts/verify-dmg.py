"""Read-only verification of the packaged app and Finder layout; no GUI."""
from pathlib import Path
import hashlib
import os
import subprocess
import sys
import tempfile

from ds_store import DSStore

image, source_app = (Path(arg).resolve() for arg in sys.argv[1:])
mount = Path(tempfile.mkdtemp(prefix="pixel-dmg-check-"))
attached = False
try:
    subprocess.run([
        "hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen",
        "-mountpoint", str(mount), str(image),
    ], check=True, stdout=subprocess.DEVNULL)
    attached = True
    if os.readlink(mount / "Программы") != "/Applications":
        raise ValueError("Invalid Applications link")
    app = mount / source_app.name
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    executable = Path("Contents/MacOS/PixelTransfer")
    def digest(path):
        return hashlib.sha256(path.read_bytes()).digest()
    if digest(app / executable) != digest(source_app / executable):
        raise ValueError("Packaged executable differs from the build")
    with DSStore.open(str(mount / ".DS_Store"), "r") as store:
        if store[source_app.name]["Iloc"] != (240, 100) or store["Программы"]["Iloc"] != (720, 100):
            raise ValueError("Invalid icon positions")
        settings = store["."]["icvp"]
        if settings["backgroundType"] != 2 or not settings["backgroundImageAlias"]:
            raise ValueError("Missing Finder background")
        if settings["iconSize"] != 96:
            raise ValueError("Invalid icon size")
        print("Finder window:", store["."]["bwsp"]["WindowBounds"])
    if not (mount / ".background.tiff").is_file():
        raise ValueError("Missing background image")
    print("DMG app signature, executable, Applications link, background and layout: OK")
finally:
    if attached:
        subprocess.run(["hdiutil", "detach", str(mount)], check=True, stdout=subprocess.DEVNULL)
    mount.rmdir()
