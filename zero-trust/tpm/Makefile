# Detect architecture and set appropriate compiler
ARCH := $(shell uname -m)
OS := $(shell uname -s)

# Architecture-specific compiler settings
ifeq ($(ARCH),aarch64)
	# ARM64 Linux
	CC=gcc
	ARCH_CFLAGS=-march=armv8-a
else ifeq ($(ARCH),arm64)
	# ARM64 (alternative naming)
	CC=gcc
	ARCH_CFLAGS=-march=armv8-a
else
	# Default (x86_64)
	CC=gcc
	ARCH_CFLAGS=
endif

# OS-specific library paths
ifeq ($(OS),Darwin)
	# macOS
	PREFIX=/opt/homebrew
	INCLUDE_PATH=-I$(PREFIX)/include -I/usr/include/
	LIBRARY_PATH=-L$(PREFIX)/lib
	DYLD_FLAGS=-Wl,-rpath,$(PREFIX)/lib
else
	# Linux
	PREFIX=/usr/local
	INCLUDE_PATH=-I$(PREFIX)/include -I/usr/include/
	LIBRARY_PATH=-L$(PREFIX)/lib -L/usr/lib
	DYLD_FLAGS=
endif

CFLAGS=-Wall -Werror $(INCLUDE_PATH) -Wno-deprecated-declarations $(ARCH_CFLAGS)
LDFLAGS=$(LIBRARY_PATH) -ltss2-esys -ltss2-mu -ltss2-tctildr -lssl -lcrypto $(DYLD_FLAGS)
SOURCES=tpm-app-persist.c
EXECUTABLE=tpm-app-persist

.PHONY: all clean info

all: info $(EXECUTABLE)

info:
	@echo "Building for architecture: $(ARCH) on $(OS)"
	@echo "Using compiler: $(CC)"
	@echo "Architecture flags: $(ARCH_CFLAGS)"
	@echo "Include paths: $(INCLUDE_PATH)"
	@echo "Library paths: $(LIBRARY_PATH)"

$(EXECUTABLE): $(SOURCES)
	$(CC) $(CFLAGS) $(SOURCES) -o $(EXECUTABLE) $(LDFLAGS)

clean:
	rm -f $(EXECUTABLE)
