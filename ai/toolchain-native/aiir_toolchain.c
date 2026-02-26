#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include "../runtime-server-native/ai_runtime_native.h"

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#define A2A_MAGIC 0x41324131u
#define A2A_VERSION 2u
#define D2B_MAGIC 0x44324231u
#define D2B_VERSION 1u

#define ARR_GROW_CAP(c) ((c) == 0 ? 16 : (c) * 2)

typedef struct { uint32_t *v; size_t n; size_t c; } U32Vec;
typedef struct { uint8_t *v; size_t n; size_t c; } U8Vec;
typedef struct { char **v; size_t n; size_t c; } StrVec;

typedef struct {
  uint32_t *words;
  uint32_t len;
} Packet;

typedef struct {
  Packet *v;
  size_t n;
  size_t c;
} PacketVec;

typedef struct {
  uint32_t id;
  uint32_t off;
  uint32_t comp_len;
  uint32_t raw_len;
  uint32_t codec;
} ContentRow;

typedef struct {
  ContentRow *v;
  size_t n;
  size_t c;
} ContentVec;

static char *str_dup_local(const char *s) {
  size_t n = strlen(s);
  char *p = (char *)malloc(n + 1);
  if (!p) return NULL;
  memcpy(p, s, n + 1);
  return p;
}

static bool u32_push(U32Vec *a, uint32_t x) {
  if (a->n == a->c) {
    size_t nc = ARR_GROW_CAP(a->c);
    uint32_t *nv = (uint32_t *)realloc(a->v, nc * sizeof(uint32_t));
    if (!nv) return false;
    a->v = nv;
    a->c = nc;
  }
  a->v[a->n++] = x;
  return true;
}

static bool u8_append(U8Vec *a, const uint8_t *buf, size_t n) {
  if (n == 0) return true;
  if (a->n + n > a->c) {
    size_t nc = a->c ? a->c : 1024;
    while (nc < a->n + n) nc *= 2;
    uint8_t *nv = (uint8_t *)realloc(a->v, nc);
    if (!nv) return false;
    a->v = nv;
    a->c = nc;
  }
  memcpy(a->v + a->n, buf, n);
  a->n += n;
  return true;
}

static bool str_push(StrVec *a, const char *s) {
  if (a->n == a->c) {
    size_t nc = ARR_GROW_CAP(a->c);
    char **nv = (char **)realloc(a->v, nc * sizeof(char *));
    if (!nv) return false;
    a->v = nv;
    a->c = nc;
  }
  char *cp = str_dup_local(s);
  if (!cp) return false;
  a->v[a->n++] = cp;
  return true;
}

static int str_cmp(const void *a, const void *b) {
  const char *sa = *(const char * const *)a;
  const char *sb = *(const char * const *)b;
  return strcmp(sa, sb);
}

static bool packet_push(PacketVec *a, Packet p) {
  if (a->n == a->c) {
    size_t nc = ARR_GROW_CAP(a->c);
    Packet *nv = (Packet *)realloc(a->v, nc * sizeof(Packet));
    if (!nv) return false;
    a->v = nv;
    a->c = nc;
  }
  a->v[a->n++] = p;
  return true;
}

static bool content_push(ContentVec *a, ContentRow r) {
  if (a->n == a->c) {
    size_t nc = ARR_GROW_CAP(a->c);
    ContentRow *nv = (ContentRow *)realloc(a->v, nc * sizeof(ContentRow));
    if (!nv) return false;
    a->v = nv;
    a->c = nc;
  }
  a->v[a->n++] = r;
  return true;
}

static void str_free(StrVec *a) {
  if (!a) return;
  for (size_t i = 0; i < a->n; i++) free(a->v[i]);
  free(a->v);
  a->v = NULL; a->n = a->c = 0;
}

static void packet_free(PacketVec *a) {
  if (!a) return;
  for (size_t i = 0; i < a->n; i++) free(a->v[i].words);
  free(a->v);
  a->v = NULL; a->n = a->c = 0;
}

static uint32_t fnv1a32(const uint8_t *buf, size_t n) {
  uint32_t h = 0x811c9dc5u;
  for (size_t i = 0; i < n; i++) {
    h ^= (uint32_t)buf[i];
    h *= 0x01000193u;
  }
  return h;
}

static bool read_file(const char *path, uint8_t **out, size_t *out_len) {
  FILE *f = fopen(path, "rb");
  if (!f) return false;
  if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return false; }
  long sz = ftell(f);
  if (sz < 0) { fclose(f); return false; }
  if (fseek(f, 0, SEEK_SET) != 0) { fclose(f); return false; }
  uint8_t *buf = (uint8_t *)malloc((size_t)sz);
  if (!buf && sz > 0) { fclose(f); return false; }
  if (sz > 0 && fread(buf, 1, (size_t)sz, f) != (size_t)sz) { free(buf); fclose(f); return false; }
  fclose(f);
  *out = buf;
  *out_len = (size_t)sz;
  return true;
}

static bool write_u32_le(const char *path, const uint32_t *w, size_t n) {
  FILE *f = fopen(path, "wb");
  if (!f) return false;
  for (size_t i = 0; i < n; i++) {
    uint8_t b[4];
    b[0] = (uint8_t)(w[i] & 0xffu);
    b[1] = (uint8_t)((w[i] >> 8u) & 0xffu);
    b[2] = (uint8_t)((w[i] >> 16u) & 0xffu);
    b[3] = (uint8_t)((w[i] >> 24u) & 0xffu);
    if (fwrite(b, 1, 4, f) != 4) { fclose(f); return false; }
  }
  fclose(f);
  return true;
}

