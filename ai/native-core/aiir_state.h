#ifndef AIIR_STATE_H
#define AIIR_STATE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
  char wal_path[1024];
  char snapshot_path[1024];
} AiirState;

bool aiir_state_init(AiirState *s, const char *wal_path, const char *snapshot_path, const char *meta_json);
void aiir_state_log_dbexec(const AiirState *s, uint32_t op_id, uint32_t proc_id, size_t argc);

#endif
