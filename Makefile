# billee-hardware-2027 — workspace bootstrap & science-module installers
#
#   make            # same as `make help`
#   make setup      # get on lucadev + init/update every submodule (was ./setup.sh)
#   make rover      # setup, then fast-forward this repo to the latest lucadev
#   make science host    # install the spectrometer VNC viewer on your laptop
#   make science rover   # install the spectrometer stack on the Jetson
#   make science run     # start the remote VNC kiosk on the Jetson
#   make astronaut jetson   # install the astronaut video/audio streamer on the Jetson
#   make astronaut pi       # install it on the Pi
#   make astronaut          # list all its commands (probe, status, logs, e2e, ...)

BRANCH      ?= lucadev
SCIENCE_DIR := RunScienceSpectrometer
ASTRO_DIR   := astronaut-streamer

.DEFAULT_GOAL := help
.PHONY: help banner setup rover science astronaut

# setup — the bootstrap every action target runs first (formerly ./setup.sh):
# get on the working branch and initialise/update every submodule recursively.
setup: ## Check out lucadev and init/update every submodule recursively
	git checkout $(BRANCH)
	git submodule update --init --recursive
	@echo "All repositories pulled and up to date"
	@$(MAKE) --no-print-directory banner

# `make science <host|rover|run>` / `make astronaut <target>` — treat the words
# after the module name as its arguments, not targets of their own: rewrite
# them into no-op targets, and (below) skip defining the real `rover` and
# `help` recipes so `science rover` doesn't also trigger a repo sync and
# `astronaut help` shows the streamer's help. A bare `make rover` or
# `make help` still lands in the `else` branch and gets the real recipe.
MODULE_ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
ifneq ($(filter science astronaut,$(firstword $(MAKECMDGOALS))),)
ifneq ($(MODULE_ARGS),)
$(eval $(MODULE_ARGS):;@:)
endif
else

rover: setup ## Run setup, then fast-forward this repo to the latest lucadev
	git pull --ff-only
	git submodule update --init --recursive
	@echo "rover: repo + submodules now at the latest $(BRANCH)."

help: ## Show this list of targets
	@$(MAKE) --no-print-directory banner
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "} {printf "  \033[36m%-9s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "  science host    Install the spectrometer VNC viewer (your laptop)"
	@echo "  science rover   Install the spectrometer stack on the Jetson"
	@echo "  science run     Start the remote VNC kiosk on the Jetson"
	@echo
	@echo "  astronaut jetson   Install the astronaut video/audio streamer on the Jetson"
	@echo "  astronaut pi       Install it on the Pi"
	@echo "  astronaut          List all its commands (probe, status, logs, test, e2e, ...)"

endif

science: setup ## Spectrometer module: 'make science host|rover' to install, 'make science run' to start the kiosk
	@case "$(MODULE_ARGS)" in \
	  host)  sudo bash $(SCIENCE_DIR)/host_install_me.sh ;; \
	  rover) sudo bash $(SCIENCE_DIR)/jetson_install_me.sh ;; \
	  run)   exec bash $(SCIENCE_DIR)/start-remote-kiosk.sh ;; \
	  "")    echo "usage: make science host | make science rover | make science run"; exit 2 ;; \
	  *)     echo "unknown science target '$(MODULE_ARGS)' — want: host | rover | run"; exit 2 ;; \
	esac

# The astronaut streamer is its own repo (a submodule) with its own Makefile:
# pass the command on. Only its submodule is fetched (no recursive setup),
# so this stays light on the Pi.
astronaut: ## Astronaut video/audio streamer: 'make astronaut' lists its commands
	@[ -e $(ASTRO_DIR)/.git ] || git submodule update --init $(ASTRO_DIR)
	@$(MAKE) --no-print-directory -C $(ASTRO_DIR) $(or $(MODULE_ARGS),help)

banner:
	@echo ""
	@echo "	   ██████╗ ██╗██╗     ██╗     ███████╗███████╗"
	@echo "	   ██╔══██╗██║██║     ██║     ██╔════╝██╔════╝"
	@echo "	   ██████╔╝██║██║     ██║     █████╗  █████╗"
	@echo "	   ██╔══██╗██║██║     ██║     ██╔══╝  ██╔══╝"
	@echo "	   ██████╔╝██║███████╗███████╗███████╗███████╗"
	@echo "	   ╚═════╝ ╚═╝╚══════╝╚══════╝╚══════╝╚══════╝"
	@echo ""
	@echo "          Rover Control Module  ·  Science Control Module"
	@echo "     Powered by ROS2 Humble and F\` Flight Software (NASA/JPL)"
	@echo ""