static bool read_u32_le(const char *path, uint32_t **out, size_t *out_n) {
  uint8_t *raw = NULL;
  size_t raw_len = 0;
  if (!read_file(path, &raw, &raw_len)) return false;
  if ((raw_len % 4u) != 0u) { free(raw); return false; }
  size_t n = raw_len / 4u;
  uint32_t *w = (uint32_t *)malloc(n * sizeof(uint32_t));
  if (!w) { free(raw); return false; }
  for (size_t i = 0; i < n; i++) {
    w[i] = (uint32_t)raw[i * 4u] |
           ((uint32_t)raw[i * 4u + 1u] << 8u) |
           ((uint32_t)raw[i * 4u + 2u] << 16u) |
           ((uint32_t)raw[i * 4u + 3u] << 24u);
  }
  free(raw);
  *out = w;
  *out_n = n;
  return true;
}

static bool ensure_dir(const char *path) {
  char tmp[PATH_MAX];
  size_t n = strlen(path);
  if (n >= sizeof(tmp)) return false;
  memcpy(tmp, path, n + 1);
  for (size_t i = 1; i < n; i++) {
    if (tmp[i] == '/') {
      tmp[i] = '\0';
      if (mkdir(tmp, 0755) != 0 && errno != EEXIST) return false;
      tmp[i] = '/';
    }
  }
  if (mkdir(tmp, 0755) != 0 && errno != EEXIST) return false;
  return true;
}

static bool has_ext(const char *name, const char *ext) {
  size_t ln = strlen(name), le = strlen(ext);
  if (ln < le) return false;
  return strcmp(name + ln - le, ext) == 0;
}

static bool is_supported_lang(const char *name) {
  static const char *exts[] = {
    ".js", ".mjs", ".cjs", ".ts", ".tsx", ".jsx", ".html", ".htm", ".css", ".scss",
    ".sql", ".php", ".py", ".rb", ".go", ".java", ".kt", ".rs", ".json", ".yml", ".yaml"
  };
  for (size_t i = 0; i < sizeof(exts) / sizeof(exts[0]); i++) if (has_ext(name, exts[i])) return true;
  return false;
}

static uint32_t lang_id_for_ext(const char *name) {
  if (has_ext(name, ".js") || has_ext(name, ".mjs") || has_ext(name, ".cjs") || has_ext(name, ".jsx")) return 1u;
  if (has_ext(name, ".ts") || has_ext(name, ".tsx")) return 2u;
  if (has_ext(name, ".html") || has_ext(name, ".htm")) return 3u;
  if (has_ext(name, ".css") || has_ext(name, ".scss")) return 4u;
  if (has_ext(name, ".sql")) return 5u;
  if (has_ext(name, ".php")) return 6u;
  if (has_ext(name, ".py")) return 7u;
  if (has_ext(name, ".rb")) return 8u;
  if (has_ext(name, ".go")) return 9u;
  if (has_ext(name, ".java")) return 10u;
  if (has_ext(name, ".kt")) return 11u;
  if (has_ext(name, ".rs")) return 12u;
  if (has_ext(name, ".json")) return 13u;
  if (has_ext(name, ".yml") || has_ext(name, ".yaml")) return 14u;
  return 0u;
}

static bool skip_dir_name(const char *name) {
  static const char *skip[] = {
    ".git", "node_modules", "vendor", "dist", "build", "target", "coverage", ".next", ".cache", "__pycache__"
  };
  for (size_t i = 0; i < sizeof(skip) / sizeof(skip[0]); i++) if (strcmp(name, skip[i]) == 0) return true;
  return false;
}

static bool is_likely_text(const uint8_t *buf, size_t n) {
  if (n == 0) return false;
  size_t ctrl = 0;
  for (size_t i = 0; i < n; i++) {
    uint8_t v = buf[i];
    if (v == 0u) return false;
    if (v < 9u || (v > 13u && v < 32u)) ctrl++;
  }
  return ((double)ctrl / (double)n) < 0.08;
}

static bool walk_files_rec(const char *dir, StrVec *out, bool lang_only) {
  DIR *d = opendir(dir);
  if (!d) return false;
  struct dirent *e;
  while ((e = readdir(d)) != NULL) {
    if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0) continue;
    char p[PATH_MAX];
    if (snprintf(p, sizeof(p), "%s/%s", dir, e->d_name) >= (int)sizeof(p)) { closedir(d); return false; }
    struct stat st;
    if (stat(p, &st) != 0) { closedir(d); return false; }
    if (S_ISDIR(st.st_mode)) {
      if (skip_dir_name(e->d_name)) continue;
      if (!walk_files_rec(p, out, lang_only)) { closedir(d); return false; }
      continue;
    }
    if (!S_ISREG(st.st_mode)) continue;
    if (lang_only && !is_supported_lang(e->d_name)) continue;
    if (!str_push(out, p)) { closedir(d); return false; }
  }
  closedir(d);
  return true;
}

