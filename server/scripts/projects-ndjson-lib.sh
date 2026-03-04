#!/usr/bin/env bash
set -euo pipefail

aiir_json_get_str() {
  local line="$1"
  local field="$2"
  awk -v line="$line" -v field="$field" 'BEGIN {
    re="\"" field "\":\"[^\"]*\"";
    if (match(line, re)) {
      val=substr(line, RSTART+length(field)+4, RLENGTH-length(field)-5);
      print val;
    }
  }'
}

aiir_json_get_num() {
  local line="$1"
  local field="$2"
  awk -v line="$line" -v field="$field" 'BEGIN {
    re="\"" field "\":[0-9]+";
    if (match(line, re)) {
      val=substr(line, RSTART+length(field)+3, RLENGTH-length(field)-3);
      print val;
    }
  }'
}

aiir_project_line_latest() {
  local file="$1"
  local mode="$2"
  local ident="$3"
  if [[ ! -f "$file" ]]; then
    return 1
  fi
  awk -v mode="$mode" -v ident="$ident" '
    function getf(line, key,   re) {
      re="\"" key "\":\"[^\"]*\"";
      if (match(line, re)) return substr(line, RSTART+length(key)+4, RLENGTH-length(key)-5);
      return "";
    }
    {
      ref=getf($0, "project_ref");
      name=getf($0, "project_name");
      if (mode=="ref") {
        if (ref==ident || tolower(ref)==tolower(ident)) last=$0;
      } else {
        if (name==ident || tolower(name)==tolower(ident)) last=$0;
      }
    }
    END { if (last != "") print last; }
  ' "$file"
}

aiir_project_lines_latest_unique() {
  local file="$1"
  local limit="${2:-20}"
  if [[ ! -f "$file" ]]; then
    return 0
  fi
  awk -v limit="$limit" '
    function getf(line, key,   re) {
      re="\"" key "\":\"[^\"]*\"";
      if (match(line, re)) return substr(line, RSTART+length(key)+4, RLENGTH-length(key)-5);
      return "";
    }
    {
      ref=getf($0, "project_ref");
      if (ref != "") row[ref]=$0;
    }
    END {
      n=0;
      for (r in row) {
        print row[r];
        n++;
        if (n>=limit) break;
      }
    }
  ' "$file"
}
