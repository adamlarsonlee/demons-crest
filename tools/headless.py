#!/usr/bin/env python3
"""Run a ROM in a headless libretro core and dump frames as PNG.

Exists so ROM changes can be verified visually without a GUI emulator.
"""

import argparse
import ctypes
import struct
import zlib
from pathlib import Path

PIXEL_0RGB1555, PIXEL_XRGB8888, PIXEL_RGB565 = 0, 1, 2

ENV_GET_OVERSCAN = 2
ENV_GET_CAN_DUPE = 3
ENV_SET_PIXEL_FORMAT = 10
ENV_SET_INPUT_DESCRIPTORS = 11
ENV_GET_VARIABLE = 15
ENV_SET_VARIABLES = 16
ENV_GET_VARIABLE_UPDATE = 17
ENV_GET_SYSTEM_DIRECTORY = 9
ENV_GET_SAVE_DIRECTORY = 31

MEM_SAVE_RAM, MEM_RTC, MEM_SYSTEM_RAM, MEM_VIDEO_RAM = 0, 1, 2, 3

BUTTONS = {"b": 0, "y": 1, "select": 2, "start": 3, "up": 4, "down": 5,
           "left": 6, "right": 7, "a": 8, "x": 9, "l": 10, "r": 11}


class GameInfo(ctypes.Structure):
    _fields_ = [("path", ctypes.c_char_p), ("data", ctypes.c_void_p),
                ("size", ctypes.c_size_t), ("meta", ctypes.c_char_p)]


class Geometry(ctypes.Structure):
    _fields_ = [("base_width", ctypes.c_uint), ("base_height", ctypes.c_uint),
                ("max_width", ctypes.c_uint), ("max_height", ctypes.c_uint),
                ("aspect_ratio", ctypes.c_float)]


class Timing(ctypes.Structure):
    _fields_ = [("fps", ctypes.c_double), ("sample_rate", ctypes.c_double)]


class AVInfo(ctypes.Structure):
    _fields_ = [("geometry", Geometry), ("timing", Timing)]


def write_png(path, width, height, rows):
    raw = b"".join(b"\x00" + r for r in rows)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    Path(path).write_bytes(png)