static bool bytes_to_u32_packed(const uint8_t *buf, size_t n, uint32_t **out, size_t *out_n) {
  size_t wn = (n + 3u) / 4u;
  uint32_t *w = (uint32_t *)calloc(wn ? wn : 1u, sizeof(uint32_t));
  if (!w) return false;
  for (size_t i = 0; i < n; i++) {
    w[i / 4u] |= ((uint32_t)buf[i]) << ((i % 4u) * 8u);
  }
  *out = w;
  *out_n = wn;
  return true;
}

static bool u32_packed_to_bytes(const uint32_t *w, size_t wn, size_t exact_n, uint8_t **out) {
  uint8_t *buf = (uint8_t *)malloc(exact_n ? exact_n : 1u);
  if (!buf) return false;
  for (size_t i = 0; i < exact_n; i++) {
    size_t idx = i / 4u;
    if (idx >= wn) { free(buf); return false; }
    buf[i] = (uint8_t)((w[idx] >> ((i % 4u) * 8u)) & 0xffu);
  }
  *out = buf;
  return true;
}

static bool make_packet(const uint8_t *content, size_t content_len, const char *path_key,
                        uint32_t lang_id, size_t preview_bytes, size_t max_tokens,
                        uint32_t **out_words, uint32_t *out_len) {
  uint32_t content_hash = fnv1a32(content, content_len);
  uint32_t path_hash = fnv1a32((const uint8_t *)path_key, strlen(path_key));

  U32Vec symbols = {0};
  size_t i = 0;
  size_t tokens = 0;
  while (i < content_len && tokens < max_tokens) {
    uint8_t c = content[i];
    bool is_start = (c == '_') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
    if (!is_start) { i++; continue; }
    size_t j = i + 1;
    while (j < content_len) {
      uint8_t d = content[j];
      bool ok = (d == '_') || (d >= 'A' && d <= 'Z') || (d >= 'a' && d <= 'z') || (d >= '0' && d <= '9');
      if (!ok) break;
      j++;
    }
    uint32_t h = fnv1a32(content + i, j - i);
    if (!u32_push(&symbols, h)) { free(symbols.v); return false; }
    tokens++;
    i = j;
  }

  size_t lines = 1;
  for (size_t k = 0; k < content_len; k++) if (content[k] == '\n') lines++;

  size_t preview_n = content_len < preview_bytes ? content_len : preview_bytes;
  uint32_t *source_u8 = (uint32_t *)malloc((preview_n ? preview_n : 1u) * sizeof(uint32_t));
  if (!source_u8) { free(symbols.v); return false; }
  for (size_t k = 0; k < preview_n; k++) source_u8[k] = content[k];

  uint32_t code[6] = {13u, 0u, 0u, 0u, 0u, 0u};
  uint32_t meta[8] = {
    1u, (uint32_t)content_len, (uint32_t)lines, lang_id,
    2u, path_hash, content_hash, (uint32_t)tokens,
  };

  // sections: CODE,SLOT,SOURCE_U8,SYMBOL_HASH,META
  uint32_t sec_count = 5u;
  uint32_t toc_base = 8u;
  uint32_t payload_base = 8u + sec_count * 4u;
  uint32_t len_code = 6u, rw_code = 6u;
  uint32_t len_slot = 0u, rw_slot = 4u;
  uint32_t len_source = (uint32_t)preview_n, rw_source = 1u;
  uint32_t len_sym = (uint32_t)symbols.n, rw_sym = 1u;
  uint32_t len_meta = 8u, rw_meta = 4u;
  uint32_t total = payload_base + len_code + len_slot + len_source + len_sym + len_meta;

  uint32_t *w = (uint32_t *)calloc(total, sizeof(uint32_t));
  if (!w) { free(source_u8); free(symbols.v); return false; }

  w[0] = A2A_MAGIC;
  w[1] = A2A_VERSION;
  w[2] = sec_count;
  w[3] = 0u;
  w[4] = toc_base;
  w[5] = payload_base;
  w[6] = total;
  w[7] = 0u;

  uint32_t p = payload_base;

  // CODE
  w[toc_base + 0] = 1u;
  w[toc_base + 1] = p;
  w[toc_base + 2] = len_code;
  w[toc_base + 3] = rw_code;
  memcpy(w + p, code, sizeof(code));
  p += len_code;

  // SLOT
  w[toc_base + 4] = 2u;
  w[toc_base + 5] = p;
  w[toc_base + 6] = len_slot;
  w[toc_base + 7] = rw_slot;
  p += len_slot;

  // SOURCE_U8
  w[toc_base + 8] = 3u;
  w[toc_base + 9] = p;
  w[toc_base + 10] = len_source;
  w[toc_base + 11] = rw_source;
  if (len_source) memcpy(w + p, source_u8, len_source * sizeof(uint32_t));
  p += len_source;

  // SYMBOL_HASH
  w[toc_base + 12] = 4u;
  w[toc_base + 13] = p;
  w[toc_base + 14] = len_sym;
  w[toc_base + 15] = rw_sym;
  if (len_sym) memcpy(w + p, symbols.v, len_sym * sizeof(uint32_t));
  p += len_sym;

  // META
  w[toc_base + 16] = 5u;
  w[toc_base + 17] = p;
  w[toc_base + 18] = len_meta;
  w[toc_base + 19] = rw_meta;
  memcpy(w + p, meta, sizeof(meta));

  free(source_u8);
  free(symbols.v);
  *out_words = w;
  *out_len = total;
  return true;
}

