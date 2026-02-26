#include <arpa/inet.h>
#include <ctype.h>
#include <errno.h>
#include <netinet/in.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#include "../native-core/aiir_core.h"
#include "../native-core/aiir_policy.h"
#include "../native-core/aiir_state.h"
#include "../native-core/aiir_drift.h"

#define A2A_SEC_CODE 1u
#define A2A_SEC_SLOT 2u
#define A2A_SEC_META 5u
#define A2A_SEC_CODE_INFO 8u

#define D2B_SEC_OPS 1u
#define D2B_SEC_SIG 2u

#define REQ_BUF_MAX_HARD (1024 * 1024)
#define RESP_BUF_MAX (1024 * 1024)

typedef struct {
  uint32_t file_id;
  uint32_t off;
  uint32_t len;
} Row3;

typedef struct {
  uint32_t op_id;
  uint32_t engine_id;
  uint32_t acl_id;
  uint32_t proc_id;
  uint32_t min_args;
  uint32_t max_args;
} DbOp;

typedef struct {
  uint32_t op_id;
  uint32_t arg_index;
  uint32_t type_id;
  uint32_t flags;
} DbSig;

typedef enum {
  JV_NULL = 0,
  JV_BOOL = 1,
  JV_NUMBER = 2,
  JV_STRING = 3,
} JsonType;

typedef struct {
  JsonType t;
  bool b;
  bool is_int;
  double num;
  long long i64;
  char *s;
} JsonVal;

typedef struct {
  AiirU32Buf lite_table;
  AiirU32Buf lite_blob;
  AiirU32Buf adapt_table;
  AiirU32Buf adapt_blob;
  AiirU32Buf db_packet;
  AiirPolicy policy;
  AiirState state;
  AiirDrift drift;

  DbOp *ops;
  size_t ops_count;
  DbSig *sigs;
  size_t sig_count;
} Runtime;

static bool json_escape_copy(const char *src, size_t src_len, char *dst, size_t dst_cap, size_t *dst_len) {
  size_t w = 0;
  for (size_t i = 0; i < src_len; i++) {
    unsigned char c = (unsigned char)src[i];
    const char *rep = NULL;
    char tmp[7];
    if (c == '\\') rep = "\\\\";
    else if (c == '"') rep = "\\\"";
    else if (c == '\n') rep = "\\n";
    else if (c == '\r') rep = "\\r";
    else if (c == '\t') rep = "\\t";
    else if (c < 0x20) {
      snprintf(tmp, sizeof(tmp), "\\u%04x", c);
      rep = tmp;
    }
    if (rep) {
      size_t rl = strlen(rep);
      if (w + rl >= dst_cap) return false;
      memcpy(dst + w, rep, rl);
      w += rl;
    } else {
      if (w + 1 >= dst_cap) return false;
      dst[w++] = (char)c;
    }
  }
  if (w >= dst_cap) return false;
  dst[w] = '\0';
  *dst_len = w;
  return true;
}

static bool find_header_end(const char *req, size_t n, size_t *header_end) {
  for (size_t i = 0; i + 3 < n; i++) {
    if (req[i] == '\r' && req[i + 1] == '\n' && req[i + 2] == '\r' && req[i + 3] == '\n') {
      *header_end = i + 4;
      return true;
    }
  }
  return false;
}

static bool parse_method_path(const char *req, char *method, size_t method_cap, char *path, size_t path_cap) {
  const char *sp1 = strchr(req, ' ');
  if (!sp1) return false;
  size_t mlen = (size_t)(sp1 - req);
  if (mlen == 0 || mlen + 1 > method_cap) return false;
  memcpy(method, req, mlen);
  method[mlen] = '\0';

  const char *sp2 = strchr(sp1 + 1, ' ');
  if (!sp2) return false;
  size_t plen = (size_t)(sp2 - (sp1 + 1));
  if (plen == 0 || plen + 1 > path_cap) return false;
  memcpy(path, sp1 + 1, plen);
  path[plen] = '\0';
  return true;
}

