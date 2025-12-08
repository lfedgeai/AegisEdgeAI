CC=gcc
CFLAGS=-Wall -Werror -I/usr/include/ -Wno-deprecated-declarations
LDFLAGS=-ltss2-esys -ltss2-mu -ltss2-tctildr -lssl -lcrypto

# Detect architecture
ARCH := $(shell uname -m)

# Set architecture-specific flags if needed
ifeq ($(ARCH),aarch64)
    # ARM64 specific flags (if any)
    CFLAGS += -march=armv8-a
endif

ifeq ($(ARCH),x86_64)
    # x86-64 specific flags (if any)
    CFLAGS += -march=x86-64
endif

# Build targets
TARGETS = tpm-app-persist tpm-app-evict tpm-app-sign tpm-app-selftest

all: $(TARGETS)
	@echo "Successfully built all targets for architecture: $(ARCH)"

tpm-app-persist: tpm-app-persist.c
	@echo "Building tpm-app-persist for architecture: $(ARCH)"
	$(CC) $(CFLAGS) $< -o $@ $(LDFLAGS)

tpm-app-evict: tpm-app-evict.c
	@echo "Building tpm-app-evict for architecture: $(ARCH)"
	$(CC) $(CFLAGS) $< -o $@ $(LDFLAGS)

tpm-app-sign: tpm-app-sign.c
	@echo "Building tpm-app-sign for architecture: $(ARCH)"
	$(CC) $(CFLAGS) $< -o $@ $(LDFLAGS)

tpm-app-selftest: tpm-app-selftest.c
	@echo "Building tpm-app-selftest for architecture: $(ARCH)"
	$(CC) $(CFLAGS) $< -o $@ $(LDFLAGS)

clean:
	rm -f $(TARGETS)

.PHONY: all clean
