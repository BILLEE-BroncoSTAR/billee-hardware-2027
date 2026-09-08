# billee-hardware-2027 — workspace bootstrap & science-module installers
#
#   make            # same as `make help`
#   make setup      # get on lucadev + init/update every submodule (was ./setup.sh)
#   make rover      # setup, then fast-forward this repo to the latest lucadev
#   make science host    # install the spectrometer VNC viewer on your laptop
#   make science rover   # install the spectrometer stack on the Jetson
#   make science run     # start the remote VNC kiosk on the Jetson

BRANCH      ?= lucadev
SCIENCE_DIR := RunScienceSpectrometer

.DEFAULT_GOAL := help
.PHONY: help banner setup rover science

# setup — the bootstrap every action target runs first (formerly ./setup.sh):
# get on the working branch and initialise/update every submodule recursively.
setup: ## Check out lucadev and init/update every submodule recursively
	git checkout $(BRANCH)
	git submodule update --init --recursive
	@echo "All repositories pulled and up to date"
	@$(MAKE) --no-print-directory banner

# `make science <host|rover>` — treat the word after `science` as an argument,
# not its own target: rewrite it into a no-op target, and (below) skip defining
# the real `rover` recipe so `science rover` doesn't also trigger a repo sync.
# A bare `make rover` still lands in the `else` branch and gets the real recipe.
ifeq (science,$(firstword $(MAKECMDGOALS)))
SCIENCE_ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
ifneq ($(SCIENCE_ARGS),)
$(eval $(SCIENCE_ARGS):;@:)
endif
else

rover: setup ## Run setup, then fast-forward this repo to the latest lucadev
	git pull --ff-only
	git submodule update --init --recursive
	@echo "rover: repo + submodules now at the latest $(BRANCH)."

endif

help: ## Show this list of targets
	@$(MAKE) --no-print-directory banner
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "} {printf "  \033[36m%-9s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "  science host    Install the spectrometer VNC viewer (your laptop)"
	@echo "  science rover   Install the spectrometer stack on the Jetson"
	@echo "  science run     Start the remote VNC kiosk on the Jetson"

science: setup ## Spectrometer module: 'make science host|rover' to install, 'make science run' to start the kiosk
	@case "$(SCIENCE_ARGS)" in \
	  host)  sudo bash $(SCIENCE_DIR)/host_install_me.sh ;; \
	  rover) sudo bash $(SCIENCE_DIR)/jetson_install_me.sh ;; \
	  run)   exec bash $(SCIENCE_DIR)/start-remote-kiosk.sh ;; \
	  "")    echo "usage: make science host | make science rover | make science run"; exit 2 ;; \
	  *)     echo "unknown science target '$(SCIENCE_ARGS)' — want: host | rover | run"; exit 2 ;; \
	esac

banner:
	@echo ""
	@echo "██████╗ ██╗██╗     ██╗     ███████╗███████╗    ██╗  ██╗██╗    ██╗"
	@echo "██╔══██╗██║██║     ██║     ██╔════╝██╔════╝    ██║  ██║██║    ██║"
	@echo "██████╔╝██║██║     ██║     █████╗  █████╗      ███████║██║ █╗ ██║"
	@echo "██╔══██╗██║██║     ██║     ██╔══╝  ██╔══╝      ██╔══██║██║███╗██║"
	@echo "██████╔╝██║███████╗███████╗███████╗███████╗    ██║  ██║╚███╔███╔╝"
	@echo "╚═════╝ ╚═╝╚══════╝╚══════╝╚══════╝╚══════╝    ╚═╝  ╚═╝ ╚══╝╚══╝ "
	@echo ""
	@echo "          Rover Control Module  ·  Science Control Module"
	@echo "     Powered by ROS2 Humble and F\` Flight Software (NASA/JPL)"
	@echo ""