static long parse_content_length(const char *headers) {
  const char *p = headers;
  while (*p) {
    if ((p[0] == 'C' || p[0] == 'c') && strncasecmp(p, "Content-Length:", 15) == 0) {
      p += 15;
      while (*p == ' ' || *p == '\t') p++;
      return strtol(p, NULL, 10);
    }
    const char *nl = strstr(p, "\r\n");
    if (!nl) break;
    p = nl + 2;
  }
  return 0;
}

static const DbOp *find_op(const Runtime *rt, uint32_t op_id) {
  for (size_t i = 0; i < rt->ops_count; i++) {
    if (rt->ops[i].op_id == op_id) return &rt->ops[i];
  }
  return NULL;
}

static bool load_db_index(Runtime *rt) {
  AiirU32Buf *p = &rt->db_packet;
  if (p->len < 8 || p->words[0] != AIIR_D2B_MAGIC) return false;
  uint32_t sec_count = p->words[2];
  uint32_t toc_base = p->words[4];
  uint32_t total_words = p->words[6];
  if (total_words != p->len) return false;

  uint32_t *ops_words = NULL, *sig_words = NULL;
  uint32_t ops_len = 0, sig_len = 0;
  for (uint32_t i = 0; i < sec_count; i++) {
    uint32_t t = toc_base + i * 4u;
    if (t + 3u >= p->len) return false;
    uint32_t id = p->words[t];
    uint32_t off = p->words[t + 1u];
    uint32_t len = p->words[t + 2u];
    uint32_t rw = p->words[t + 3u];
    if (off + len > p->len || rw == 0 || (len % rw) != 0) return false;
    if (id == D2B_SEC_OPS) {
      ops_words = p->words + off;
      ops_len = len;
    } else if (id == D2B_SEC_SIG) {
      sig_words = p->words + off;
      sig_len = len;
    }
  }
  if (!ops_words || !sig_words || (ops_len % 6u) != 0 || (sig_len % 4u) != 0) return false;

  rt->ops_count = ops_len / 6u;
  rt->sig_count = sig_len / 4u;
  rt->ops = (DbOp *)calloc(rt->ops_count, sizeof(DbOp));
  rt->sigs = (DbSig *)calloc(rt->sig_count, sizeof(DbSig));
  if (!rt->ops || !rt->sigs) return false;

  for (size_t i = 0; i < rt->ops_count; i++) {
    size_t k = i * 6u;
    rt->ops[i].op_id = ops_words[k];
    rt->ops[i].engine_id = ops_words[k + 1u];
    rt->ops[i].acl_id = ops_words[k + 2u];
    rt->ops[i].proc_id = ops_words[k + 3u];
    rt->ops[i].min_args = ops_words[k + 4u];
    rt->ops[i].max_args = ops_words[k + 5u];
  }
  for (size_t i = 0; i < rt->sig_count; i++) {
    size_t k = i * 4u;
    rt->sigs[i].op_id = sig_words[k];
    rt->sigs[i].arg_index = sig_words[k + 1u];
    rt->sigs[i].type_id = sig_words[k + 2u];
    rt->sigs[i].flags = sig_words[k + 3u];
  }
  return true;
}