static int cmd_rebuild_db(const char *core_dir) {
  if (!ensure_dir(core_dir)) return 1;

  // OPS: [opId,engineId,aclId,procId,minArgs,maxArgs]
  uint32_t ops[] = {
    9001u, 1u, 1u, 9001u, 0u, 0u,
    1001u, 1u, 2u, 1001u, 1u, 1u,
    1002u, 1u, 2u, 1002u, 3u, 3u,
    2001u, 1u, 2u, 2001u, 1u, 1u,
    2002u, 1u, 2u, 2002u, 3u, 3u,
    3001u, 1u, 3u, 3001u, 4u, 4u,
    4001u, 1u, 3u, 4001u, 1u, 1u,
  };
  // SIG: [opId,argIndex,typeId,flags]
  uint32_t sig[] = {
    1001u, 0u, 3u, 0u,
    1002u, 0u, 3u, 0u, 1002u, 1u, 1u, 0u, 1002u, 2u, 1u, 0u,
    2001u, 0u, 3u, 0u,
    2002u, 0u, 3u, 0u, 2002u, 1u, 3u, 0u, 2002u, 2u, 1u, 0u,
    3001u, 0u, 3u, 0u, 3001u, 1u, 3u, 0u, 3001u, 2u, 3u, 0u, 3001u, 3u, 1u, 0u,
    4001u, 0u, 3u, 0u,
  };
  uint32_t meta[] = {1u,1u,0u,0u, 2u,7u,13u,0u};

  uint32_t sec_count = 3u, toc_base = 8u, payload_base = 8u + 12u;
  uint32_t len_ops = (uint32_t)(sizeof(ops)/sizeof(ops[0]));
  uint32_t len_sig = (uint32_t)(sizeof(sig)/sizeof(sig[0]));
  uint32_t len_meta = (uint32_t)(sizeof(meta)/sizeof(meta[0]));
  uint32_t total = payload_base + len_ops + len_sig + len_meta;
  uint32_t *w = (uint32_t *)calloc(total, sizeof(uint32_t));
  if (!w) return 1;

  w[0]=D2B_MAGIC; w[1]=D2B_VERSION; w[2]=sec_count; w[3]=0u;
  w[4]=toc_base; w[5]=payload_base; w[6]=total; w[7]=0u;
  uint32_t p = payload_base;

  w[toc_base+0]=1u; w[toc_base+1]=p; w[toc_base+2]=len_ops; w[toc_base+3]=6u; memcpy(w+p, ops, sizeof(ops)); p += len_ops;
  w[toc_base+4]=2u; w[toc_base+5]=p; w[toc_base+6]=len_sig; w[toc_base+7]=4u; memcpy(w+p, sig, sizeof(sig)); p += len_sig;
  w[toc_base+8]=3u; w[toc_base+9]=p; w[toc_base+10]=len_meta; w[toc_base+11]=4u; memcpy(w+p, meta, sizeof(meta));

  char out[PATH_MAX];
  snprintf(out, sizeof(out), "%s/m2m.db.packet.aiir", core_dir);
  bool ok = write_u32_le(out, w, total);
  free(w);
  if (!ok) return 1;
  printf("1 %u %u %u\n", total, len_ops/6u, len_sig/4u);
  return 0;
}

