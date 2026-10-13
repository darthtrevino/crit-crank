.PHONY: build run clean

SDK = ${PLAYDATE_SDK_PATH}
ifeq ($(SDK),)
	SDK = $(shell egrep '^\s*SDKRoot' ~/.Playdate/config | head -n 1 | cut -c9-)
endif

GAME = critcrank

build:
	"$(SDK)/bin/pdc" source $(GAME).pdx

run: build
	open -a "$(SDK)/bin/Playdate Simulator.app" $(GAME).pdx

clean:
	rm -rf $(GAME).pdx charsheet.pdx
