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
#define CAP_NONCE_RING_MAX 512u
#define CAP_NONCE_MAX_LEN 64u

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

  bool cap_required;
  char cap_secret[256];
  size_t cap_max_future_sec;
  char cap_nonce_ring[CAP_NONCE_RING_MAX][CAP_NONCE_MAX_LEN + 1u];
  size_t cap_nonce_count;
  size_t cap_nonce_next;
  char audit_path[384];
  FILE *audit_fp;

  uint64_t metric_requests_total;
  uint64_t metric_responses_2xx;
  uint64_t metric_responses_4xx;
  uint64_t metric_responses_5xx;
  uint64_t metric_rate_limited_total;
  uint64_t metric_circuit_open_total;
  uint64_t metric_db_exec_allow_total;
  uint64_t metric_db_exec_deny_total;
  uint64_t metric_capability_deny_total;
  bool log_requests;

  bool gateway_enable;
  bool gateway_human_indirect;
  bool gateway_require_capability;
  bool gateway_allow_direct_credentials;
  char gateway_projects_file[384];
  char gateway_db_provider[64];
  char gateway_db_default_profile[64];
  char gateway_db_region[64];
  size_t gateway_db_retention_days;
  uint64_t gateway_seq;
} Runtime;

static size_t parse_env_size(const char *name, size_t defv, size_t minv, size_t maxv);
static bool is_ascii_token(const char *s, size_t min_len, size_t max_len, const char *extra_allowed);
static bool is_known_contract_version(const char *v);
static bool is_known_create_intent(const char *intent);
static bool is_known_db_exec_intent(const char *intent);

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

static bool parse_env_bool(const char *name, bool defv) {
  const char *s = getenv(name);
  if (!s || !*s) return defv;
  if (strcmp(s, "1") == 0 || strcasecmp(s, "true") == 0 || strcasecmp(s, "yes") == 0 || strcasecmp(s, "on") == 0) return true;
  if (strcmp(s, "0") == 0 || strcasecmp(s, "false") == 0 || strcasecmp(s, "no") == 0 || strcasecmp(s, "off") == 0) return false;
  return defv;
}