static int cmd_rebuild_core(const char *git_root, const char *core_dir) {
  const size_t MAX_FILES_TOTAL = getenv("AI_MAX_FILES_TOTAL") ? (size_t)strtoull(getenv("AI_MAX_FILES_TOTAL"), NULL, 10) : 640u;
  const size_t MAX_FILES_PER_REPO = getenv("AI_MAX_FILES_PER_REPO") ? (size_t)strtoull(getenv("AI_MAX_FILES_PER_REPO"), NULL, 10) : 80u;
  const size_t MAX_FILE_BYTES = getenv("AI_MAX_FILE_BYTES") ? (size_t)strtoull(getenv("AI_MAX_FILE_BYTES"), NULL, 10) : 220000u;
  const size_t PREVIEW_BYTES = getenv("AI_PREVIEW_BYTES") ? (size_t)strtoull(getenv("AI_PREVIEW_BYTES"), NULL, 10) : 2048u;
  const size_t MAX_TOKENS = getenv("AI_MAX_TOKENS") ? (size_t)strtoull(getenv("AI_MAX_TOKENS"), NULL, 10) : 2048u;
  const size_t MAX_ADAPT_BYTES = getenv("AI_MAX_ADAPT_BYTES") ? (size_t)strtoull(getenv("AI_MAX_ADAPT_BYTES"), NULL, 10) : (6u * 1024u * 1024u);

  if (!ensure_dir(core_dir)) return 1;

  StrVec repos = {0};
  DIR *d = opendir(git_root);
  if (!d) return 1;
  struct dirent *e;
  while ((e = readdir(d)) != NULL) {
    if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0) continue;
    char p[PATH_MAX], g[PATH_MAX];
    snprintf(p, sizeof(p), "%s/%s", git_root, e->d_name);
    struct stat st;
    if (stat(p, &st) != 0 || !S_ISDIR(st.st_mode)) continue;
    if (snprintf(g, sizeof(g), "%s/.git", p) >= (int)sizeof(g)) continue;
    if (stat(g, &st) == 0 && S_ISDIR(st.st_mode)) {
      if (!str_push(&repos, p)) { closedir(d); str_free(&repos); return 1; }
    }
  }
  closedir(d);
  qsort(repos.v, repos.n, sizeof(char *), str_cmp);

  PacketVec packets = {0};
  U32Vec adapt_rows = {0};
  U32Vec adapt_blob = {0};
  size_t adapt_bytes = 0;

  for (size_t ri = 0; ri < repos.n && packets.n < MAX_FILES_TOTAL; ri++) {
    const char *repo = repos.v[ri];
    const char *slash = strrchr(repo, '/');
    const char *repo_name = slash ? slash + 1 : repo;

    StrVec files = {0};
    if (!walk_files_rec(repo, &files, true)) { str_free(&files); continue; }
    qsort(files.v, files.n, sizeof(char *), str_cmp);

    size_t picked = 0;
    for (size_t fi = 0; fi < files.n && packets.n < MAX_FILES_TOTAL && picked < MAX_FILES_PER_REPO; fi++) {
      const char *fp = files.v[fi];
      struct stat st;
      if (stat(fp, &st) != 0 || !S_ISREG(st.st_mode)) continue;
      size_t fs = (size_t)st.st_size;
      if (fs == 0 || fs > MAX_FILE_BYTES) continue;

      uint8_t *raw = NULL;
      size_t raw_len = 0;
      if (!read_file(fp, &raw, &raw_len)) continue;
      if (!is_likely_text(raw, raw_len)) { free(raw); continue; }

      size_t repo_len = strlen(repo);
      const char *rel = fp;
      if (strncmp(fp, repo, repo_len) == 0 && fp[repo_len] == '/') rel = fp + repo_len + 1;
      char key[PATH_MAX * 2];
      snprintf(key, sizeof(key), "%s/%s", repo_name, rel);

      uint32_t *pw = NULL;
      uint32_t plen = 0;
      if (!make_packet(raw, raw_len, key, lang_id_for_ext(fp), PREVIEW_BYTES, MAX_TOKENS, &pw, &plen)) {
        free(raw);
        continue;
      }
      Packet p = {pw, plen};
      if (!packet_push(&packets, p)) {
        free(pw);
        free(raw);
        continue;
      }

      uint32_t file_id = (uint32_t)(packets.n - 1);
      if (raw_len > PREVIEW_BYTES && adapt_bytes + raw_len <= MAX_ADAPT_BYTES) {
        uint32_t off = (uint32_t)adapt_blob.n;
        for (size_t k = 0; k < raw_len; k++) {
          if (!u32_push(&adapt_blob, raw[k])) break;
        }
        uint32_t len = (uint32_t)raw_len;
        if (!u32_push(&adapt_rows, file_id) || !u32_push(&adapt_rows, off) || !u32_push(&adapt_rows, len)) {
          free(raw);
          str_free(&files);
          str_free(&repos);
          packet_free(&packets);
          free(adapt_rows.v);
          free(adapt_blob.v);
          return 1;
        }
        adapt_bytes += raw_len;
      }

      picked++;
      free(raw);
    }

    str_free(&files);
  }

  U32Vec table = {0};
  U32Vec blob = {0};
  for (size_t i = 0; i < packets.n; i++) {
    uint32_t off = (uint32_t)blob.n;
    if (!u32_push(&table, (uint32_t)i) || !u32_push(&table, off) || !u32_push(&table, packets.v[i].len)) {
      str_free(&repos); packet_free(&packets); free(adapt_rows.v); free(adapt_blob.v); free(table.v); free(blob.v); return 1;
    }
    for (uint32_t k = 0; k < packets.v[i].len; k++) if (!u32_push(&blob, packets.v[i].words[k])) {
      str_free(&repos); packet_free(&packets); free(adapt_rows.v); free(adapt_blob.v); free(table.v); free(blob.v); return 1;
    }
  }

  U32Vec adapt_ids = {0};
  for (size_t i = 0; i + 2 < adapt_rows.n; i += 3) if (!u32_push(&adapt_ids, adapt_rows.v[i])) {
    str_free(&repos); packet_free(&packets); free(adapt_rows.v); free(adapt_blob.v); free(table.v); free(blob.v); free(adapt_ids.v); return 1;
  }

  char p1[PATH_MAX], p2[PATH_MAX], p3[PATH_MAX], p4[PATH_MAX], p5[PATH_MAX];
  snprintf(p1, sizeof(p1), "%s/m2m.ai2ai.lite.table.aiir", core_dir);
  snprintf(p2, sizeof(p2), "%s/m2m.ai2ai.lite.blob.aiir", core_dir);
  snprintf(p3, sizeof(p3), "%s/m2m.ai2ai.source.adapt.table.aiir", core_dir);
  snprintf(p4, sizeof(p4), "%s/m2m.ai2ai.source.adapt.ids.aiir", core_dir);
  snprintf(p5, sizeof(p5), "%s/m2m.ai2ai.source.adapt.blob.aiir", core_dir);

  bool ok = write_u32_le(p1, table.v, table.n) && write_u32_le(p2, blob.v, blob.n) &&
            write_u32_le(p3, adapt_rows.v, adapt_rows.n) && write_u32_le(p4, adapt_ids.v, adapt_ids.n) &&
            write_u32_le(p5, adapt_blob.v, adapt_blob.n);

  printf("1 %zu %zu %zu %zu %zu %zu\n", repos.n, packets.n, table.n, blob.n, adapt_ids.n, adapt_blob.n);

  str_free(&repos);
  packet_free(&packets);
  free(adapt_rows.v);
  free(adapt_blob.v);
  free(adapt_ids.v);
  free(table.v);
  free(blob.v);
  return ok ? 0 : 1;
}

