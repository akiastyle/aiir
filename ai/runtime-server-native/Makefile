CC ?= gcc
CFLAGS ?= -O2 -std=c11 -Wall -Wextra -Werror -DAI_RUNTIME_STANDALONE=1
LDFLAGS ?=

BIN = ai-runtime-native
SRC = ai_runtime_native.c ../native-core/aiir_core.c ../native-core/aiir_policy.c ../native-core/aiir_state.c ../native-core/aiir_drift.c

all: $(BIN)

$(BIN): $(SRC)
	$(CC) $(CFLAGS) -o $@ $(SRC) $(LDFLAGS)

clean:
	rm -f $(BIN)
