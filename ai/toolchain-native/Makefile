CC ?= gcc
CFLAGS ?= -O2 -std=c11 -Wall -Wextra -Werror
LDFLAGS ?=

BIN = aiird
SRC = aiir_toolchain.c ../runtime-server-native/ai_runtime_native.c ../native-core/aiir_core.c ../native-core/aiir_policy.c ../native-core/aiir_state.c ../native-core/aiir_drift.c

all: $(BIN)

$(BIN): $(SRC)
	$(CC) $(CFLAGS) -o $@ $(SRC) $(LDFLAGS)
	ln -sf $(BIN) aiir-toolchain

clean:
	rm -f $(BIN) aiir-toolchain
