#ifndef AIIR_DRIFT_H
#define AIIR_DRIFT_H

#include <stdbool.h>
#include <stdint.h>

typedef struct {
  char core_dir[1024];
  uint32_t base_hash;
  uint32_t checks;
  uint32_t drift_count;
  uint32_t check_every;
} AiirDrift;

bool aiir_drift_init(AiirDrift *d, const char *core_dir, uint32_t check_every);
void aiir_drift_tick(AiirDrift *d);

#endif