def to_rgb_rows(buf, width, height, pitch, fmt):
    rows = []
    for y in range(height):
        line = buf[y * pitch:y * pitch + pitch]
        out = bytearray()
        if fmt == PIXEL_XRGB8888:
            for x in range(width):
                b, g, r = line[x * 4], line[x * 4 + 1], line[x * 4 + 2]
                out += bytes((r, g, b))
        else:
            for x in range(width):
                p = line[x * 2] | (line[x * 2 + 1] << 8)
                if fmt == PIXEL_RGB565:
                    r, g, b = (p >> 11) & 0x1F, (p >> 5) & 0x3F, p & 0x1F
                    out += bytes((r * 255 // 31, g * 255 // 63, b * 255 // 31))
                else:
                    r, g, b = (p >> 10) & 0x1F, (p >> 5) & 0x1F, p & 0x1F
                    out += bytes((r * 255 // 31, g * 255 // 31, b * 255 // 31))
        rows.append(bytes(out))
    return rows


class Core:
    def __init__(self, core_path, system_dir="/tmp"):
        self.lib = ctypes.CDLL(core_path)
        self.pixel_fmt = PIXEL_0RGB1555
        self.frame = None
        self.pressed = set()
        self._sysdir = ctypes.c_char_p(system_dir.encode())
        self._keep = []
        self._bind()

    def _bind(self):
        L = self.lib
        ENV = ctypes.CFUNCTYPE(ctypes.c_bool, ctypes.c_uint, ctypes.c_void_p)
        VIDEO = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_uint,
                                 ctypes.c_uint, ctypes.c_size_t)
        AUDIO = ctypes.CFUNCTYPE(None, ctypes.c_int16, ctypes.c_int16)
        AUDIOB = ctypes.CFUNCTYPE(ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t)
        POLL = ctypes.CFUNCTYPE(None)
        STATE = ctypes.CFUNCTYPE(ctypes.c_int16, ctypes.c_uint, ctypes.c_uint,
                                 ctypes.c_uint, ctypes.c_uint)

        def env(cmd, data):
            if cmd == ENV_SET_PIXEL_FORMAT:
                self.pixel_fmt = ctypes.cast(data, ctypes.POINTER(ctypes.c_int))[0]
                return True
            if cmd == ENV_GET_CAN_DUPE:
                ctypes.cast(data, ctypes.POINTER(ctypes.c_bool))[0] = True
                return True
            if cmd in (ENV_GET_SYSTEM_DIRECTORY, ENV_GET_SAVE_DIRECTORY):
                ctypes.cast(data, ctypes.POINTER(ctypes.c_char_p))[0] = self._sysdir
                return True
            if cmd in (ENV_SET_INPUT_DESCRIPTORS, ENV_SET_VARIABLES):
                return True
            if cmd == ENV_GET_OVERSCAN:
                ctypes.cast(data, ctypes.POINTER(ctypes.c_bool))[0] = False
                return True
            return False

        def video(data, width, height, pitch):
            if data:
                self.frame = (ctypes.string_at(data, pitch * height),
                              width, height, pitch)

        def state(port, device, index, btn):
            return 1 if (port == 0 and btn in self.pressed) else 0

        cbs = [ENV(env), VIDEO(video), AUDIO(lambda l, r: None),
               AUDIOB(lambda d, f: f), POLL(lambda: None), STATE(state)]
        self._keep = cbs
        L.retro_set_environment(cbs[0])
        L.retro_set_video_refresh(cbs[1])
        L.retro_set_audio_sample(cbs[2])
        L.retro_set_audio_sample_batch(cbs[3])
        L.retro_set_input_poll(cbs[4])
        L.retro_set_input_state(cbs[5])
        L.retro_init()

    def load(self, rom_path):
        data = Path(rom_path).read_bytes()
        self._rom = ctypes.create_string_buffer(data, len(data))
        info = GameInfo(path=str(rom_path).encode(),
                        data=ctypes.cast(self._rom, ctypes.c_void_p),
                        size=len(data), meta=None)
        self.lib.retro_load_game.restype = ctypes.c_bool
        if not self.lib.retro_load_game(ctypes.byref(info)):
            raise RuntimeError("core refused to load the ROM")
        av = AVInfo()
        self.lib.retro_get_system_av_info(ctypes.byref(av))
        return av

    def run(self):
        self.lib.retro_run()

    def serialize(self):
        self.lib.retro_serialize_size.restype = ctypes.c_size_t
        self.lib.retro_serialize.restype = ctypes.c_bool
        n = self.lib.retro_serialize_size()
        if not n:
            raise RuntimeError("core reports a zero-size save state")
        buf = ctypes.create_string_buffer(n)
        if not self.lib.retro_serialize(buf, n):
            raise RuntimeError("retro_serialize failed")
        return buf.raw

    def unserialize(self, data):
        self.lib.retro_unserialize.restype = ctypes.c_bool
        buf = ctypes.create_string_buffer(data, len(data))
        if not self.lib.retro_unserialize(buf, len(data)):
            raise RuntimeError("retro_unserialize failed")

    def memory(self, kind):
        ptr, size = self._mem_ptr(kind)
        if not ptr:
            return None
        return ctypes.string_at(ptr, size)

    def _mem_ptr(self, kind):
        self.lib.retro_get_memory_data.restype = ctypes.c_void_p
        self.lib.retro_get_memory_size.restype = ctypes.c_size_t
        return self.lib.retro_get_memory_data(kind), self.lib.retro_get_memory_size(kind)

    def poke(self, kind, offset, value):
        """Write one byte into core memory, for probing candidate addresses."""
        ptr, size = self._mem_ptr(kind)
        if not ptr:
            raise RuntimeError("core exposes no such memory region")
        if not 0 <= offset < size:
            raise RuntimeError(f"offset 0x{offset:X} outside 0..0x{size-1:X}")
        ctypes.memmove(ctypes.c_void_p(ptr + offset), bytes((value & 0xFF,)), 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rom")
    ap.add_argument("--core", default="/usr/local/lib/snes9x_libretro.so")
    ap.add_argument("--frames", type=int, default=600)
    ap.add_argument("--dump", default="", help="comma-separated frame numbers")
    ap.add_argument("--press", default="", help="frame:button[,frame:button...]")
    ap.add_argument("--outdir", default="build/frames")
    ap.add_argument("--prefix", default="frame")
    ap.add_argument("--dump-wram", default="", help="comma-separated frame numbers")
    ap.add_argument("--dump-vram", default="", help="comma-separated frame numbers")
    ap.add_argument("--load-state", help="restore this state before running; "
                                         "frame numbers then count from the restore")
    ap.add_argument("--save-state", default="", help="frame:path")
    ap.add_argument("--poke", default="",
                    help="frame:addr=value[,...]; addr is a WRAM offset or $7Exxxx/$7Fxxxx")
    args = ap.parse_args()

    wanted = {int(x) for x in args.dump.split(",") if x.strip()}
    want_wram = {int(x) for x in args.dump_wram.split(",") if x.strip()}
    want_vram = {int(x) for x in args.dump_vram.split(",") if x.strip()}
    schedule = {}
    for item in filter(None, args.press.split(",")):
        f, btn = item.split(":")
        schedule.setdefault(int(f), []).append(BUTTONS[btn.strip().lower()])

    def parse_addr(text):
        text = text.strip()
        if text.startswith("$"):
            v = int(text[1:], 16)
            if 0x7E0000 <= v <= 0x7FFFFF:
                return v - 0x7E0000
            raise SystemExit(f"bank address {text} is outside WRAM $7E0000-$7FFFFF")
        return int(text, 0)

    pokes = {}
    for item in filter(None, args.poke.split(",")):
        f, assign = item.split(":", 1)
        addr, value = assign.split("=", 1)
        pokes.setdefault(int(f), []).append((parse_addr(addr), int(value, 0)))

    saves = {}
    for item in filter(None, args.save_state.split(",")):
        f, path = item.split(":", 1)
        saves[int(f)] = path

    core = Core(args.core)
    av = core.load(args.rom)
    print(f"loaded  {args.rom}")
    print(f"geometry {av.geometry.base_width}x{av.geometry.base_height}  "
          f"fps {av.timing.fps:.2f}  pixel_fmt {core.pixel_fmt}")

    if args.load_state:
        core.unserialize(Path(args.load_state).read_bytes())
        print(f"restored {args.load_state}")

    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    for f in range(1, args.frames + 1):
        core.pressed = set(schedule.get(f, []))
        core.run()
        for addr, value in pokes.get(f, ()):
            core.poke(MEM_SYSTEM_RAM, addr, value)
            print(f"  frame {f}: poked WRAM 0x{addr:05X} = 0x{value:02X}")
        if f in wanted:
            if not core.frame:
                print(f"  frame {f}: no video yet")
                continue
            buf, w, h, pitch = core.frame
            rows = to_rgb_rows(buf, w, h, pitch, core.pixel_fmt)
            path = outdir / f"{args.prefix}-{f:05d}.png"
            write_png(path, w, h, rows)
            print(f"  wrote {path}  ({w}x{h})")
        if f in want_wram:
            d = core.memory(MEM_SYSTEM_RAM)
            if d:
                out = outdir / f"{args.prefix}-{f:05d}.wram"
                out.write_bytes(d)
                print(f"  wrote {out}  ({len(d):,} bytes)")
            else:
                print(f"  frame {f}: core exposes no system RAM")
        if f in want_vram:
            d = core.memory(MEM_VIDEO_RAM)
            if d:
                out = outdir / f"{args.prefix}-{f:05d}.vram"
                out.write_bytes(d)
                print(f"  wrote {out}  ({len(d):,} bytes)")
            else:
                print(f"  frame {f}: core exposes no video RAM")
        if f in saves:
            path = Path(saves[f])
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(core.serialize())
            print(f"  saved {path}  ({path.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
