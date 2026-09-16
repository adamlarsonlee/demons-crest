# Passwords

Demon's Crest saves via passwords rather than SRAM, so a password encodes the
whole progress state. These load correctly on the Japanese ROM, confirming that
passwords are not region-specific.

A valid password is 16 characters drawn from `BCDFGHJKLMNPQRSTVWXYZ` — the
alphabet minus the vowels `A E I O U`. See `docs/recon.md` for the entry screen
mechanics and `tools/mkpassword.py` for entering one headlessly.

|Password|Effect|Verified|
|--------|------|--------|
|`QFFF KNRR DDLR XGTQ`|All items|accepted, loads overworld|
|`KDGY KRMV DDXR XWKQ`|All crests, fire powers, potions, talismans|accepted, loads overworld|
|`RBNL XHGB VGBB LYLD`|Boss rush: only bosses appear|accepted|
|`BDLK BXPB GHGG FQKL`|Level 2|accepted, loads overworld|
|`TRTL STGZ FQMF XFLF`|Level 3|accepted, loads overworld|
|`YZHF MMXK VJDR GMWQ`|Level 5|accepted, loads overworld|

One widely reposted "level 4" code, `DKHH UMBH CSWN KMMQ`, contains a `U`, which
is not in the password alphabet. It is almost certainly a U/V transcription error
and was rejected before being tried.

## Usage

```sh
PRESS=$(python3 tools/mkpassword.py QFFFKNRRDDLRXGTQ --submit | head -1)
python3 tools/headless.py rom/DemonsBlazon.sfc \
    --load-state states/password.state --frames 1700 --press "$PRESS" \
    --dump-wram 1690 --save-state 1690:states/allitems.state
```

Sources: community cheat lists for Demon's Crest (SNES); cross-checked against a
Japanese Demon's Blazon trick page which lists the same codes.
