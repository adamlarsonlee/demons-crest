#!/usr/bin/env python3
"""Turn a Demon's Blazon password into a headless.py --press schedule.

The password screen is a 4x4 grid of 16 characters, each defaulting to 'B'.
The d-pad moves the cursor; B cycles the character through a 21-entry cycle
(the alphabet minus vowels) in the order below, wrapping.
"""

import argparse

CYCLE = "BZYXWVTSRQPNMLKJHGFDC"
ALPHABET = "".join(sorted(CYCLE))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("password")
    ap.add_argument("--spacing", type=int, default=6,
                    help="frames between presses; too low and inputs are dropped")
    ap.add_argument("--start", type=int, default=10, help="first input frame")
    args = ap.parse_args()

    pw = args.password.upper().replace(" ", "")
    if len(pw) != 16:
        raise SystemExit(f"password must be 16 characters, got {len(pw)}")
    bad = sorted(set(pw) - set(CYCLE))
    if bad:
        raise SystemExit(
            f"not in the password alphabet: {' '.join(bad)}\n"
            f"valid characters are the consonants {ALPHABET} (no vowels)")

    presses, frame = [], args.start

    def tap(button, times=1):
        nonlocal frame
        for _ in range(times):
            presses.append(f"{frame}:{button}")
            presses.append(f"{frame + 1}:{button}")
            frame += args.spacing

    for row in range(4):
        for col in range(4):
            tap("b", CYCLE.index(pw[row * 4 + col]))
            if col < 3:
                tap("right")
        if row < 3:
            tap("down")
            tap("left", 3)

    print(",".join(presses))
    print(f"# {len(presses)//2} presses, last input frame {frame - args.spacing}",
          flush=True)


if __name__ == "__main__":
    main()