static bool load_runtime(const char *core_dir, Runtime *rt) {
  memset(rt, 0, sizeof(*rt));
  if (!aiir_load_u32_pref(core_dir, "m2m.ai2ai.lite.table", &rt->lite_table)) return false;
  if (!aiir_load_u32_pref(core_dir, "m2m.ai2ai.lite.blob", &rt->lite_blob)) return false;
  if (!aiir_load_u32_pref(core_dir, "m2m.ai2ai.source.adapt.table", &rt->adapt_table)) return false;
  if (!aiir_load_u32_pref(core_dir, "m2m.ai2ai.source.adapt.blob", &rt->adapt_blob)) return false;
  if (!aiir_load_u32_pref(core_dir, "m2m.db.packet", &rt->db_packet)) return false;

  if ((rt->lite_table.len % 3u) != 0u) return false;
  if ((rt->adapt_table.len % 3u) != 0u) return false;
  if (!load_db_index(rt)) return false;
  if (!aiir_policy_init_from_env(&rt->policy)) return false;
  const char *wal = getenv("AI_WAL_PATH");
  const char *snap = getenv("AI_SNAPSHOT_PATH");
  char meta[256];
  snprintf(meta, sizeof(meta), "{\"files\":%zu}", rt->lite_table.len / 3u);
  if (!aiir_state_init(&rt->state, wal, snap, meta)) return false;
  uint32_t check_every = 200u;
  const char *ce = getenv("AI_DRIFT_CHECK_EVERY");
  if (ce && *ce) {
    unsigned long v = strtoul(ce, NULL, 10);
    if (v > 0 && v <= 1000000u) check_every = (uint32_t)v;
  }
  if (!aiir_drift_init(&rt->drift, core_dir, check_every)) return false;
  return true;
}

static void free_runtime(Runtime *rt) {
  aiir_u32_free(&rt->lite_table);
  aiir_u32_free(&rt->lite_blob);
  aiir_u32_free(&rt->adapt_table);
  aiir_u32_free(&rt->adapt_blob);
  aiir_u32_free(&rt->db_packet);
  aiir_policy_free(&rt->policy);
  free(rt->ops);
  free(rt->sigs);
}

static int json_response(int fd, int code, const char *body) {
  const char *msg =
      (code == 200) ? "OK" :
      (code == 400) ? "Bad Request" :
      (code == 404) ? "Not Found" :
      (code == 429) ? "Too Many Requests" :
      (code == 503) ? "Service Unavailable" :
      "Error";
  char hdr[512];
  int bl = (int)strlen(body);
  int n = snprintf(hdr, sizeof(hdr),
                   "HTTP/1.1 %d %s\r\n"
                   "Content-Type: application/json; charset=utf-8\r\n"
                   "Cache-Control: no-store\r\n"
                   "Content-Length: %d\r\n"
                   "Connection: close\r\n\r\n",
                   code, msg, bl);
  if (n < 0) return -1;
  if (write(fd, hdr, (size_t)n) < 0) return -1;
  if (write(fd, body, (size_t)bl) < 0) return -1;
  return 0;
}

static bool get_packet_by_id(const Runtime *rt, uint32_t id, const uint32_t **pkt, uint32_t *pkt_len) {
  uint32_t files = (uint32_t)(rt->lite_table.len / 3u);
  if (id >= files) return false;
  uint32_t p = id * 3u;
  uint32_t off = rt->lite_table.words[p + 1u];
  uint32_t len = rt->lite_table.words[p + 2u];
  if ((uint64_t)off + (uint64_t)len > rt->lite_blob.len) return false;
  *pkt = rt->lite_blob.words + off;
  *pkt_len = len;
  return true;
}

static bool parse_a2a_summary(const uint32_t *w, uint32_t n, uint32_t *code_records, uint32_t *slot_records, uint32_t *meta_records) {
  if (n < 8u || w[0] != AIIR_A2A_MAGIC) return false;
  uint32_t sec_count = w[2];
  uint32_t toc_base = w[4];
  uint32_t total = w[6];
  if (total != n) return false;

  *code_records = 0;
  *slot_records = 0;
  *meta_records = 0;

  bool has_code = false;
  uint32_t code_info_off = 0, code_info_len = 0;

  for (uint32_t i = 0; i < sec_count; i++) {
    uint32_t t = toc_base + i * 4u;
    if (t + 3u >= n) return false;
    uint32_t id = w[t];
    uint32_t off = w[t + 1u];
    uint32_t len = w[t + 2u];
    uint32_t rw = w[t + 3u];
    if (off + len > n || rw == 0 || (len % rw) != 0) return false;
    if (id == A2A_SEC_CODE) {
      *code_records = len / 6u;
      has_code = true;
    } else if (id == A2A_SEC_SLOT) {
      *slot_records = len / 4u;
    } else if (id == A2A_SEC_META) {
      *meta_records = len / 4u;
    } else if (id == A2A_SEC_CODE_INFO) {
      code_info_off = off;
      code_info_len = len;
    }
  }

  if (!has_code && code_info_len >= 4u) {
    uint32_t raw_words = w[code_info_off + 1u];
    *code_records = raw_words / 6u;
  }

  return true;
}

