#include "aiir_drift.h"
#include "aiir_core.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint32_t hash_file(const char *path) {
  uint8_t *buf = NULL;
  size_t n = 0;
  if (!aiir_read_file(path, &buf, &n)) return 0u;
  uint32_t h = aiir_fnv1a32(buf, n);
  free(buf);
  return h;
}

static uint32_t hash_core_set(const char *core_dir) {
  const char *names[] = {
    "m2m.ai2ai.lite.table.aiir",
    "m2m.ai2ai.lite.blob.aiir",
    "m2m.ai2ai.source.adapt.table.aiir",
    "m2m.ai2ai.source.adapt.blob.aiir",
    "m2m.db.packet.aiir",
  };
  uint32_t h = 0x811c9dc5u;
  for (size_t i = 0; i < sizeof(names)/sizeof(names[0]); i++) {
    char p[1200];
    snprintf(p, sizeof(p), "%s/%s", core_dir, names[i]);
    uint32_t fh = hash_file(p);
    h ^= fh;
    h *= 0x01000193u;
  }
  return h;
}

bool aiir_drift_init(AiirDrift *d, const char *core_dir, uint32_t check_every) {
  memset(d, 0, sizeof(*d));
  snprintf(d->core_dir, sizeof(d->core_dir), "%s", core_dir);
  d->check_every = check_every ? check_every : 200u;
  d->base_hash = hash_core_set(core_dir);
  return d->base_hash != 0u;
}

void aiir_drift_tick(AiirDrift *d) {
  d->checks++;
  if (d->checks % d->check_every != 0u) return;
  uint32_t now = hash_core_set(d->core_dir);
  if (now != 0u && now != d->base_hash) {
    d->drift_count++;
    d->base_hash = now;
  }
}