static int cmd_build_package(const char *src, const char *out_dir, const char *core_dir) {
  if (!ensure_dir(out_dir)) return 1;

  StrVec files = {0};
  if (!walk_files_rec(src, &files, false)) { str_free(&files); return 1; }
  qsort(files.v, files.n, sizeof(char *), str_cmp);

  U8Vec path_blob = {0};
  U8Vec src_blob = {0};
  U32Vec files_table = {0};
  ContentVec content = {0};

  for (size_t i = 0; i < files.n; i++) {
    const char *fp = files.v[i];
    size_t src_len = strlen(src);
    const char *rel = fp;
    if (strncmp(fp, src, src_len) == 0 && fp[src_len] == '/') rel = fp + src_len + 1;

    uint8_t *raw = NULL;
    size_t raw_len = 0;
    if (!read_file(fp, &raw, &raw_len)) continue;

    uint32_t poff = (uint32_t)path_blob.n;
    uint32_t plen = (uint32_t)strlen(rel);
    uint32_t cid = (uint32_t)content.n;
    uint32_t flags = 0u;

    if (!u8_append(&path_blob, (const uint8_t *)rel, plen) ||
        !u8_append(&src_blob, raw, raw_len) ||
        !u32_push(&files_table, (uint32_t)i) ||
        !u32_push(&files_table, poff) ||
        !u32_push(&files_table, plen) ||
        !u32_push(&files_table, cid) ||
        !u32_push(&files_table, flags)) {
      free(raw);
      str_free(&files);
      free(path_blob.v); free(src_blob.v); free(files_table.v); free(content.v);
      return 1;
    }

    ContentRow r;
    r.id = cid;
    r.off = (uint32_t)(src_blob.n - raw_len);
    r.comp_len = (uint32_t)raw_len;
    r.raw_len = (uint32_t)raw_len;
    r.codec = 0u;
    if (!content_push(&content, r)) {
      free(raw);
      str_free(&files);
      free(path_blob.v); free(src_blob.v); free(files_table.v); free(content.v);
      return 1;
    }

    free(raw);
  }

  uint32_t *paths_w = NULL, *source_w = NULL;
  size_t paths_n = 0, source_n = 0;
  if (!bytes_to_u32_packed(path_blob.v, path_blob.n, &paths_w, &paths_n) ||
      !bytes_to_u32_packed(src_blob.v, src_blob.n, &source_w, &source_n)) {
    str_free(&files); free(path_blob.v); free(src_blob.v); free(files_table.v); free(content.v); free(paths_w); free(source_w);
    return 1;
  }

  U32Vec content_table = {0};
  for (size_t i = 0; i < content.n; i++) {
    if (!u32_push(&content_table, content.v[i].id) || !u32_push(&content_table, content.v[i].off) ||
        !u32_push(&content_table, content.v[i].comp_len) || !u32_push(&content_table, content.v[i].raw_len) ||
        !u32_push(&content_table, content.v[i].codec)) {
      str_free(&files); free(path_blob.v); free(src_blob.v); free(files_table.v); free(content.v); free(paths_w); free(source_w); free(content_table.v);
      return 1;
    }
  }

  uint32_t manifest[8] = {
    2u, 1u, (uint32_t)content.n, (uint32_t)files_table.n, (uint32_t)paths_n,
    (uint32_t)content_table.n, (uint32_t)source_n, (uint32_t)content.n,
  };

  char p[PATH_MAX];
  snprintf(p, sizeof(p), "%s/manifest.aiir", out_dir); if (!write_u32_le(p, manifest, 8)) return 1;
  snprintf(p, sizeof(p), "%s/files.table.aiir", out_dir); if (!write_u32_le(p, files_table.v, files_table.n)) return 1;
  snprintf(p, sizeof(p), "%s/paths.blob.aiir", out_dir); if (!write_u32_le(p, paths_w, paths_n)) return 1;
  snprintf(p, sizeof(p), "%s/content.table.aiir", out_dir); if (!write_u32_le(p, content_table.v, content_table.n)) return 1;
  snprintf(p, sizeof(p), "%s/source.blob.aiir", out_dir); if (!write_u32_le(p, source_w, source_n)) return 1;

  const char *core_files[] = {
    "m2m.ai2ai.lite.table.aiir",
    "m2m.ai2ai.lite.blob.aiir",
    "m2m.ai2ai.source.adapt.table.aiir",
    "m2m.ai2ai.source.adapt.ids.aiir",
    "m2m.ai2ai.source.adapt.blob.aiir",
    "m2m.db.packet.aiir",
  };
  for (size_t i = 0; i < sizeof(core_files)/sizeof(core_files[0]); i++) {
    char srcp[PATH_MAX], dstp[PATH_MAX];
    snprintf(srcp, sizeof(srcp), "%s/%s", core_dir, core_files[i]);
    snprintf(dstp, sizeof(dstp), "%s/%s", out_dir, core_files[i]);
    uint8_t *raw = NULL; size_t n = 0;
    if (!read_file(srcp, &raw, &n)) continue;
    FILE *f = fopen(dstp, "wb");
    if (f) { fwrite(raw, 1, n, f); fclose(f); }
    free(raw);
  }

  printf("1 2 1 %zu %zu %zu %zu %zu %zu %zu\n", files.n, content.n, src_blob.n, files_table.n, paths_n, content_table.n, source_n);

  str_free(&files);
  free(path_blob.v); free(src_blob.v); free(files_table.v); free(content.v);
  free(paths_w); free(source_w); free(content_table.v);
  return 0;
}

