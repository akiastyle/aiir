#include "aiir_state.h"

#include <stdio.h>
#include <string.h>
#include <time.h>

bool aiir_state_init(AiirState *s, const char *wal_path, const char *snapshot_path, const char *meta_json) {
  memset(s, 0, sizeof(*s));
  snprintf(s->wal_path, sizeof(s->wal_path), "%s", wal_path && *wal_path ? wal_path : "/var/www/aiir/ai/state/ai.wal");
  snprintf(s->snapshot_path, sizeof(s->snapshot_path), "%s", snapshot_path && *snapshot_path ? snapshot_path : "/var/www/aiir/ai/state/snapshot.json");

  FILE *sf = fopen(s->snapshot_path, "w");
  if (!sf) return false;
  time_t t = time(NULL);
  fprintf(sf, "{\"ts\":%lld,\"meta\":%s}\n", (long long)t, meta_json ? meta_json : "{}");
  fclose(sf);
  return true;
}

void aiir_state_log_dbexec(const AiirState *s, uint32_t op_id, uint32_t proc_id, size_t argc) {
  FILE *wf = fopen(s->wal_path, "a");
  if (!wf) return;
  time_t t = time(NULL);
  fprintf(wf, "{\"ts\":%lld,\"opId\":%u,\"procId\":%u,\"argc\":%zu}\n", (long long)t, op_id, proc_id, argc);
  fclose(wf);
}
