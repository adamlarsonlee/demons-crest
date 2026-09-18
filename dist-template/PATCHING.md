# Patching your ROM

This is a patch, not a game. You supply the game.

You need an unmodified dump of the **Japanese** release, *Demon's Blazon:
Makai-mura Monshou-hen*. The USA release, *Demon's Crest*, will **not** work —
it is a different build with a different code layout, and patching it produces
a ROM that does not boot. We cannot supply the ROM and will not link to one.

The right file is **2,097,152 bytes** with this SHA-1:

```
a6dc126a1da593d900b33eb74cf33403075e9525
```

If your file is 2,097,664 bytes it carries an extra 512-byte "copier header" on
the front. Method 1 below removes it for you. Other patchers may not, and that
is the single most common reason a patched ROM shows a black screen.

---

## Method 1 — one command, and it checks its work

Recommended, because it is the only method that tells you whether the result is
correct. Needs Python 3: macOS and Linux already have it; on Windows install it
from <https://www.python.org/downloads/> and tick "Add Python to PATH" during
setup.

Put your ROM in this folder, then:

```sh
python3 apply.py "Demon's Blazon.sfc"
```

On Windows, `py apply.py "Demon's Blazon.sfc"`.

It writes `Demon's Blazon_Practice.sfc` next to your ROM. Before touching
anything it confirms your ROM is the right one, removes a copier header if there
is one, and afterwards compares the result against the hash in
`DemonsBlazon_Practice.ips.sha1`. If it prints `verified`, what you have is
byte-for-byte the ROM we built and tested.

## Method 2 — no install, in a web browser

<https://www.marcrobledo.com/RomPatcher.js/> is an open-source patcher that runs
as JavaScript in the page.

1. **ROM file** — choose your Demon's Blazon ROM.
2. **Patch file** — choose `DemonsBlazon_Practice.ips` from this folder.
3. Leave **Fix ROM checksum** unticked. The patch already corrects the checksum,
   and re-fixing it may change bytes and make the result stop matching our hash.
4. Click **Apply patch** and save the file it produces.

Two caveats. It is somebody else's website, and we have not verified what it
does with the file you give it, so use your own judgement about handing it a
ROM. And its header removal is not something you can confirm from the interface
— if your ROM is the 2,097,664-byte kind, prefer Method 1.

## Method 3 — any other IPS patcher

Floating IPS (Windows) and MultiPatch (macOS) both apply IPS patches and are
widely used. Strip the copier header yourself first if your ROM has one.

## Checking any of the above

Whichever method you used, you can confirm the result. Compare the SHA-1 of your
patched ROM against the contents of `DemonsBlazon_Practice.ips.sha1`:

```sh
shasum -a 1 "Demon's Blazon_Practice.sfc"          # macOS / Linux
certutil -hashfile "Demons Blazon_Practice.sfc" SHA1   # Windows
```

They should be identical. If they are not, the patch went on wrong — start again
from a clean ROM with Method 1.

---

## If something goes wrong

**"this is not the ROM the patch was built against"** — you almost certainly have
the USA release. Check your ROM's own SHA-1 with the commands above and compare
it against the one at the top of this file. Note that a 2,097,664-byte file will
not match until its header is removed; `apply.py` does that and prints the
corrected hash, so trust its number over your own.

**Black screen, or it hangs on the Capcom logo** — the patch almost certainly
went onto a headered ROM without the header being removed, so every change
landed 512 bytes early. Redo it with Method 1.

**It boots but something is odd around saves** — the patch turns on
battery-backed SRAM in the cartridge header, which the original game did not
have, because that is where save states are kept. We have not tested how any
particular flash cart or emulator reacts to that, so if saves misbehave, try
deleting any `.srm` file sitting next to the ROM and loading it again. Reports
of what works and what does not are welcome.

## What you get

`README.md` in this folder lists the controls and what each practice feature
does.
