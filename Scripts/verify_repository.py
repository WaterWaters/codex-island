#!/usr/bin/env python3
"""Check the public Git file set and local Markdown links without dependencies."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
FORBIDDEN_ROOTS = {"local", "build", ".build", ".swiftpm", ".codebase-memory", "artifacts"}
MEDIA = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".icns", ".mp4", ".mov"}
PUBLIC_MEDIA = {"Artwork/AppIcon.png", "Artwork/AppIcon.icns", "docs/assets/banner.png"}
PRIVATE_SUFFIXES = {".sqlite", ".db", ".jsonl", ".p12", ".p8", ".pem", ".key", ".mobileprovision"}


class References(HTMLParser):
    def __init__(self):
        super().__init__()
        self.values = []

    def handle_starttag(self, tag, attrs):
        self.values.extend(v for k, v in attrs if k in {"src", "href"} and v)


def main():
    raw = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "."], cwd=ROOT
    )
    names = sorted(set(filter(None, raw.decode().split("\0"))))
    errors = []
    links = 0
    for name in names:
        path = ROOT / name
        parts = Path(name).parts
        if (parts[0] in FORBIDDEN_ROOTS or "__pycache__" in parts or "CurrentPet" in parts
                or path.name == "native-preview.png" or path.suffix in PRIVATE_SUFFIXES
                or path.name == ".env" or path.name.startswith(".env.") and path.name != ".env.example"
                or ".sqlite-" in path.name or ".db-" in path.name):
            errors.append(f"Private/generated path: {name}")
        if path.is_symlink() or not path.is_file():
            errors.append(f"Not a regular source file: {name}")
            continue
        if path.suffix in MEDIA:
            if name not in PUBLIC_MEDIA:
                errors.append(f"Media is not on the public brand-asset allowlist: {name}")
            continue
        try:
            text = path.read_text()
        except UnicodeDecodeError:
            errors.append(f"Unexpected binary source file: {name}")
            continue
        if re.search(r"gh[pousr]_[A-Za-z0-9_]{30,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----", text):
            errors.append(f"Possible embedded credential: {name}")
        if any(line.rstrip() != line for line in text.splitlines()):
            errors.append(f"Trailing whitespace: {name}")
        if path.suffix != ".md":
            continue
        html = References()
        html.feed(text)
        refs = re.findall(r"!?\[[^\]]*\]\(([^)]+)\)", text) + html.values
        for ref in refs:
            url = urlsplit(ref)
            if url.scheme or ref.startswith("//"):
                continue
            target = (path.parent / unquote(url.path)).resolve() if url.path else path
            links += 1
            if not target.is_relative_to(ROOT) or not target.exists():
                errors.append(f"Broken/outside local link in {name}: {ref}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Public source check passed: {len(names)} files; {links} local Markdown links.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
