#ifndef AIIR_POLICY_H
#define AIIR_POLICY_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
  bool allow_db_exec;
  bool allow_all_ops;
  uint32_t *allow_ops;
  size_t allow_ops_n;
} AiirPolicy;

bool aiir_policy_init_from_env(AiirPolicy *p);
bool aiir_policy_allow_op(const AiirPolicy *p, uint32_t op_id);
void aiir_policy_free(AiirPolicy *p);

#endif
