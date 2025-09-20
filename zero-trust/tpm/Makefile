CC=gcc
CFLAGS=-Wall -Werror -I/usr/include/ -Wno-deprecated-declarations
LDFLAGS=-ltss2-esys -ltss2-mu -ltss2-tctildr -lssl -lcrypto
SOURCES=tpm-app-persist.c
EXECUTABLE=tpm-app-persist

all: $(EXECUTABLE)

$(EXECUTABLE): $(SOURCES)
	$(CC) $(CFLAGS) $(SOURCES) -o $(EXECUTABLE) $(LDFLAGS)

clean:
	rm -f $(EXECUTABLE)