static bool pick_aiir(const char *dir, const char *stem, char *out, size_t out_cap) {
  snprintf(out, out_cap, "%s/%s.aiir", dir, stem);
  if (access(out, R_OK) == 0) return true;
  snprintf(out, out_cap, "%s/%s.u32", dir, stem);
  if (access(out, R_OK) == 0) return true;
  return false;
}

static bool validate_a2a_packet(const uint32_t *w, size_t n) {
  if (!w || n < 8u) return false;
  if (w[0] != A2A_MAGIC) return false;
  uint32_t sec_count = w[2], toc_base = w[4], total = w[6];
  if (total != n) return false;
  for (uint32_t i = 0; i < sec_count; i++) {
    uint32_t t = toc_base + i * 4u;
    if (t + 3u >= n) return false;
    uint32_t off = w[t + 1u], len = w[t + 2u], rw = w[t + 3u];
    if (rw == 0u) return false;
    if (len % rw != 0u) return false;
    if ((uint64_t)off + (uint64_t)len > n) return false;
  }
  return true;
}

static uint32_t xorshift32(uint32_t *s) {
  uint32_t x = *s;
  x ^= x << 13u;
  x ^= x >> 17u;
  x ^= x << 5u;
  *s = x;
  return x;
}

static int cmd_conformance(const char *core_dir, uint32_t iters) {
  char ptab[PATH_MAX], pblob[PATH_MAX];
  if (!pick_aiir(core_dir, "m2m.ai2ai.lite.table", ptab, sizeof(ptab)) ||
      !pick_aiir(core_dir, "m2m.ai2ai.lite.blob", pblob, sizeof(pblob))) return 1;

  uint32_t *tab = NULL, *blob = NULL;
  size_t tab_n = 0, blob_n = 0;
  if (!read_u32_le(ptab, &tab, &tab_n) || !read_u32_le(pblob, &blob, &blob_n)) {
    free(tab); free(blob); return 1;
  }
  if (tab_n < 3u || tab_n % 3u != 0u) { free(tab); free(blob); return 1; }

  uint32_t off = tab[1], len = tab[2];
  if ((uint64_t)off + (uint64_t)len > blob_n) { free(tab); free(blob); return 1; }

  const uint32_t *pkt = blob + off;
  bool ok_base = validate_a2a_packet(pkt, len);
  if (!ok_base) { free(tab); free(blob); return 1; }

  uint32_t seed = 0x12345678u;
  uint32_t rejected = 0u;
  for (uint32_t i = 0; i < iters; i++) {
    uint32_t *m = (uint32_t *)malloc(len * sizeof(uint32_t));
    if (!m) break;
    memcpy(m, pkt, len * sizeof(uint32_t));
    uint32_t idx = xorshift32(&seed) % len;
    uint32_t bit = 1u << (xorshift32(&seed) % 31u);
    m[idx] ^= bit;
    if (!validate_a2a_packet(m, len)) rejected++;
    free(m);
  }

  printf("1 %u %u %u\n", iters, rejected, ok_base ? 1u : 0u);
  free(tab); free(blob);
  return 0;
}