static bool find_adapt(const Runtime *rt, uint32_t file_id, uint32_t *off, uint32_t *len) {
  for (size_t i = 0; i < rt->adapt_table.len; i += 3u) {
    if (rt->adapt_table.words[i] == file_id) {
      *off = rt->adapt_table.words[i + 1u];
      *len = rt->adapt_table.words[i + 2u];
      return true;
    }
  }
  return false;
}

static bool build_source_preview(const Runtime *rt, uint32_t file_id, char *out, size_t out_cap, uint32_t *fallback_len) {
  uint32_t off = 0, len = 0;
  *fallback_len = 0;
  if (!find_adapt(rt, file_id, &off, &len)) {
    out[0] = '\0';
    return true;
  }
  if ((uint64_t)off + (uint64_t)len > rt->adapt_blob.len) return false;
  *fallback_len = len;

  size_t raw_len = len < 4096u ? len : 4096u;
  char tmp[4097];
  for (size_t i = 0; i < raw_len; i++) {
    tmp[i] = (char)(rt->adapt_blob.words[off + i] & 0xffu);
  }
  tmp[raw_len] = '\0';
  size_t escaped_len = 0;
  return json_escape_copy(tmp, raw_len, out, out_cap, &escaped_len);
}

static bool parse_json_int(const char *s, const char *key, long long *out) {
  const char *p = strstr(s, key);
  if (!p) return false;
  p += strlen(key);
  while (*p && *p != ':') p++;
  if (*p != ':') return false;
  p++;
  while (*p == ' ' || *p == '\t') p++;
  char *end = NULL;
  long long v = strtoll(p, &end, 10);
  if (end == p) return false;
  *out = v;
  return true;
}

static const char *skip_ws(const char *p) {
  while (*p && isspace((unsigned char)*p)) p++;
  return p;
}

static bool parse_json_string(const char **pp, char **out_s) {
  const char *p = *pp;
  if (*p != '"') return false;
  p++;
  size_t cap = 128;
  size_t len = 0;
  char *buf = (char *)malloc(cap);
  if (!buf) return false;
  while (*p && *p != '"') {
    char c = *p++;
    if (c == '\\') {
      char e = *p++;
      if (!e) { free(buf); return false; }
      if (e == 'n') c = '\n';
      else if (e == 'r') c = '\r';
      else if (e == 't') c = '\t';
      else c = e;
    }
    if (len + 1 >= cap) {
      cap *= 2;
      char *nb = (char *)realloc(buf, cap);
      if (!nb) { free(buf); return false; }
      buf = nb;
    }
    buf[len++] = c;
  }
  if (*p != '"') { free(buf); return false; }
  p++;
  buf[len] = '\0';
  *out_s = buf;
  *pp = p;
  return true;
}

