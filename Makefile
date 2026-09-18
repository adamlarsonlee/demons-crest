ROM   ?= rom/DemonsBlazon.sfc
BUILD := build
OUT   := $(BUILD)/DemonsBlazon_Practice.sfc
CONFIG := $(BUILD)/rom_config.inc
LOCK  := rom.lock
ASM   := src/asm/patch.asm

.PHONY: all verify rom patch dist clean distclean docker-image docker-rom docker-shell docker-shot docker-dist

all: rom

## Identify the source ROM, pin its hash, and emit the asar mapping include.
verify: $(CONFIG)

$(ROM):
	@echo "error: no ROM found at '$(ROM)'" >&2
	@echo "" >&2
	@echo "Supply your own dump of Demon's Blazon (Japan) at that path, or point" >&2
	@echo "the build at it directly:  make ROM=/path/to/rom.sfc" >&2
	@echo "ROMs are gitignored and are never committed or distributed." >&2
	@exit 1

$(CONFIG): $(ROM) tools/romcheck.py
	@mkdir -p $(BUILD)
	python3 tools/romcheck.py "$(ROM)" --emit-config $(CONFIG) --lock $(LOCK)

## Build the practice ROM by patching a copy of the verified source ROM.
rom: $(OUT)

$(OUT): $(ASM) $(CONFIG) $(wildcard src/asm/*.asm)
	@mkdir -p $(BUILD)
	cp "$(ROM)" $(OUT)
	asar --fix-checksum=on $(ASM) $(OUT)
	@echo "built $(OUT)"

## Emit a distributable IPS patch (the ROM itself is never shareable).
patch: $(BUILD)/DemonsBlazon_Practice.ips

$(BUILD)/DemonsBlazon_Practice.ips: $(OUT)
	python3 tools/mkips.py "$(ROM)" $(OUT) $@

## Assemble the folder handed to players: patch, applier, instructions, hashes.
dist: $(BUILD)/DemonsCrestPractice.zip

$(BUILD)/DemonsCrestPractice.zip: $(BUILD)/DemonsBlazon_Practice.ips tools/mkdist.py \
		tools/apply.py dist-template/PATCHING.md README.md VERSION
	python3 tools/mkdist.py --ips $(BUILD)/DemonsBlazon_Practice.ips --rom $(OUT) \
		--out $(BUILD)/dist --zip $@

clean:
	rm -rf $(BUILD)

distclean: clean
	rm -f $(LOCK)

# --- Containerized build -----------------------------------------------------
# Keeps the host free of a toolchain install. Output is byte-identical to a
# host build. ROM is mounted read-only and never enters the image.

IMAGE    := demons-crest-build
ROM_ABS  := $(abspath $(firstword $(wildcard $(ROM)) $(ROM)))
DOCKER_RUN = docker run --rm -v "$(CURDIR)":/work \
	-v "$(ROM_ABS)":/work/rom/$(notdir $(ROM)):ro $(IMAGE)

docker-image:
	docker build -t $(IMAGE) -f docker/Dockerfile docker/

docker-rom:
	$(DOCKER_RUN) make rom

# Frame capture. Defaults to the Capcom logo screen, where the demo text lands.
FRAMES ?= 430
DUMP   ?= 420
SHOT   ?= $(OUT)

docker-dist:
	$(DOCKER_RUN) make dist

docker-shot:
	$(DOCKER_RUN) python3 tools/headless.py $(SHOT) --frames $(FRAMES) --dump $(DUMP)

docker-shell:
	docker run --rm -it -v "$(CURDIR)":/work \
		-v "$(ROM_ABS)":/work/rom/$(notdir $(ROM)):ro $(IMAGE) bash
