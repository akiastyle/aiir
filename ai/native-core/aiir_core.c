#include "aiir_core.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

void aiir_u32_free(AiirU32Buf *b) {
  if (!b || !b->words) return;
  free(b->words);
  b->words = NULL;
  b->len = 0;
}

bool aiir_read_file(const char *path, uint8_t **out, size_t *out_len) {
  FILE *f = fopen(path, "rb");
  if (!f) return false;
  if (fseek(f, 0, SEEK_END) != 0) {
    fclose(f);
    return false;
  }
  long sz = ftell(f);
  if (sz < 0) {
    fclose(f);
    return false;
  }
  if (fseek(f, 0, SEEK_SET) != 0) {
    fclose(f);
    return false;
  }
  uint8_t *buf = (uint8_t *)malloc((size_t)sz);
  if (!buf && sz > 0) {
    fclose(f);
    return false;
  }
  if (sz > 0 && fread(buf, 1, (size_t)sz, f) != (size_t)sz) {
    free(buf);
    fclose(f);
    return false;
  }
  fclose(f);
  *out = buf;
  *out_len = (size_t)sz;
  return true;
}

bool aiir_load_u32(const char *path, AiirU32Buf *out) {
  uint8_t *raw = NULL;
  size_t raw_len = 0;
  if (!aiir_read_file(path, &raw, &raw_len)) return false;
  if ((raw_len % 4u) != 0u) {
    free(raw);
    return false;
  }
  size_t n = raw_len / 4u;
  uint32_t *w = (uint32_t *)malloc(n * sizeof(uint32_t));
  if (!w) {
    free(raw);
    return false;
  }
  for (size_t i = 0; i < n; i++) {
    w[i] = (uint32_t)raw[i * 4u] |
           ((uint32_t)raw[i * 4u + 1u] << 8u) |
           ((uint32_t)raw[i * 4u + 2u] << 16u) |
           ((uint32_t)raw[i * 4u + 3u] << 24u);
  }
  free(raw);
  out->words = w;
  out->len = n;
  return true;
}

bool aiir_load_u32_pref(const char *dir, const char *stem, AiirU32Buf *out) {
  char p1[1024];
  char p2[1024];
  snprintf(p1, sizeof(p1), "%s/%s.aiir", dir, stem);
  snprintf(p2, sizeof(p2), "%s/%s.u32", dir, stem);
  if (aiir_load_u32(p1, out)) return true;
  return aiir_load_u32(p2, out);
}

bool aiir_write_u32(const char *path, const uint32_t *words, size_t len) {
  FILE *f = fopen(path, "wb");
  if (!f) return false;
  for (size_t i = 0; i < len; i++) {
    uint8_t b[4];
    b[0] = (uint8_t)(words[i] & 0xffu);
    b[1] = (uint8_t)((words[i] >> 8u) & 0xffu);
    b[2] = (uint8_t)((words[i] >> 16u) & 0xffu);
    b[3] = (uint8_t)((words[i] >> 24u) & 0xffu);
    if (fwrite(b, 1, 4, f) != 4) {
      fclose(f);
      return false;
    }
  }
  fclose(f);
  return true;
}

uint32_t aiir_fnv1a32(const uint8_t *buf, size_t n) {
  uint32_t h = 0x811c9dc5u;
  for (size_t i = 0; i < n; i++) {
    h ^= (uint32_t)buf[i];
    h *= 0x01000193u;
  }
  return h;
}