static bool parse_json_args(const char *body, JsonVal **out_vals, size_t *out_n) {
  const char *p = strstr(body, "\"args\"");
  if (!p) {
    *out_vals = NULL;
    *out_n = 0;
    return true;
  }
  p = strchr(p, ':');
  if (!p) return false;
  p++;
  p = skip_ws(p);
  if (*p != '[') return false;
  p++;

  size_t cap = 8;
  size_t n = 0;
  JsonVal *arr = (JsonVal *)calloc(cap, sizeof(JsonVal));
  if (!arr) return false;

  while (1) {
    p = skip_ws(p);
    if (*p == ']') { p++; break; }
    if (n >= cap) {
      cap *= 2;
      JsonVal *na = (JsonVal *)realloc(arr, cap * sizeof(JsonVal));
      if (!na) { free(arr); return false; }
      memset(na + n, 0, (cap - n) * sizeof(JsonVal));
      arr = na;
    }

    JsonVal v = {0};
    if (*p == '"') {
      v.t = JV_STRING;
      if (!parse_json_string(&p, &v.s)) { free(arr); return false; }
    } else if (strncmp(p, "true", 4) == 0) {
      v.t = JV_BOOL; v.b = true; p += 4;
    } else if (strncmp(p, "false", 5) == 0) {
      v.t = JV_BOOL; v.b = false; p += 5;
    } else if (strncmp(p, "null", 4) == 0) {
      v.t = JV_NULL; p += 4;
    } else {
      char *end = NULL;
      double d = strtod(p, &end);
      if (end == p) {
        for (size_t k = 0; k < n; k++) free(arr[k].s);
        free(arr);
        return false;
      }
      v.t = JV_NUMBER;
      v.num = d;
      long long iv = (long long)d;
      v.is_int = (d == (double)iv);
      v.i64 = iv;
      p = end;
    }

    arr[n++] = v;
    p = skip_ws(p);
    if (*p == ',') {
      p++;
      continue;
    }
    if (*p == ']') { p++; break; }
    for (size_t k = 0; k < n; k++) free(arr[k].s);
    free(arr);
    return false;
  }

  *out_vals = arr;
  *out_n = n;
  return true;
}

static bool type_check(uint32_t type_id, const JsonVal *v) {
  switch (type_id) {
    case 1: return v->t == JV_NUMBER && v->is_int; // I64
    case 2: return v->t == JV_NUMBER; // F64
    case 3: return v->t == JV_STRING; // TEXT
    case 4: return false; // BYTES unsupported in json transport
    case 5: return v->t == JV_BOOL; // BOOL
    case 6: return v->t == JV_NULL; // NIL
    default: return false;
  }
}

static uint32_t count_sig_for_op(const Runtime *rt, uint32_t op_id) {
  uint32_t c = 0;
  for (size_t i = 0; i < rt->sig_count; i++) if (rt->sigs[i].op_id == op_id) c++;
  return c;
}

static const DbSig *find_sig(const Runtime *rt, uint32_t op_id, uint32_t arg_index) {
  for (size_t i = 0; i < rt->sig_count; i++) {
    if (rt->sigs[i].op_id == op_id && rt->sigs[i].arg_index == arg_index) return &rt->sigs[i];
  }
  return NULL;
}

static size_t parse_env_size(const char *name, size_t defv, size_t minv, size_t maxv) {
  const char *s = getenv(name);
  if (!s || !*s) return defv;
  char *end = NULL;
  unsigned long long v = strtoull(s, &end, 10);
  if (end == s || *end != '\0') return defv;
  if (v < minv) return minv;
  if (v > maxv) return maxv;
  return (size_t)v;
}