static int cmd_unpack_package(const char *in_dir, const char *out_dir) {
  if (!ensure_dir(out_dir)) return 1;
  char p[PATH_MAX];
  if (!pick_aiir(in_dir, "manifest", p, sizeof(p))) return 1;

  uint32_t *manifest = NULL; size_t mlen = 0;
  if (!read_u32_le(p, &manifest, &mlen) || mlen < 8 || manifest[0] != 2u) { free(manifest); return 1; }

  char pf[PATH_MAX], pp[PATH_MAX], pc[PATH_MAX], ps[PATH_MAX];
  if (!pick_aiir(in_dir, "files.table", pf, sizeof(pf)) ||
      !pick_aiir(in_dir, "paths.blob", pp, sizeof(pp)) ||
      !pick_aiir(in_dir, "content.table", pc, sizeof(pc)) ||
      !pick_aiir(in_dir, "source.blob", ps, sizeof(ps))) {
    free(manifest);
    return 1;
  }

  uint32_t *files_t = NULL, *paths_w = NULL, *content_t = NULL, *source_w = NULL;
  size_t files_n = 0, paths_n = 0, content_n = 0, source_n = 0;
  if (!read_u32_le(pf, &files_t, &files_n) || !read_u32_le(pp, &paths_w, &paths_n) ||
      !read_u32_le(pc, &content_t, &content_n) || !read_u32_le(ps, &source_w, &source_n)) {
    free(manifest); free(files_t); free(paths_w); free(content_t); free(source_w); return 1;
  }

  if (files_n % 5u != 0u || content_n % 5u != 0u) {
    free(manifest); free(files_t); free(paths_w); free(content_t); free(source_w); return 1;
  }

  uint32_t file_count = (uint32_t)(files_n / 5u);
  uint32_t content_count = (uint32_t)(content_n / 5u);
  if (file_count == 0 || content_count == 0) {
    free(manifest); free(files_t); free(paths_w); free(content_t); free(source_w); return 0;
  }

  uint32_t p_last = (file_count - 1u) * 5u;
  size_t path_bytes_len = (size_t)files_t[p_last + 1u] + (size_t)files_t[p_last + 2u];
  uint32_t c_last = (content_count - 1u) * 5u;
  size_t src_bytes_len = (size_t)content_t[c_last + 1u] + (size_t)content_t[c_last + 2u];

  uint8_t *path_bytes = NULL, *src_bytes = NULL;
  if (!u32_packed_to_bytes(paths_w, paths_n, path_bytes_len, &path_bytes) ||
      !u32_packed_to_bytes(source_w, source_n, src_bytes_len, &src_bytes)) {
    free(manifest); free(files_t); free(paths_w); free(content_t); free(source_w); free(path_bytes); free(src_bytes); return 1;
  }

  for (uint32_t i = 0; i < file_count; i++) {
    uint32_t fp = i * 5u;
    uint32_t poff = files_t[fp + 1u], plen = files_t[fp + 2u], cid = files_t[fp + 3u];
    if (cid >= content_count || (size_t)poff + (size_t)plen > path_bytes_len) continue;

    uint32_t cp = cid * 5u;
    uint32_t off = content_t[cp + 1u], clen = content_t[cp + 2u], codec = content_t[cp + 4u];
    if (codec != 0u || (size_t)off + (size_t)clen > src_bytes_len) continue;

    char rel[PATH_MAX];
    size_t rlen = plen < sizeof(rel) - 1u ? plen : sizeof(rel) - 1u;
    memcpy(rel, path_bytes + poff, rlen);
    rel[rlen] = '\0';

    char dst[PATH_MAX];
    if (snprintf(dst, sizeof(dst), "%s/%s", out_dir, rel) >= (int)sizeof(dst)) continue;
    char *slash = strrchr(dst, '/');
    if (slash) {
      *slash = '\0';
      ensure_dir(dst);
      *slash = '/';
    }

    FILE *f = fopen(dst, "wb");
    if (!f) continue;
    fwrite(src_bytes + off, 1, clen, f);
    fclose(f);
  }

  printf("1 %u %u\n", manifest[0], file_count);
  free(manifest); free(files_t); free(paths_w); free(content_t); free(source_w); free(path_bytes); free(src_bytes);
  return 0;
}

static void usage(const char *argv0) {
  fprintf(stderr,
          "usage:\n"
          "  %s rebuild-db <core-dir>\n"
          "  %s rebuild-core <git-root> <core-dir>\n"
          "  %s rebuild-all <git-root> <core-dir>\n"
          "  %s build-package <src-dir> <out-dir> <core-dir>\n"
          "  %s unpack-package <package-dir> <out-dir>\n"
          "  %s serve\n"
          "  %s bootstrap <git-root> <core-dir> [serve]\n"
          "  %s conformance <core-dir> [iters]\n",
          argv0, argv0, argv0, argv0, argv0, argv0, argv0, argv0);
}

int main(int argc, char **argv) {
  if (argc < 2) { usage(argv[0]); return 1; }
  if (strcmp(argv[1], "rebuild-db") == 0) {
    if (argc != 3) { usage(argv[0]); return 1; }
    return cmd_rebuild_db(argv[2]);
  }
  if (strcmp(argv[1], "rebuild-core") == 0) {
    if (argc != 4) { usage(argv[0]); return 1; }
    return cmd_rebuild_core(argv[2], argv[3]);
  }
  if (strcmp(argv[1], "rebuild-all") == 0) {
    if (argc != 4) { usage(argv[0]); return 1; }
    if (cmd_rebuild_db(argv[3]) != 0) return 1;
    return cmd_rebuild_core(argv[2], argv[3]);
  }
  if (strcmp(argv[1], "build-package") == 0) {
    if (argc != 5) { usage(argv[0]); return 1; }
    return cmd_build_package(argv[2], argv[3], argv[4]);
  }
  if (strcmp(argv[1], "unpack-package") == 0) {
    if (argc != 4) { usage(argv[0]); return 1; }
    return cmd_unpack_package(argv[2], argv[3]);
  }
  if (strcmp(argv[1], "serve") == 0) {
    return ai_runtime_native_main(argc - 1, argv + 1);
  }
  if (strcmp(argv[1], "bootstrap") == 0) {
    if (argc < 4 || argc > 5) { usage(argv[0]); return 1; }
    if (cmd_rebuild_db(argv[3]) != 0) return 1;
    if (cmd_rebuild_core(argv[2], argv[3]) != 0) return 1;
    if (argc == 5 && strcmp(argv[4], "serve") == 0) {
      return ai_runtime_native_main(1, argv);
    }
    return 0;
  }
  if (strcmp(argv[1], "conformance") == 0) {
    if (argc < 3 || argc > 4) { usage(argv[0]); return 1; }
    uint32_t iters = 500u;
    if (argc == 4) {
      unsigned long v = strtoul(argv[3], NULL, 10);
      if (v > 0 && v <= 1000000u) iters = (uint32_t)v;
    }
    return cmd_conformance(argv[2], iters);
  }
  usage(argv[0]);
  return 1;
}
