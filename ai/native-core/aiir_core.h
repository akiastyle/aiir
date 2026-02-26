#ifndef AIIR_CORE_H
#define AIIR_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define AIIR_A2A_MAGIC 0x41324131u
#define AIIR_A2A_VERSION 2u
#define AIIR_D2B_MAGIC 0x44324231u
#define AIIR_D2B_VERSION 1u

typedef struct {
  uint32_t *words;
  size_t len;
} AiirU32Buf;

void aiir_u32_free(AiirU32Buf *b);
bool aiir_read_file(const char *path, uint8_t **out, size_t *out_len);
bool aiir_load_u32(const char *path, AiirU32Buf *out);
bool aiir_load_u32_pref(const char *dir, const char *stem, AiirU32Buf *out);
bool aiir_write_u32(const char *path, const uint32_t *words, size_t len);
uint32_t aiir_fnv1a32(const uint8_t *buf, size_t n);

#endif