static int handle_request(Runtime *rt, int cfd, const char *db_mode, size_t req_cap, size_t body_cap) {
  char *req = (char *)malloc(req_cap + 1);
  if (!req) return -1;
  ssize_t got = read(cfd, req, req_cap);
  if (got <= 0) { free(req); return -1; }
  req[got] = '\0';

  char method[16], path[2048];
  if (!parse_method_path(req, method, sizeof(method), path, sizeof(path))) {
    json_response(cfd, 400, "{\"ok\":0,\"err\":\"request\"}");
    free(req);
    return 0;
  }

  if (strcmp(method, "GET") == 0 && strcmp(path, "/health") == 0) {
    int wal_exists = access(rt->state.wal_path, F_OK) == 0 ? 1 : 0;
    int snap_exists = access(rt->state.snapshot_path, F_OK) == 0 ? 1 : 0;
    char body[4096];
    snprintf(body, sizeof(body),
             "{\"ok\":1,\"service\":\"ai-ir-runtime-native\",\"dbMode\":\"%.64s\","
             "\"driftCount\":%u,\"checks\":%u,\"policy\":{\"allowDbExec\":%s,\"allowAllOps\":%s},"
             "\"state\":{\"walPath\":\"%.384s\",\"walExists\":%d,\"snapshotPath\":\"%.384s\",\"snapshotExists\":%d}}",
             db_mode,
             rt->drift.drift_count,
             rt->drift.checks,
             rt->policy.allow_db_exec ? "true" : "false",
             rt->policy.allow_all_ops ? "true" : "false",
             rt->state.wal_path,
             wal_exists,
             rt->state.snapshot_path,
             snap_exists);
    json_response(cfd, 200, body);
    free(req);
    return 0;
  }

  if (strcmp(method, "GET") == 0 && strcmp(path, "/ai/meta") == 0) {
    uint32_t files = (uint32_t)(rt->lite_table.len / 3u);
    char body[512];
    snprintf(body, sizeof(body),
             "{\"files\":%u,\"liteBlobWords\":%zu,\"sourceAdaptRows\":%zu,\"sourceAdaptWords\":%zu,\"dbPacketWords\":%zu}",
             files, rt->lite_blob.len, rt->adapt_table.len / 3u, rt->adapt_blob.len, rt->db_packet.len);
    json_response(cfd, 200, body);
    free(req);
    return 0;
  }

  if (strcmp(method, "GET") == 0 && strncmp(path, "/ai/render/", 11) == 0) {
    char *end = NULL;
    long idl = strtol(path + 11, &end, 10);
    if (!end || *end != '\0' || idl < 0) {
      json_response(cfd, 400, "{\"ok\":0,\"err\":\"id\"}");
      free(req);
      return 0;
    }
    const uint32_t *pkt = NULL;
    uint32_t pkt_len = 0;
    if (!get_packet_by_id(rt, (uint32_t)idl, &pkt, &pkt_len)) {
      json_response(cfd, 404, "{\"ok\":0,\"err\":\"file-id\"}");
      free(req);
      return 0;
    }

    uint32_t cr = 0, sr = 0, mr = 0;
    if (!parse_a2a_summary(pkt, pkt_len, &cr, &sr, &mr)) {
      json_response(cfd, 400, "{\"ok\":0,\"err\":\"packet\"}");
      free(req);
      return 0;
    }

    char preview[4096];
    uint32_t fallback_len = 0;
    bool ok_preview = build_source_preview(rt, (uint32_t)idl, preview, sizeof(preview), &fallback_len);
    if (!ok_preview) {
      json_response(cfd, 400, "{\"ok\":0,\"err\":\"adapt\"}");
      free(req);
      return 0;
    }

    char body[RESP_BUF_MAX];
    snprintf(body, sizeof(body),
             "{\"ok\":1,\"render\":{\"fileId\":%ld,\"codeRecords\":%u,\"slotRecords\":%u,\"metaRecords\":%u,\"hasSourceFallback\":%s,\"sourceFallbackLen\":%u,\"sourcePreview\":\"%s\"}}",
             idl, cr, sr, mr, (fallback_len > 0 ? "true" : "false"), fallback_len, preview);
    json_response(cfd, 200, body);
    free(req);
    return 0;
  }

  if (strcmp(method, "POST") == 0 && strcmp(path, "/ai/db/exec") == 0) {
    if (!rt->policy.allow_db_exec) {
      json_response(cfd, 400, "{\"ok\":0,\"err\":\"policy-db-exec\"}");
      free(req);
      return 0;
    }
    size_t hdr_end = 0;
    if (!find_header_end(req, (size_t)got, &hdr_end)) {
      json_response(cfd, 400, "{\"ok\":0,\"err\":\"headers\"}");
      free(req);
      return 0;
    }
    long cl = parse_content_length(req);
    if (cl < 0 || cl > (long)body_cap) {
      json_response(cfd, 400, "{\"ok\":0,\"err\":\"content-length\"}");
      free(req);
      return 0;
    }

    const char *bodyp = req + hdr_end;
    long have = (long)got - (long)hdr_end;
    if (have < cl) {
      json_response(cfd, 400, "{\"ok\":0,\"err\":\"body-short\"}");
      free(req);
      return 0;
    }

    long long op_lli = 0;
    if (!parse_json_int(bodyp, "\"opId\"", &op_lli) || op_lli < 0 || op_lli > 0xffffffffLL) {
      json_response(cfd, 400, "{\"ok\":0,\"err\":\"opId\"}");
      free(req);
      return 0;
    }
    uint32_t op_id = (uint32_t)op_lli;
    if (!aiir_policy_allow_op(&rt->policy, op_id)) {
      json_response(cfd, 400, "{\"ok\":0,\"err\":\"policy-op\"}");
      free(req);
      return 0;
    }
    const DbOp *op = find_op(rt, op_id);
    if (!op) {
      json_response(cfd, 400, "{\"ok\":0,\"err\":\"op\"}");
      free(req);
      return 0;
    }

    JsonVal *args = NULL;
    size_t argc = 0;
    if (!parse_json_args(bodyp, &args, &argc)) {
      json_response(cfd, 400, "{\"ok\":0,\"err\":\"args\"}");
      free(req);
      return 0;
    }

    if (argc < op->min_args || argc > op->max_args) {
      for (size_t i = 0; i < argc; i++) free(args[i].s);
      free(args);
      json_response(cfd, 400, "{\"ok\":0,\"err\":\"argc\"}");
      free(req);
      return 0;
    }

    uint32_t sigc = count_sig_for_op(rt, op_id);
    if (sigc != argc) {
      for (size_t i = 0; i < argc; i++) free(args[i].s);
      free(args);
      json_response(cfd, 400, "{\"ok\":0,\"err\":\"sig-arity\"}");
      free(req);
      return 0;
    }

    for (size_t i = 0; i < argc; i++) {
      const DbSig *sg = find_sig(rt, op_id, (uint32_t)i);
      if (!sg || !type_check(sg->type_id, &args[i])) {
        for (size_t k = 0; k < argc; k++) free(args[k].s);
        free(args);
        json_response(cfd, 400, "{\"ok\":0,\"err\":\"type\"}");
        free(req);
        return 0;
      }
    }

    for (size_t i = 0; i < argc; i++) free(args[i].s);
    free(args);

    char body[512];
    snprintf(body, sizeof(body),
             "{\"ok\":1,\"result\":{\"ok\":1,\"mode\":\"dry-run\",\"opId\":%u,\"procId\":%u,\"argsCount\":%zu}}",
             op->op_id, op->proc_id, argc);
    aiir_state_log_dbexec(&rt->state, op->op_id, op->proc_id, argc);
    json_response(cfd, 200, body);
    free(req);
    return 0;
  }

  json_response(cfd, 404, "{\"ok\":0,\"err\":\"route\"}");
  free(req);
  return 0;
}

