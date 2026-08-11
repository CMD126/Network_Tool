# Network Tool Pro — install / test / lint
#
# Usage:
#   make install     # installs to $(PREFIX) (default /usr/local), needs sudo on most systems
#   make install PREFIX=$HOME/.local   # per-user install, no sudo
#   make uninstall
#   make test         # runs the bats test suite (falls back to the plain-shell runner)
#   make lint         # shellcheck, if installed
#   make clean

PREFIX  ?= /usr/local
BINDIR  := $(DESTDIR)$(PREFIX)/bin
LIBDIR  := $(DESTDIR)$(PREFIX)/lib/networktool
CFGDIR  := $(HOME)/.config/networktool

SHELL_FILES := networktool.sh lib/*.sh

.PHONY: install uninstall test lint clean

install:
	install -d "$(LIBDIR)/lib"
	install -m 0755 networktool.sh "$(LIBDIR)/networktool.sh"
	install -m 0644 lib/*.sh "$(LIBDIR)/lib/"
	install -d "$(BINDIR)"
	printf '#!/usr/bin/env bash\nexec "%s/networktool.sh" "$$@"\n' "$(LIBDIR)" > "$(BINDIR)/networktool"
	chmod 0755 "$(BINDIR)/networktool"
	install -d "$(CFGDIR)"
	[ -f "$(CFGDIR)/config.ini" ] || install -m 0644 config/config.ini.example "$(CFGDIR)/config.ini"
	@echo "Installed. Run: networktool --help"

uninstall:
	rm -f "$(BINDIR)/networktool"
	rm -rf "$(LIBDIR)"
	@echo "Uninstalled. Config left in place at $(CFGDIR) (remove manually if desired)."

test:
	@if command -v bats >/dev/null 2>&1; then \
		bats tests/; \
	else \
		echo "bats-core not found; running the plain-shell fallback runner instead."; \
		bash tests/run_tests.sh; \
	fi

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck $(SHELL_FILES); \
	else \
		echo "shellcheck not installed — skipping (install: https://www.shellcheck.net)"; \
	fi

clean:
	rm -f last_result.txt networktool.log
