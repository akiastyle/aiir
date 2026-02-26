#include "aiir_policy.h"

#include <stdlib.h>
#include <string.h>
#include <strings.h>

static bool parse_bool_env(const char *s, bool defv) {
  if (!s || !*s) return defv;
  if (strcmp(s, "1") == 0 || strcasecmp(s, "true") == 0 || strcasecmp(s, "yes") == 0) return true;
  if (strcmp(s, "0") == 0 || strcasecmp(s, "false") == 0 || strcasecmp(s, "no") == 0) return false;
  return defv;
}

bool aiir_policy_init_from_env(AiirPolicy *p) {
  memset(p, 0, sizeof(*p));
  p->allow_db_exec = parse_bool_env(getenv("AI_POLICY_ALLOW_DB_EXEC"), false);

  const char *ops = getenv("AI_POLICY_ALLOW_OPS");
  if (!ops || !*ops) {
    p->allow_all_ops = false;
    return true;
  }
  if (strcmp(ops, "*") == 0) {
    p->allow_all_ops = true;
    return true;
  }

  size_t cap = 16;
  p->allow_ops = (uint32_t *)malloc(cap * sizeof(uint32_t));
  if (!p->allow_ops) return false;

  const char *s = ops;
  while (*s) {
    while (*s == ' ' || *s == ',') s++;
    if (!*s) break;
    char *end = NULL;
    unsigned long v = strtoul(s, &end, 10);
    if (end == s) {
      while (*s && *s != ',') s++;
      continue;
    }
    if (p->allow_ops_n == cap) {
      cap *= 2;
      uint32_t *nw = (uint32_t *)realloc(p->allow_ops, cap * sizeof(uint32_t));
      if (!nw) return false;
      p->allow_ops = nw;
    }
    p->allow_ops[p->allow_ops_n++] = (uint32_t)v;
    s = end;
    while (*s && *s != ',') s++;
  }

  if (p->allow_ops_n == 0) p->allow_all_ops = false;
  return true;
}

bool aiir_policy_allow_op(const AiirPolicy *p, uint32_t op_id) {
  if (p->allow_all_ops) return true;
  for (size_t i = 0; i < p->allow_ops_n; i++) if (p->allow_ops[i] == op_id) return true;
  return false;
}

void aiir_policy_free(AiirPolicy *p) {
  free(p->allow_ops);
  p->allow_ops = NULL;
  p->allow_ops_n = 0;
}