int ai_runtime_native_main(int argc, char **argv) {
  (void)argc;
  (void)argv;
  const char *core_dir = getenv("AI_CORE_DIR");
  if (!core_dir || !*core_dir) core_dir = "/var/www/aiir/ai/core";
  const char *host = getenv("AI_RUNTIME_HOST");
  if (!host || !*host) host = "127.0.0.1";
  const char *port_s = getenv("AI_RUNTIME_PORT");
  int port = port_s && *port_s ? atoi(port_s) : 7788;
  if (port <= 0 || port > 65535) port = 7788;
  const char *db_mode = getenv("AI_DB_EXEC_MODE");
  if (!db_mode || !*db_mode) db_mode = "dry-run";
  size_t req_cap = parse_env_size("AI_MAX_REQ_BYTES", 262144u, 4096u, REQ_BUF_MAX_HARD);
  size_t body_cap = parse_env_size("AI_MAX_BODY_BYTES", 65536u, 1024u, req_cap);
  size_t timeout_ms = parse_env_size("AI_IO_TIMEOUT_MS", 1500u, 100u, 60000u);
  size_t rate_limit_rps = parse_env_size("AI_RATE_LIMIT_RPS", 60u, 1u, 100000u);
  size_t cb_fail_threshold = parse_env_size("AI_CB_FAIL_THRESHOLD", 20u, 1u, 100000u);
  size_t cb_cooldown_sec = parse_env_size("AI_CB_COOLDOWN_SEC", 15u, 1u, 3600u);

  Runtime rt;
  if (!load_runtime(core_dir, &rt)) {
    fprintf(stderr, "load-runtime-failed\n");
    return 1;
  }

  int sfd = socket(AF_INET, SOCK_STREAM, 0);
  if (sfd < 0) {
    perror("socket");
    free_runtime(&rt);
    return 1;
  }

  int one = 1;
  setsockopt(sfd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

  struct sockaddr_in addr;
  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_port = htons((uint16_t)port);
  if (inet_pton(AF_INET, host, &addr.sin_addr) != 1) {
    fprintf(stderr, "bad-host\n");
    close(sfd);
    free_runtime(&rt);
    return 1;
  }

  if (bind(sfd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
    perror("bind");
    close(sfd);
    free_runtime(&rt);
    return 1;
  }
  if (listen(sfd, 64) != 0) {
    perror("listen");
    close(sfd);
    free_runtime(&rt);
    return 1;
  }

  printf("1 %s %d %zu\n", host, port, rt.lite_table.len / 3u);
  fflush(stdout);

  time_t rl_window = 0;
  size_t rl_count = 0;
  size_t consecutive_fail = 0;
  time_t cb_open_until = 0;

  while (1) {
    int cfd = accept(sfd, NULL, NULL);
    if (cfd < 0) {
      if (errno == EINTR) continue;
      perror("accept");
      break;
    }
    struct timeval tv;
    tv.tv_sec = (time_t)(timeout_ms / 1000u);
    tv.tv_usec = (suseconds_t)((timeout_ms % 1000u) * 1000u);
    (void)setsockopt(cfd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    (void)setsockopt(cfd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    time_t now = time(NULL);
    if (cb_open_until > now) {
      json_response(cfd, 503, "{\"ok\":0,\"err\":\"circuit-open\"}");
      close(cfd);
      continue;
    }
    if (rl_window != now) {
      rl_window = now;
      rl_count = 0;
    }
    if (rl_count >= rate_limit_rps) {
      json_response(cfd, 429, "{\"ok\":0,\"err\":\"rate-limit\"}");
      close(cfd);
      continue;
    }
    rl_count++;
    aiir_drift_tick(&rt.drift);
    int rc = handle_request(&rt, cfd, db_mode, req_cap, body_cap);
    if (rc < 0) {
      consecutive_fail++;
      if (consecutive_fail >= cb_fail_threshold) {
        cb_open_until = now + (time_t)cb_cooldown_sec;
        consecutive_fail = 0;
      }
    } else {
      consecutive_fail = 0;
    }
    close(cfd);
  }

  close(sfd);
  free_runtime(&rt);
  return 0;
}

#ifdef AI_RUNTIME_STANDALONE
int main(int argc, char **argv) {
  return ai_runtime_native_main(argc, argv);
}
#endif
