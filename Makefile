# billee-hardware-2027 — workspace bootstrap & science-module installers
#
#   make            # same as `make help`
#   make rover      # sync this repo (lucadev) + every submodule, recursively
#   make science host    # install the spectrometer VNC viewer on your laptop
#   make science rover   # install the spectrometer stack on the Jetson
#   make science run     # start the remote VNC kiosk in a detached screen session
#   make science attach  # re-attach to that screen session (Ctrl-A D to detach)
#   make science stop    # stop the kiosk and close the screen session

BRANCH      ?= lucadev
SCIENCE_DIR := RunScienceSpectrometer

.DEFAULT_GOAL := help
.PHONY: help banner rover science

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

rover: ## Check out lucadev, pull, then init/update every submodule recursively
	git checkout $(BRANCH)
	git pull --ff-only
	git submodule update --init --recursive
	@$(MAKE) --no-print-directory banner
	@echo "All repositories pulled and up to date."

endif

help: ## Show this list of targets
	@$(MAKE) --no-print-directory banner
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "} {printf "  \033[36m%-9s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "  science host    Install the spectrometer VNC viewer (your laptop)"
	@echo "  science rover   Install the spectrometer stack on the Jetson"
	@echo "  science run     Start the VNC kiosk in a detached screen session"
	@echo "  science attach  Re-attach to the kiosk screen session (Ctrl-A D to detach)"
	@echo "  science stop    Stop the kiosk and close its screen session"

KIOSK_SCREEN := billee-kiosk

science: ## Spectrometer module: host|rover install, run/attach/stop the kiosk (detached screen)
	@case "$(SCIENCE_ARGS)" in \
	  host)  sudo bash $(SCIENCE_DIR)/host_install_me.sh ;; \
	  rover) sudo bash $(SCIENCE_DIR)/jetson_install_me.sh ;; \
	  run) \
	    command -v screen >/dev/null 2>&1 || { echo "[INFO] installing screen..."; sudo apt-get install -y screen || exit 1; }; \
	    if screen -list 2>/dev/null | grep -q "[.]$(KIOSK_SCREEN)[[:space:]]"; then \
	      echo "[INFO] kiosk screen '$(KIOSK_SCREEN)' is already running — 'make science attach'."; exit 0; \
	    fi; \
	    pw="$$HOME/.vnc/spectral-analysis.passwd"; \
	    if [ ! -f "$$pw" ] && command -v x11vnc >/dev/null 2>&1; then \
	      echo "[INFO] no VNC password set — do it now (one-time, needs a prompt):"; \
	      mkdir -p "$$(dirname "$$pw")"; x11vnc -storepasswd "$$pw" || exit 1; \
	    fi; \
	    screen -dmS $(KIOSK_SCREEN) bash $(SCIENCE_DIR)/start-remote-kiosk.sh; \
	    echo "[INFO] kiosk started in detached screen '$(KIOSK_SCREEN)'."; \
	    echo "       attach: make science attach   |   stop: make science stop" ;; \
	  attach) exec screen -r $(KIOSK_SCREEN) ;; \
	  stop) \
	    screen -S $(KIOSK_SCREEN) -X stuff "$$(printf '\003')" 2>/dev/null || true; \
	    sleep 3; \
	    screen -S $(KIOSK_SCREEN) -X quit 2>/dev/null || true; \
	    echo "[INFO] stopped the kiosk and closed screen '$(KIOSK_SCREEN)'." ;; \
	  "")    echo "usage: make science host | rover | run | attach | stop"; exit 2 ;; \
	  *)     echo "unknown science target '$(SCIENCE_ARGS)' — want: host | rover | run | attach | stop"; exit 2 ;; \
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