static uint64_t now_ms(void) {
  struct timeval tv;
  gettimeofday(&tv, NULL);
  return (uint64_t)tv.tv_sec * 1000ULL + (uint64_t)(tv.tv_usec / 1000);
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

static bool get_header_value(const char *req, const char *name, char *out, size_t out_cap) {
  size_t name_len = strlen(name);
  const char *p = req;
  while (*p) {
    const char *line_end = strstr(p, "\r\n");
    if (!line_end) break;
    if (line_end == p) break;
    if (strncasecmp(p, name, name_len) == 0 && p[name_len] == ':') {
      const char *v = p + name_len + 1;
      while (v < line_end && (*v == ' ' || *v == '\t')) v++;
      size_t n = (size_t)(line_end - v);
      if (n + 1u > out_cap) return false;
      memcpy(out, v, n);
      out[n] = '\0';
      return true;
    }
    p = line_end + 2;
  }
  return false;
}

static bool is_valid_nonce(const char *nonce) {
  size_t n = strlen(nonce);
  if (n < 8u || n > CAP_NONCE_MAX_LEN) return false;
  for (size_t i = 0; i < n; i++) {
    char c = nonce[i];
    if (!(isalnum((unsigned char)c) || c == '-' || c == '_' || c == '.')) return false;
  }
  return true;
}

static bool cap_nonce_seen(const Runtime *rt, const char *nonce) {
  for (size_t i = 0; i < rt->cap_nonce_count; i++) {
    if (strcmp(rt->cap_nonce_ring[i], nonce) == 0) return true;
  }
  return false;
}

static void cap_nonce_add(Runtime *rt, const char *nonce) {
  size_t n = strlen(nonce);
  if (n > CAP_NONCE_MAX_LEN) n = CAP_NONCE_MAX_LEN;
  memcpy(rt->cap_nonce_ring[rt->cap_nonce_next], nonce, n);
  rt->cap_nonce_ring[rt->cap_nonce_next][n] = '\0';
  rt->cap_nonce_next = (rt->cap_nonce_next + 1u) % CAP_NONCE_RING_MAX;
  if (rt->cap_nonce_count < CAP_NONCE_RING_MAX) rt->cap_nonce_count++;
}

typedef struct {
  uint32_t s[8];
  uint64_t bits;
  uint8_t buf[64];
  size_t len;
} Sha256Ctx;

static const uint32_t k256[64] = {
  0x428a2f98u,0x71374491u,0xb5c0fbcfu,0xe9b5dba5u,0x3956c25bu,0x59f111f1u,0x923f82a4u,0xab1c5ed5u,
  0xd807aa98u,0x12835b01u,0x243185beu,0x550c7dc3u,0x72be5d74u,0x80deb1feu,0x9bdc06a7u,0xc19bf174u,
  0xe49b69c1u,0xefbe4786u,0x0fc19dc6u,0x240ca1ccu,0x2de92c6fu,0x4a7484aau,0x5cb0a9dcu,0x76f988dau,
  0x983e5152u,0xa831c66du,0xb00327c8u,0xbf597fc7u,0xc6e00bf3u,0xd5a79147u,0x06ca6351u,0x14292967u,
  0x27b70a85u,0x2e1b2138u,0x4d2c6dfcu,0x53380d13u,0x650a7354u,0x766a0abbu,0x81c2c92eu,0x92722c85u,
  0xa2bfe8a1u,0xa81a664bu,0xc24b8b70u,0xc76c51a3u,0xd192e819u,0xd6990624u,0xf40e3585u,0x106aa070u,
  0x19a4c116u,0x1e376c08u,0x2748774cu,0x34b0bcb5u,0x391c0cb3u,0x4ed8aa4au,0x5b9cca4fu,0x682e6ff3u,
  0x748f82eeu,0x78a5636fu,0x84c87814u,0x8cc70208u,0x90befffau,0xa4506cebu,0xbef9a3f7u,0xc67178f2u
};

static uint32_t ror32(uint32_t x, uint32_t n) { return (x >> n) | (x << (32u - n)); }

static void sha256_block(Sha256Ctx *c, const uint8_t b[64]) {
  uint32_t w[64];
  for (uint32_t i = 0; i < 16; i++) {
    uint32_t j = i * 4u;
    w[i] = ((uint32_t)b[j] << 24) | ((uint32_t)b[j + 1u] << 16) | ((uint32_t)b[j + 2u] << 8) | (uint32_t)b[j + 3u];
  }
  for (uint32_t i = 16; i < 64; i++) {
    uint32_t s0 = ror32(w[i - 15u], 7u) ^ ror32(w[i - 15u], 18u) ^ (w[i - 15u] >> 3u);
    uint32_t s1 = ror32(w[i - 2u], 17u) ^ ror32(w[i - 2u], 19u) ^ (w[i - 2u] >> 10u);
    w[i] = w[i - 16u] + s0 + w[i - 7u] + s1;
  }
  uint32_t a = c->s[0], b0 = c->s[1], c0 = c->s[2], d = c->s[3], e = c->s[4], f = c->s[5], g = c->s[6], h = c->s[7];
  for (uint32_t i = 0; i < 64; i++) {
    uint32_t S1 = ror32(e, 6u) ^ ror32(e, 11u) ^ ror32(e, 25u);
    uint32_t ch = (e & f) ^ ((~e) & g);
    uint32_t t1 = h + S1 + ch + k256[i] + w[i];
    uint32_t S0 = ror32(a, 2u) ^ ror32(a, 13u) ^ ror32(a, 22u);
    uint32_t maj = (a & b0) ^ (a & c0) ^ (b0 & c0);
    uint32_t t2 = S0 + maj;
    h = g; g = f; f = e; e = d + t1; d = c0; c0 = b0; b0 = a; a = t1 + t2;
  }
  c->s[0] += a; c->s[1] += b0; c->s[2] += c0; c->s[3] += d;
  c->s[4] += e; c->s[5] += f; c->s[6] += g; c->s[7] += h;
}

static void sha256_init(Sha256Ctx *c) {
  c->s[0] = 0x6a09e667u; c->s[1] = 0xbb67ae85u; c->s[2] = 0x3c6ef372u; c->s[3] = 0xa54ff53au;
  c->s[4] = 0x510e527fu; c->s[5] = 0x9b05688cu; c->s[6] = 0x1f83d9abu; c->s[7] = 0x5be0cd19u;
  c->bits = 0;
  c->len = 0;
}

static void sha256_update(Sha256Ctx *c, const uint8_t *p, size_t n) {
  while (n > 0) {
    size_t take = 64u - c->len;
    if (take > n) take = n;
    memcpy(c->buf + c->len, p, take);
    c->len += take;
    p += take;
    n -= take;
    if (c->len == 64u) {
      sha256_block(c, c->buf);
      c->bits += 512u;
      c->len = 0;
    }
  }
}

static void sha256_final(Sha256Ctx *c, uint8_t out[32]) {
  c->bits += (uint64_t)c->len * 8u;
  c->buf[c->len++] = 0x80u;
  if (c->len > 56u) {
    while (c->len < 64u) c->buf[c->len++] = 0u;
    sha256_block(c, c->buf);
    c->len = 0u;
  }
  while (c->len < 56u) c->buf[c->len++] = 0u;
  for (int i = 7; i >= 0; i--) {
    c->buf[c->len++] = (uint8_t)((c->bits >> (i * 8)) & 0xffu);
  }
  sha256_block(c, c->buf);
  for (uint32_t i = 0; i < 8u; i++) {
    out[i * 4u] = (uint8_t)(c->s[i] >> 24);
    out[i * 4u + 1u] = (uint8_t)(c->s[i] >> 16);
    out[i * 4u + 2u] = (uint8_t)(c->s[i] >> 8);
    out[i * 4u + 3u] = (uint8_t)(c->s[i]);
  }
}

static void hmac_sha256(const uint8_t *key, size_t key_len, const uint8_t *msg, size_t msg_len, uint8_t out[32]) {
  uint8_t k0[64], kipad[64], kopad[64], tmp[32];
  memset(k0, 0, sizeof(k0));
  if (key_len > 64u) {
    Sha256Ctx c;
    sha256_init(&c);
    sha256_update(&c, key, key_len);
    sha256_final(&c, k0);
  } else {
    memcpy(k0, key, key_len);
  }
  for (size_t i = 0; i < 64u; i++) {
    kipad[i] = (uint8_t)(k0[i] ^ 0x36u);
    kopad[i] = (uint8_t)(k0[i] ^ 0x5cu);
  }
  Sha256Ctx c1;
  sha256_init(&c1);
  sha256_update(&c1, kipad, sizeof(kipad));
  sha256_update(&c1, msg, msg_len);
  sha256_final(&c1, tmp);

  Sha256Ctx c2;
  sha256_init(&c2);
  sha256_update(&c2, kopad, sizeof(kopad));
  sha256_update(&c2, tmp, sizeof(tmp));
  sha256_final(&c2, out);
}

static void cap_sig_hex(const Runtime *rt, uint32_t op_id, long long exp_ts, const char *nonce, char out_hex[65]) {
  char msg[512];
  int n = snprintf(msg, sizeof(msg), "%u|%lld|%s", op_id, exp_ts, nonce);
  if (n < 0) n = 0;
  if ((size_t)n >= sizeof(msg)) n = (int)(sizeof(msg) - 1u);
  uint8_t mac[32];
  hmac_sha256((const uint8_t *)rt->cap_secret, strlen(rt->cap_secret), (const uint8_t *)msg, (size_t)n, mac);
  static const char *hex = "0123456789abcdef";
  for (size_t i = 0; i < 32u; i++) {
    out_hex[i * 2u] = hex[(mac[i] >> 4) & 0x0fu];
    out_hex[i * 2u + 1u] = hex[mac[i] & 0x0fu];
  }
  out_hex[64] = '\0';
}

static bool constant_time_eq_hex(const char *a, const char *b) {
  size_t la = strlen(a), lb = strlen(b);
  if (la != lb) return false;
  unsigned char diff = 0;
  for (size_t i = 0; i < la; i++) {
    unsigned char ca = (unsigned char)tolower((unsigned char)a[i]);
    unsigned char cb = (unsigned char)tolower((unsigned char)b[i]);
    diff |= (unsigned char)(ca ^ cb);
  }
  return diff == 0;
}

static void audit_log(Runtime *rt, const char *peer, const char *method, const char *path, int status, const char *event, uint32_t op_id, const char *reason) {
  char ts[32];
  time_t now = time(NULL);
  struct tm tmv;
  memset(&tmv, 0, sizeof(tmv));
  struct tm *ptm = gmtime(&now);
  if (ptm) tmv = *ptm;
  strftime(ts, sizeof(ts), "%Y-%m-%dT%H:%M:%SZ", &tmv);

  char peer_e[256], method_e[64], path_e[512], event_e[96], reason_e[192];
  size_t out_len = 0;
  (void)json_escape_copy(peer ? peer : "-", strlen(peer ? peer : "-"), peer_e, sizeof(peer_e), &out_len);
  (void)json_escape_copy(method ? method : "-", strlen(method ? method : "-"), method_e, sizeof(method_e), &out_len);
  (void)json_escape_copy(path ? path : "-", strlen(path ? path : "-"), path_e, sizeof(path_e), &out_len);
  (void)json_escape_copy(event ? event : "-", strlen(event ? event : "-"), event_e, sizeof(event_e), &out_len);
  (void)json_escape_copy(reason ? reason : "-", strlen(reason ? reason : "-"), reason_e, sizeof(reason_e), &out_len);

  char line[1400];
  snprintf(line, sizeof(line),
           "{\"ts\":\"%s\",\"event\":\"%s\",\"status\":%d,\"peer\":\"%s\",\"method\":\"%s\",\"path\":\"%s\",\"opId\":%u,\"reason\":\"%s\"}",
           ts, event_e, status, peer_e, method_e, path_e, op_id, reason_e);

  fprintf(stderr, "%s\n", line);
  if (rt->audit_fp) {
    fprintf(rt->audit_fp, "%s\n", line);
    fflush(rt->audit_fp);
  }
}

static void request_log(Runtime *rt, const char *peer, const char *method, const char *path, int status, const char *reason, uint64_t start_ms) {
  if (!rt->log_requests) return;
  uint64_t elapsed_ms = 0;
  uint64_t n = now_ms();
  if (n >= start_ms) elapsed_ms = n - start_ms;
  char msg[64];
  snprintf(msg, sizeof(msg), "request-latency-ms=%llu", (unsigned long long)elapsed_ms);
  audit_log(rt, peer, method, path, status, "request", 0u, reason ? reason : msg);
}

static bool validate_capability(Runtime *rt, const char *req, uint32_t op_id, char *deny_reason, size_t deny_reason_cap) {
  if (!rt->cap_required) return true;
  char h_op[64], h_exp[64], h_nonce[128], h_sig[128];
  if (!get_header_value(req, "X-AIIR-Cap-Op", h_op, sizeof(h_op)) ||
      !get_header_value(req, "X-AIIR-Cap-Exp", h_exp, sizeof(h_exp)) ||
      !get_header_value(req, "X-AIIR-Cap-Nonce", h_nonce, sizeof(h_nonce)) ||
      !get_header_value(req, "X-AIIR-Cap-Sig", h_sig, sizeof(h_sig))) {
    snprintf(deny_reason, deny_reason_cap, "cap-missing");
    return false;
  }

  char *end = NULL;
  unsigned long op_hdr = strtoul(h_op, &end, 10);
  if (end == h_op || *end != '\0' || op_hdr > 0xffffffffu || (uint32_t)op_hdr != op_id) {
    snprintf(deny_reason, deny_reason_cap, "cap-op");
    return false;
  }

  long long exp_ts = strtoll(h_exp, &end, 10);
  if (end == h_exp || *end != '\0' || exp_ts <= 0) {
    snprintf(deny_reason, deny_reason_cap, "cap-exp");
    return false;
  }
  time_t now = time(NULL);
  if (exp_ts < (long long)now) {
    snprintf(deny_reason, deny_reason_cap, "cap-expired");
    return false;
  }
  if ((long long)(exp_ts - (long long)now) > (long long)rt->cap_max_future_sec) {
    snprintf(deny_reason, deny_reason_cap, "cap-future");
    return false;
  }

  if (!is_valid_nonce(h_nonce)) {
    snprintf(deny_reason, deny_reason_cap, "cap-nonce");
    return false;
  }
  if (cap_nonce_seen(rt, h_nonce)) {
    snprintf(deny_reason, deny_reason_cap, "cap-replay");
    return false;
  }

  char expected_sig[65];
  cap_sig_hex(rt, op_id, exp_ts, h_nonce, expected_sig);
  if (!constant_time_eq_hex(h_sig, expected_sig)) {
    snprintf(deny_reason, deny_reason_cap, "cap-sig");
    return false;
  }

  cap_nonce_add(rt, h_nonce);
  return true;
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

  rt->cap_required = parse_env_bool("AI_CAP_REQUIRE", false);
  const char *cap_secret = getenv("AI_CAP_SECRET");
  if (cap_secret && *cap_secret) {
    strncpy(rt->cap_secret, cap_secret, sizeof(rt->cap_secret) - 1u);
    rt->cap_secret[sizeof(rt->cap_secret) - 1u] = '\0';
  } else {
    rt->cap_secret[0] = '\0';
  }
  if (rt->cap_required && rt->cap_secret[0] == '\0') return false;
  rt->cap_max_future_sec = parse_env_size("AI_CAP_MAX_FUTURE_SEC", 120u, 1u, 86400u);

  const char *audit_path = getenv("AI_AUDIT_LOG_PATH");
  if (!audit_path || !*audit_path) audit_path = "/var/www/aiir/ai/log/runtime_audit.log";
  strncpy(rt->audit_path, audit_path, sizeof(rt->audit_path) - 1u);
  rt->audit_path[sizeof(rt->audit_path) - 1u] = '\0';
  rt->audit_fp = fopen(rt->audit_path, "a");
  rt->log_requests = parse_env_bool("AI_LOG_REQUESTS", true);

  rt->gateway_enable = parse_env_bool("AIIR_GATEWAY_ENABLE", false);
  const char *hm = getenv("AIIR_HUMAN_DB_MODE");
  rt->gateway_human_indirect = (!hm || !*hm || strcasecmp(hm, "indirect") == 0);
  rt->gateway_require_capability = parse_env_bool("AIIR_DB_REQUIRE_CAPABILITY", true);
  rt->gateway_allow_direct_credentials = parse_env_bool("AIIR_DB_ALLOW_DIRECT_CREDENTIALS", false);

  const char *pf = getenv("AIIR_PROJECTS_FILE");
  if (!pf || !*pf) pf = "/var/www/aiir/ai/state/projects.ndjson";
  strncpy(rt->gateway_projects_file, pf, sizeof(rt->gateway_projects_file) - 1u);
  rt->gateway_projects_file[sizeof(rt->gateway_projects_file) - 1u] = '\0';

  const char *prov = getenv("AIIR_DB_PROVIDER");
  if (!prov || !*prov) prov = "default";
  strncpy(rt->gateway_db_provider, prov, sizeof(rt->gateway_db_provider) - 1u);
  rt->gateway_db_provider[sizeof(rt->gateway_db_provider) - 1u] = '\0';

  const char *profile = getenv("AIIR_DB_DEFAULT_PROFILE");
  if (!profile || !*profile) profile = "default";
  strncpy(rt->gateway_db_default_profile, profile, sizeof(rt->gateway_db_default_profile) - 1u);
  rt->gateway_db_default_profile[sizeof(rt->gateway_db_default_profile) - 1u] = '\0';

  const char *region = getenv("AIIR_DB_REGION");
  if (!region || !*region) region = "local";
  strncpy(rt->gateway_db_region, region, sizeof(rt->gateway_db_region) - 1u);
  rt->gateway_db_region[sizeof(rt->gateway_db_region) - 1u] = '\0';
  rt->gateway_db_retention_days = parse_env_size("AIIR_DB_RETENTION_DAYS", 30u, 1u, 3650u);

  if (!is_ascii_token(rt->gateway_db_provider, 1u, 63u, "._-")) return false;
  if (!is_ascii_token(rt->gateway_db_default_profile, 1u, 63u, "._-")) return false;
  if (!is_ascii_token(rt->gateway_db_region, 1u, 63u, "._-")) return false;
  if (rt->gateway_enable) {
    FILE *pfp = fopen(rt->gateway_projects_file, "a");
    if (!pfp) return false;
    fclose(pfp);
  }
  return true;
}

static void free_runtime(Runtime *rt) {
  aiir_u32_free(&rt->lite_table);
  aiir_u32_free(&rt->lite_blob);
  aiir_u32_free(&rt->adapt_table);
  aiir_u32_free(&rt->adapt_blob);
  aiir_u32_free(&rt->db_packet);
  aiir_policy_free(&rt->policy);
  if (rt->audit_fp) fclose(rt->audit_fp);
  free(rt->ops);
  free(rt->sigs);
}

static int json_response(int fd, int code, const char *body) {
  const char *msg =
      (code == 200) ? "OK" :
      (code == 202) ? "Accepted" :
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

static void metric_track_status(Runtime *rt, int code) {
  if (code >= 200 && code < 300) rt->metric_responses_2xx++;
  else if (code >= 400 && code < 500) rt->metric_responses_4xx++;
  else if (code >= 500 && code < 600) rt->metric_responses_5xx++;
}

static int json_response_tr(Runtime *rt, int fd, int code, const char *body) {
  metric_track_status(rt, code);
  return json_response(fd, code, body);
}

static int text_response_tr(Runtime *rt, int fd, int code, const char *body) {
  metric_track_status(rt, code);
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
                   "Content-Type: text/plain; version=0.0.4; charset=utf-8\r\n"
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

static const char *skip_ws(const char *p);
static bool parse_json_string(const char **pp, char **out_s);

static bool parse_json_string_key(const char *s, const char *key, char *out, size_t out_cap) {
  const char *p = strstr(s, key);
  if (!p) return false;
  p += strlen(key);
  while (*p && *p != ':') p++;
  if (*p != ':') return false;
  p++;
  p = skip_ws(p);
  char *tmp = NULL;
  if (!parse_json_string(&p, &tmp) || !tmp) return false;
  size_t n = strlen(tmp);
  if (n + 1u > out_cap) {
    free(tmp);
    return false;
  }
  memcpy(out, tmp, n + 1u);
  free(tmp);
  return true;
}

static bool is_ascii_token(const char *s, size_t min_len, size_t max_len, const char *extra_allowed) {
  if (!s) return false;
  size_t n = strlen(s);
  if (n < min_len || n > max_len) return false;
  for (size_t i = 0; i < n; i++) {
    unsigned char c = (unsigned char)s[i];
    if (isalnum(c)) continue;
    if (strchr(extra_allowed, (int)c) != NULL) continue;
    return false;
  }
  return true;
}

static bool is_known_contract_version(const char *v) {
  return strcmp(v, "hal.v1") == 0;
}

static bool is_known_create_intent(const char *intent) {
  return strcmp(intent, "create_project") == 0 || strcmp(intent, "create_project_typed") == 0;
}

static bool is_known_db_exec_intent(const char *intent) {
  return strcmp(intent, "save_data") == 0 || strcmp(intent, "read_data") == 0;
}

static void gen_ref(char *out, size_t out_cap, const char *prefix, Runtime *rt) {
  uint64_t t = (uint64_t)time(NULL);
  rt->gateway_seq++;
  snprintf(out, out_cap, "%s_%llx%llx", prefix, (unsigned long long)t, (unsigned long long)rt->gateway_seq);
}

static bool gateway_find_project_by_idempotency(Runtime *rt, const char *idempotency_key,
                                                char *project_ref, size_t project_ref_cap,
                                                char *db_ref, size_t db_ref_cap) {
  if (!idempotency_key || !*idempotency_key) return false;
  FILE *fp = fopen(rt->gateway_projects_file, "r");
  if (!fp) return false;
  char line[4096];
  bool ok = false;
  while (fgets(line, sizeof(line), fp)) {
    char idem[128];
    if (!parse_json_string_key(line, "\"idempotency_key\"", idem, sizeof(idem))) continue;
    if (strcmp(idem, idempotency_key) != 0) continue;
    if (!parse_json_string_key(line, "\"project_ref\"", project_ref, project_ref_cap)) continue;
    if (!parse_json_string_key(line, "\"db_ref\"", db_ref, db_ref_cap)) continue;
    ok = true;
    break;
  }
  fclose(fp);
  return ok;
}

static bool gateway_store_project(Runtime *rt, const char *project_ref, const char *db_ref, const char *project_name,
                                  const char *db_profile, const char *region, size_t retention_days, const char *idempotency_key,
                                  const char *contract_version, const char *intent) {
  FILE *fp = fopen(rt->gateway_projects_file, "a");
  if (!fp) return false;
  fprintf(fp,
          "{\"ts\":%llu,\"project_ref\":\"%s\",\"db_ref\":\"%s\",\"project_name\":\"%s\",\"db_profile\":\"%s\",\"region\":\"%s\",\"retention_days\":%zu,\"idempotency_key\":\"%s\",\"contract_version\":\"%s\",\"intent\":\"%s\"}\n",
          (unsigned long long)time(NULL), project_ref, db_ref, project_name, db_profile, region, retention_days,
          idempotency_key ? idempotency_key : "",
          contract_version ? contract_version : "hal.v1",
          intent ? intent : "create_project");
  fclose(fp);
  return true;
}

static bool gateway_project_db_exists(Runtime *rt, const char *project_ref, const char *db_ref) {
  FILE *fp = fopen(rt->gateway_projects_file, "r");
  if (!fp) return false;
  char pr[160], dr[160], line[2048];
  snprintf(pr, sizeof(pr), "\"project_ref\":\"%s\"", project_ref);
  snprintf(dr, sizeof(dr), "\"db_ref\":\"%s\"", db_ref);
  bool ok = false;
  while (fgets(line, sizeof(line), fp)) {
    if (strstr(line, pr) && strstr(line, dr)) {
      ok = true;
      break;
    }
  }
  fclose(fp);
  return ok;
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

static int handle_request(Runtime *rt, int cfd, const char *peer, const char *db_mode, size_t req_cap, size_t body_cap) {
  uint64_t start_ms = now_ms();
  char *req = (char *)malloc(req_cap + 1);
  if (!req) return -1;
  ssize_t got = read(cfd, req, req_cap);
  if (got <= 0) { free(req); return -1; }
  req[got] = '\0';
  rt->metric_requests_total++;

  char method[16], path[2048];
  if (!parse_method_path(req, method, sizeof(method), path, sizeof(path))) {
    json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"request\"}");
    audit_log(rt, peer, "-", "-", 400, "request-parse", 0u, "request");
    request_log(rt, peer, "-", "-", 400, "request-parse", start_ms);
    free(req);
    return 0;
  }

  if (strcmp(method, "GET") == 0 && strcmp(path, "/metrics") == 0) {
    char body[2048];
    int n = snprintf(body, sizeof(body),
                     "# TYPE aiir_runtime_requests_total counter\n"
                     "aiir_runtime_requests_total %llu\n"
                     "# TYPE aiir_runtime_responses_2xx_total counter\n"
                     "aiir_runtime_responses_2xx_total %llu\n"
                     "# TYPE aiir_runtime_responses_4xx_total counter\n"
                     "aiir_runtime_responses_4xx_total %llu\n"
                     "# TYPE aiir_runtime_responses_5xx_total counter\n"
                     "aiir_runtime_responses_5xx_total %llu\n"
                     "# TYPE aiir_runtime_rate_limited_total counter\n"
                     "aiir_runtime_rate_limited_total %llu\n"
                     "# TYPE aiir_runtime_circuit_open_total counter\n"
                     "aiir_runtime_circuit_open_total %llu\n"
                     "# TYPE aiir_runtime_db_exec_allow_total counter\n"
                     "aiir_runtime_db_exec_allow_total %llu\n"
                     "# TYPE aiir_runtime_db_exec_deny_total counter\n"
                     "aiir_runtime_db_exec_deny_total %llu\n"
                     "# TYPE aiir_runtime_capability_deny_total counter\n"
                     "aiir_runtime_capability_deny_total %llu\n",
                     (unsigned long long)rt->metric_requests_total,
                     (unsigned long long)rt->metric_responses_2xx,
                     (unsigned long long)rt->metric_responses_4xx,
                     (unsigned long long)rt->metric_responses_5xx,
                     (unsigned long long)rt->metric_rate_limited_total,
                     (unsigned long long)rt->metric_circuit_open_total,
                     (unsigned long long)rt->metric_db_exec_allow_total,
                     (unsigned long long)rt->metric_db_exec_deny_total,
                     (unsigned long long)rt->metric_capability_deny_total);
    if (n < 0) n = 0;
    if ((size_t)n >= sizeof(body)) n = (int)(sizeof(body) - 1u);
    body[n] = '\0';
    text_response_tr(rt, cfd, 200, body);
    request_log(rt, peer, method, path, 200, "metrics", start_ms);
    free(req);
    return 0;
  }

  if (strcmp(method, "GET") == 0 && strcmp(path, "/openapi.json") == 0) {
    const char *body =
      "{\"openapi\":\"3.0.3\",\"info\":{\"title\":\"AIIR Runtime API\",\"version\":\"1.0.0\"},"
      "\"paths\":{"
      "\"/health\":{\"get\":{\"responses\":{\"200\":{\"description\":\"Runtime health\"}}}},"
      "\"/metrics\":{\"get\":{\"responses\":{\"200\":{\"description\":\"Prometheus metrics\"}}}},"
      "\"/openapi.json\":{\"get\":{\"responses\":{\"200\":{\"description\":\"OpenAPI document\"}}}},"
      "\"/ai/meta\":{\"get\":{\"responses\":{\"200\":{\"description\":\"Core metadata\"}}}},"
      "\"/aiir/project/create\":{\"post\":{\"responses\":{\"202\":{\"description\":\"Project accepted and DB provisioning started\"}}}},"
      "\"/aiir/db/exec\":{\"post\":{\"responses\":{\"200\":{\"description\":\"AI-managed DB operation accepted\"}}}},"
      "\"/ai/render/{id}\":{\"get\":{\"parameters\":[{\"name\":\"id\",\"in\":\"path\",\"required\":true,\"schema\":{\"type\":\"integer\"}}],\"responses\":{\"200\":{\"description\":\"Render packet summary\"}}}},"
      "\"/ai/db/exec\":{\"post\":{\"requestBody\":{\"required\":true,\"content\":{\"application/json\":{\"schema\":{\"type\":\"object\",\"required\":[\"opId\"],\"properties\":{\"opId\":{\"type\":\"integer\",\"minimum\":0},\"args\":{\"type\":\"array\"}}}}}},"
      "\"parameters\":[{\"name\":\"X-AIIR-Cap-Op\",\"in\":\"header\",\"required\":false,\"schema\":{\"type\":\"string\"}},{\"name\":\"X-AIIR-Cap-Exp\",\"in\":\"header\",\"required\":false,\"schema\":{\"type\":\"string\"}},{\"name\":\"X-AIIR-Cap-Nonce\",\"in\":\"header\",\"required\":false,\"schema\":{\"type\":\"string\"}},{\"name\":\"X-AIIR-Cap-Sig\",\"in\":\"header\",\"required\":false,\"schema\":{\"type\":\"string\"}}],"
      "\"responses\":{\"200\":{\"description\":\"DB exec accepted\"},\"400\":{\"description\":\"Policy or capability denied\"}}}}}}";
    json_response_tr(rt, cfd, 200, body);
    request_log(rt, peer, method, path, 200, "openapi", start_ms);
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
             "\"capability\":{\"required\":%s,\"maxFutureSec\":%zu},"
             "\"gateway\":{\"enabled\":%s,\"humanIndirect\":%s},"
             "\"metrics\":{\"requestsTotal\":%llu,\"responses2xx\":%llu,\"responses4xx\":%llu,\"responses5xx\":%llu},"
             "\"audit\":{\"path\":\"%.256s\"},"
             "\"state\":{\"walPath\":\"%.384s\",\"walExists\":%d,\"snapshotPath\":\"%.384s\",\"snapshotExists\":%d}}",
             db_mode,
             rt->drift.drift_count,
             rt->drift.checks,
             rt->policy.allow_db_exec ? "true" : "false",
             rt->policy.allow_all_ops ? "true" : "false",
             rt->cap_required ? "true" : "false",
             rt->cap_max_future_sec,
             rt->gateway_enable ? "true" : "false",
             rt->gateway_human_indirect ? "true" : "false",
             (unsigned long long)rt->metric_requests_total,
             (unsigned long long)rt->metric_responses_2xx,
             (unsigned long long)rt->metric_responses_4xx,
             (unsigned long long)rt->metric_responses_5xx,
             rt->audit_path,
             rt->state.wal_path,
             wal_exists,
             rt->state.snapshot_path,
             snap_exists);
    json_response_tr(rt, cfd, 200, body);
    request_log(rt, peer, method, path, 200, "health", start_ms);
    free(req);
    return 0;
  }

  if (strcmp(method, "GET") == 0 && strcmp(path, "/ai/meta") == 0) {
    uint32_t files = (uint32_t)(rt->lite_table.len / 3u);
    char body[512];
    snprintf(body, sizeof(body),
             "{\"files\":%u,\"liteBlobWords\":%zu,\"sourceAdaptRows\":%zu,\"sourceAdaptWords\":%zu,\"dbPacketWords\":%zu}",
             files, rt->lite_blob.len, rt->adapt_table.len / 3u, rt->adapt_blob.len, rt->db_packet.len);
    json_response_tr(rt, cfd, 200, body);
    request_log(rt, peer, method, path, 200, "meta", start_ms);
    free(req);
    return 0;
  }

  if (strcmp(method, "GET") == 0 && strncmp(path, "/ai/render/", 11) == 0) {
    char *end = NULL;
    long idl = strtol(path + 11, &end, 10);
    if (!end || *end != '\0' || idl < 0) {
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"id\"}");
      request_log(rt, peer, method, path, 400, "render-id", start_ms);
      free(req);
      return 0;
    }
    const uint32_t *pkt = NULL;
    uint32_t pkt_len = 0;
    if (!get_packet_by_id(rt, (uint32_t)idl, &pkt, &pkt_len)) {
      json_response_tr(rt, cfd, 404, "{\"ok\":0,\"err\":\"file-id\"}");
      request_log(rt, peer, method, path, 404, "render-file-id", start_ms);
      free(req);
      return 0;
    }

    uint32_t cr = 0, sr = 0, mr = 0;
    if (!parse_a2a_summary(pkt, pkt_len, &cr, &sr, &mr)) {
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"packet\"}");
      request_log(rt, peer, method, path, 400, "render-packet", start_ms);
      free(req);
      return 0;
    }

    char preview[4096];
    uint32_t fallback_len = 0;
    bool ok_preview = build_source_preview(rt, (uint32_t)idl, preview, sizeof(preview), &fallback_len);
    if (!ok_preview) {
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"adapt\"}");
      request_log(rt, peer, method, path, 400, "render-adapt", start_ms);
      free(req);
      return 0;
    }

    char body[RESP_BUF_MAX];
    snprintf(body, sizeof(body),
             "{\"ok\":1,\"render\":{\"fileId\":%ld,\"codeRecords\":%u,\"slotRecords\":%u,\"metaRecords\":%u,\"hasSourceFallback\":%s,\"sourceFallbackLen\":%u,\"sourcePreview\":\"%s\"}}",
             idl, cr, sr, mr, (fallback_len > 0 ? "true" : "false"), fallback_len, preview);
    json_response_tr(rt, cfd, 200, body);
    request_log(rt, peer, method, path, 200, "render", start_ms);
    free(req);
    return 0;
  }

  if (strcmp(method, "POST") == 0 && strcmp(path, "/aiir/project/create") == 0) {
    if (!rt->gateway_enable) {
      json_response_tr(rt, cfd, 404, "{\"ok\":0,\"err\":\"gateway-disabled\"}");
      request_log(rt, peer, method, path, 404, "gateway-disabled", start_ms);
      free(req);
      return 0;
    }
    size_t hdr_end = 0;
    if (!find_header_end(req, (size_t)got, &hdr_end)) {
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"headers\"}");
      request_log(rt, peer, method, path, 400, "headers", start_ms);
      free(req);
      return 0;
    }
    long cl = parse_content_length(req);
    if (cl < 0 || cl > (long)body_cap) {
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"content-length\"}");
      request_log(rt, peer, method, path, 400, "content-length", start_ms);
      free(req);
      return 0;
    }
    const char *bodyp = req + hdr_end;
    long have = (long)got - (long)hdr_end;
    if (have < cl) {
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"body-short\"}");
      request_log(rt, peer, method, path, 400, "body-short", start_ms);
      free(req);
      return 0;
    }

    char project_name[96], db_profile[64], region[64], idem[96], contract_version[24], intent[40];
    if (!parse_json_string_key(bodyp, "\"project_name\"", project_name, sizeof(project_name))) {
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"project_name\"}");
      request_log(rt, peer, method, path, 400, "project_name", start_ms);
      free(req);
      return 0;
    }
    strncpy(db_profile, rt->gateway_db_default_profile, sizeof(db_profile) - 1u);
    db_profile[sizeof(db_profile) - 1u] = '\0';
    strncpy(region, rt->gateway_db_region, sizeof(region) - 1u);
    region[sizeof(region) - 1u] = '\0';
    idem[0] = '\0';
    (void)parse_json_string_key(bodyp, "\"db_profile\"", db_profile, sizeof(db_profile));
    (void)parse_json_string_key(bodyp, "\"region\"", region, sizeof(region));
    (void)parse_json_string_key(bodyp, "\"idempotency_key\"", idem, sizeof(idem));
    strncpy(contract_version, "hal.v1", sizeof(contract_version) - 1u);
    contract_version[sizeof(contract_version) - 1u] = '\0';
    strncpy(intent, "create_project", sizeof(intent) - 1u);
    intent[sizeof(intent) - 1u] = '\0';
    (void)parse_json_string_key(bodyp, "\"contract_version\"", contract_version, sizeof(contract_version));
    (void)parse_json_string_key(bodyp, "\"intent\"", intent, sizeof(intent));
    long long retention_lli = (long long)rt->gateway_db_retention_days;
    long long parsed_ret = 0;
    if (parse_json_int(bodyp, "\"retention_days\"", &parsed_ret) && parsed_ret > 0 && parsed_ret <= 3650) {
      retention_lli = parsed_ret;
    }

    if (!is_ascii_token(project_name, 2u, 95u, "._-")) {
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"project_name\"}");
      request_log(rt, peer, method, path, 400, "project_name-invalid", start_ms);
      free(req);
      return 0;
    }
    if (!is_ascii_token(db_profile, 1u, 63u, "._-")) {
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"db_profile\"}");
      request_log(rt, peer, method, path, 400, "db_profile", start_ms);
      free(req);
      return 0;
    }
    if (!is_ascii_token(region, 1u, 63u, "._-")) {
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"region\"}");
      request_log(rt, peer, method, path, 400, "region", start_ms);
      free(req);
      return 0;
    }
    if (idem[0] != '\0' && !is_ascii_token(idem, 8u, 95u, "._-:")) {
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"idempotency_key\"}");
      request_log(rt, peer, method, path, 400, "idempotency_key", start_ms);
      free(req);
      return 0;
    }
    if (!is_known_contract_version(contract_version)) {
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"contract_version\"}");
      request_log(rt, peer, method, path, 400, "contract_version", start_ms);
      free(req);
      return 0;
    }
    if (!is_known_create_intent(intent)) {
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"intent\"}");
      request_log(rt, peer, method, path, 400, "intent", start_ms);
      free(req);
      return 0;
    }

    if (idem[0] != '\0') {
      char existing_project_ref[64], existing_db_ref[64];
      if (gateway_find_project_by_idempotency(rt, idem, existing_project_ref, sizeof(existing_project_ref),
                                              existing_db_ref, sizeof(existing_db_ref))) {
        char existing_channel[96];
        snprintf(existing_channel, sizeof(existing_channel), "aiir.ev.project.%s", existing_project_ref);
        char out_existing[1024];
        snprintf(out_existing, sizeof(out_existing),
                 "{\"ok\":1,\"project_ref\":\"%s\",\"db_ref\":\"%s\",\"status\":\"provisioning\",\"events_channel\":\"%s\",\"idempotent\":1}",
                 existing_project_ref, existing_db_ref, existing_channel);
        json_response_tr(rt, cfd, 202, out_existing);
        request_log(rt, peer, method, path, 202, "project-create-idempotent", start_ms);
        free(req);
        return 0;
      }
    }

    char project_ref[64], db_ref[64], channel[96];
    gen_ref(project_ref, sizeof(project_ref), "prj", rt);
    gen_ref(db_ref, sizeof(db_ref), "db", rt);
    snprintf(channel, sizeof(channel), "aiir.ev.project.%s", project_ref);

    if (!gateway_store_project(rt, project_ref, db_ref, project_name, db_profile, region, (size_t)retention_lli,
                               idem, contract_version, intent)) {
      json_response_tr(rt, cfd, 503, "{\"ok\":0,\"err\":\"store\"}");
      request_log(rt, peer, method, path, 503, "store", start_ms);
      free(req);
      return 0;
    }

    char out[1024];
    snprintf(out, sizeof(out),
             "{\"ok\":1,\"project_ref\":\"%s\",\"db_ref\":\"%s\",\"status\":\"provisioning\",\"events_channel\":\"%s\"}",
             project_ref, db_ref, channel);
    json_response_tr(rt, cfd, 202, out);
    audit_log(rt, peer, method, path, 202, "gateway-project-create", 0u, project_name);
    request_log(rt, peer, method, path, 202, "project-create", start_ms);
    free(req);
    return 0;
  }

  if (strcmp(method, "POST") == 0 && strcmp(path, "/aiir/db/exec") == 0) {
    if (!rt->gateway_enable) {
      json_response_tr(rt, cfd, 404, "{\"ok\":0,\"err\":\"gateway-disabled\"}");
      request_log(rt, peer, method, path, 404, "gateway-disabled", start_ms);
      free(req);
      return 0;
    }
    size_t hdr_end = 0;
    if (!find_header_end(req, (size_t)got, &hdr_end)) {
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"headers\"}");
      request_log(rt, peer, method, path, 400, "headers", start_ms);
      free(req);
      return 0;
    }
    long cl = parse_content_length(req);
    if (cl < 0 || cl > (long)body_cap) {
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"content-length\"}");
      request_log(rt, peer, method, path, 400, "content-length", start_ms);
      free(req);
      return 0;
    }
    const char *bodyp = req + hdr_end;
    long have = (long)got - (long)hdr_end;
    if (have < cl) {
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"body-short\"}");
      request_log(rt, peer, method, path, 400, "body-short", start_ms);
      free(req);
      return 0;
    }

    char project_ref[64], db_ref[64], op_id[64], req_id[64], contract_version[24], intent[32];
    if (!parse_json_string_key(bodyp, "\"project_ref\"", project_ref, sizeof(project_ref))) {
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"project_ref\"}");
      request_log(rt, peer, method, path, 400, "project_ref", start_ms);
      free(req);
      return 0;
    }
    if (!parse_json_string_key(bodyp, "\"db_ref\"", db_ref, sizeof(db_ref))) {
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"db_ref\"}");
      request_log(rt, peer, method, path, 400, "db_ref", start_ms);
      free(req);
      return 0;
    }
    if (!parse_json_string_key(bodyp, "\"op_id\"", op_id, sizeof(op_id))) {
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"op_id\"}");
      request_log(rt, peer, method, path, 400, "op_id", start_ms);
      free(req);
      return 0;
    }
    if (!parse_json_string_key(bodyp, "\"req_id\"", req_id, sizeof(req_id))) {
      gen_ref(req_id, sizeof(req_id), "req", rt);
    }
    strncpy(contract_version, "hal.v1", sizeof(contract_version) - 1u);
    contract_version[sizeof(contract_version) - 1u] = '\0';
    intent[0] = '\0';
    (void)parse_json_string_key(bodyp, "\"contract_version\"", contract_version, sizeof(contract_version));
    (void)parse_json_string_key(bodyp, "\"intent\"", intent, sizeof(intent));

    if (!is_ascii_token(project_ref, 8u, 63u, "._-")) {
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"project_ref\"}");
      request_log(rt, peer, method, path, 400, "project_ref-invalid", start_ms);
      free(req);
      return 0;
    }
    if (!is_ascii_token(db_ref, 6u, 63u, "._-")) {
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"db_ref\"}");
      request_log(rt, peer, method, path, 400, "db_ref-invalid", start_ms);
      free(req);
      return 0;
    }
    if (!is_ascii_token(op_id, 3u, 63u, "._-:")) {
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"op_id\"}");
      request_log(rt, peer, method, path, 400, "op_id-invalid", start_ms);
      free(req);
      return 0;
    }
    if (!is_ascii_token(req_id, 3u, 63u, "._-:")) {
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"req_id\"}");
      request_log(rt, peer, method, path, 400, "req_id-invalid", start_ms);
      free(req);
      return 0;
    }
    if (!is_known_contract_version(contract_version)) {
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"contract_version\"}");
      request_log(rt, peer, method, path, 400, "contract_version", start_ms);
      free(req);
      return 0;
    }
    if (intent[0] != '\0' && !is_known_db_exec_intent(intent)) {
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"intent\"}");
      request_log(rt, peer, method, path, 400, "intent", start_ms);
      free(req);
      return 0;
    }
    if (!strstr(bodyp, "\"payload\"")) {
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"payload\"}");
      request_log(rt, peer, method, path, 400, "payload", start_ms);
      free(req);
      return 0;
    }
    if (!gateway_project_db_exists(rt, project_ref, db_ref)) {
      json_response_tr(rt, cfd, 404, "{\"ok\":0,\"err\":\"db_ref\"}");
      request_log(rt, peer, method, path, 404, "db_ref-missing", start_ms);
      free(req);
      return 0;
    }
    if (rt->gateway_human_indirect && !rt->gateway_allow_direct_credentials) {
      /* Human mode is indirect by design; execution stays AI-managed. */
    }
    char out[1024];
    snprintf(out, sizeof(out),
             "{\"ok\":1,\"req_id\":\"%s\",\"result\":{\"status\":\"queued\",\"provider\":\"%s\",\"project_ref\":\"%s\",\"db_ref\":\"%s\",\"op_id\":\"%s\"}}",
             req_id, rt->gateway_db_provider, project_ref, db_ref, op_id);
    json_response_tr(rt, cfd, 200, out);
    audit_log(rt, peer, method, path, 200, "gateway-db-exec", 0u, op_id);
    request_log(rt, peer, method, path, 200, "gateway-db-exec", start_ms);
    free(req);
    return 0;
  }

  if (strcmp(method, "POST") == 0 && strcmp(path, "/ai/db/exec") == 0) {
    if (!rt->policy.allow_db_exec) {
      rt->metric_db_exec_deny_total++;
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"policy-db-exec\"}");
      audit_log(rt, peer, method, path, 400, "db-exec-deny", 0u, "policy-db-exec");
      request_log(rt, peer, method, path, 400, "policy-db-exec", start_ms);
      free(req);
      return 0;
    }
    size_t hdr_end = 0;
    if (!find_header_end(req, (size_t)got, &hdr_end)) {
      rt->metric_db_exec_deny_total++;
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"headers\"}");
      audit_log(rt, peer, method, path, 400, "db-exec-deny", 0u, "headers");
      request_log(rt, peer, method, path, 400, "headers", start_ms);
      free(req);
      return 0;
    }
    long cl = parse_content_length(req);
    if (cl < 0 || cl > (long)body_cap) {
      rt->metric_db_exec_deny_total++;
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"content-length\"}");
      audit_log(rt, peer, method, path, 400, "db-exec-deny", 0u, "content-length");
      request_log(rt, peer, method, path, 400, "content-length", start_ms);
      free(req);
      return 0;
    }

    const char *bodyp = req + hdr_end;
    long have = (long)got - (long)hdr_end;
    if (have < cl) {
      rt->metric_db_exec_deny_total++;
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"body-short\"}");
      audit_log(rt, peer, method, path, 400, "db-exec-deny", 0u, "body-short");
      request_log(rt, peer, method, path, 400, "body-short", start_ms);
      free(req);
      return 0;
    }

    long long op_lli = 0;
    if (!parse_json_int(bodyp, "\"opId\"", &op_lli) || op_lli < 0 || op_lli > 0xffffffffLL) {
      rt->metric_db_exec_deny_total++;
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"opId\"}");
      audit_log(rt, peer, method, path, 400, "db-exec-deny", 0u, "opId");
      request_log(rt, peer, method, path, 400, "opId", start_ms);
      free(req);
      return 0;
    }
    uint32_t op_id = (uint32_t)op_lli;

    char cap_deny[64];
    if (!validate_capability(rt, req, op_id, cap_deny, sizeof(cap_deny))) {
      rt->metric_db_exec_deny_total++;
      rt->metric_capability_deny_total++;
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"capability\"}");
      audit_log(rt, peer, method, path, 400, "db-exec-deny", op_id, cap_deny);
      request_log(rt, peer, method, path, 400, "capability", start_ms);
      free(req);
      return 0;
    }

    if (!aiir_policy_allow_op(&rt->policy, op_id)) {
      rt->metric_db_exec_deny_total++;
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"policy-op\"}");
      audit_log(rt, peer, method, path, 400, "db-exec-deny", op_id, "policy-op");
      request_log(rt, peer, method, path, 400, "policy-op", start_ms);
      free(req);
      return 0;
    }
    const DbOp *op = find_op(rt, op_id);
    if (!op) {
      rt->metric_db_exec_deny_total++;
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"op\"}");
      audit_log(rt, peer, method, path, 400, "db-exec-deny", op_id, "op");
      request_log(rt, peer, method, path, 400, "op", start_ms);
      free(req);
      return 0;
    }

    JsonVal *args = NULL;
    size_t argc = 0;
    if (!parse_json_args(bodyp, &args, &argc)) {
      rt->metric_db_exec_deny_total++;
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"args\"}");
      audit_log(rt, peer, method, path, 400, "db-exec-deny", op_id, "args");
      request_log(rt, peer, method, path, 400, "args", start_ms);
      free(req);
      return 0;
    }

    if (argc < op->min_args || argc > op->max_args) {
      for (size_t i = 0; i < argc; i++) free(args[i].s);
      free(args);
      rt->metric_db_exec_deny_total++;
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"argc\"}");
      audit_log(rt, peer, method, path, 400, "db-exec-deny", op_id, "argc");
      request_log(rt, peer, method, path, 400, "argc", start_ms);
      free(req);
      return 0;
    }

    uint32_t sigc = count_sig_for_op(rt, op_id);
    if (sigc != argc) {
      for (size_t i = 0; i < argc; i++) free(args[i].s);
      free(args);
      rt->metric_db_exec_deny_total++;
      json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"sig-arity\"}");
      audit_log(rt, peer, method, path, 400, "db-exec-deny", op_id, "sig-arity");
      request_log(rt, peer, method, path, 400, "sig-arity", start_ms);
      free(req);
      return 0;
    }

    for (size_t i = 0; i < argc; i++) {
      const DbSig *sg = find_sig(rt, op_id, (uint32_t)i);
      if (!sg || !type_check(sg->type_id, &args[i])) {
        for (size_t k = 0; k < argc; k++) free(args[k].s);
        free(args);
        rt->metric_db_exec_deny_total++;
        json_response_tr(rt, cfd, 400, "{\"ok\":0,\"err\":\"type\"}");
        audit_log(rt, peer, method, path, 400, "db-exec-deny", op_id, "type");
        request_log(rt, peer, method, path, 400, "type", start_ms);
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
    rt->metric_db_exec_allow_total++;
    json_response_tr(rt, cfd, 200, body);
    audit_log(rt, peer, method, path, 200, "db-exec-allow", op_id, "ok");
    request_log(rt, peer, method, path, 200, "db-exec", start_ms);
    free(req);
    return 0;
  }

  json_response_tr(rt, cfd, 404, "{\"ok\":0,\"err\":\"route\"}");
  request_log(rt, peer, method, path, 404, "route", start_ms);
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
    struct sockaddr_storage peer_addr;
    socklen_t peer_len = sizeof(peer_addr);
    int cfd = accept(sfd, (struct sockaddr *)&peer_addr, &peer_len);
    if (cfd < 0) {
      if (errno == EINTR) continue;
      perror("accept");
      break;
    }
    char peer[128];
    peer[0] = '\0';
    if (peer_addr.ss_family == AF_INET) {
      struct sockaddr_in *a4 = (struct sockaddr_in *)&peer_addr;
      char ip[64];
      if (inet_ntop(AF_INET, &a4->sin_addr, ip, sizeof(ip))) {
        snprintf(peer, sizeof(peer), "%s:%u", ip, (unsigned)ntohs(a4->sin_port));
      }
    } else if (peer_addr.ss_family == AF_INET6) {
      snprintf(peer, sizeof(peer), "ipv6");
    }
    if (peer[0] == '\0') strncpy(peer, "unknown", sizeof(peer) - 1u);
    struct timeval tv;
    tv.tv_sec = (time_t)(timeout_ms / 1000u);
    tv.tv_usec = (suseconds_t)((timeout_ms % 1000u) * 1000u);
    (void)setsockopt(cfd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    (void)setsockopt(cfd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    time_t now = time(NULL);
    if (cb_open_until > now) {
      rt.metric_circuit_open_total++;
      json_response_tr(&rt, cfd, 503, "{\"ok\":0,\"err\":\"circuit-open\"}");
      audit_log(&rt, peer, "-", "-", 503, "runtime-deny", 0u, "circuit-open");
      close(cfd);
      continue;
    }
    if (rl_window != now) {
      rl_window = now;
      rl_count = 0;
    }
    if (rl_count >= rate_limit_rps) {
      rt.metric_rate_limited_total++;
      json_response_tr(&rt, cfd, 429, "{\"ok\":0,\"err\":\"rate-limit\"}");
      audit_log(&rt, peer, "-", "-", 429, "runtime-deny", 0u, "rate-limit");
      close(cfd);
      continue;
    }
    rl_count++;
    aiir_drift_tick(&rt.drift);
    int rc = handle_request(&rt, cfd, peer, db_mode, req_cap, body_cap);
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
