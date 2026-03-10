(function () {
  const $ = (id) => document.getElementById(id);

  const endpointEl = $("endpoint");
  const projectNameEl = $("project_name");
  const projectTypeEl = $("project_type");
  const domainEl = $("domain");
  const regionEl = $("region");
  const projectRefEl = $("project_ref");
  const dbRefEl = $("db_ref");
  const opIdEl = $("op_id");
  const collectionEl = $("collection");
  const payloadJsonEl = $("payload_json");
  const logEl = $("log");

  const modeFormEl = $("mode_form");
  const modeChatEl = $("mode_chat");
  const viewFormEl = $("view_form");
  const viewChatEl = $("view_chat");

  const chatInputEl = $("chat_input");
  const chatLogEl = $("chat_log");

  const reqId = () => `req_${Date.now()}`;
  const idk = () => `idk_${Date.now()}`;

  function appendLog(title, data, isErr) {
    const stamp = new Date().toISOString();
    const prefix = isErr ? "ERR" : "OK";
    const body = typeof data === "string" ? data : JSON.stringify(data, null, 2);
    logEl.textContent = `[${stamp}] ${prefix} ${title}\n${body}\n\n` + logEl.textContent;
  }

  function appendChat(title, data, isErr) {
    const stamp = new Date().toISOString();
    const prefix = isErr ? "ERR" : "OK";
    const body = typeof data === "string" ? data : JSON.stringify(data, null, 2);
    chatLogEl.textContent = `[${stamp}] ${prefix} ${title}\n${body}\n\n` + chatLogEl.textContent;
  }

  async function postJson(path, body) {
    const base = endpointEl.value.trim().replace(/\/$/, "");
    const url = `${base}${path}`;
    const res = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify(body)
    });

    const text = await res.text();
    let parsed = text;
    try {
      parsed = JSON.parse(text);
    } catch (_err) {
      // keep raw text
    }

    if (!res.ok) {
      appendLog(`${path} ${res.status}`, parsed, true);
      throw new Error(`HTTP ${res.status}`);
    }

    appendLog(`${path} ${res.status}`, parsed, false);
    return parsed;
  }

  function setMode(mode) {
    const isChat = mode === "chat";
    modeFormEl.classList.toggle("active", !isChat);
    modeFormEl.setAttribute("aria-selected", (!isChat).toString());
    modeChatEl.classList.toggle("active", isChat);
    modeChatEl.setAttribute("aria-selected", isChat.toString());
    viewFormEl.classList.toggle("active", !isChat);
    viewChatEl.classList.toggle("active", isChat);
  }

  async function createProject() {
    const projectName = projectNameEl.value.trim();
    if (!projectName) {
      appendLog("validation", "project_name obbligatorio", true);
      return;
    }

    const body = {
      contract_version: "hal.v1",
      intent: "create_project_typed",
      project_name: projectName,
      project_type: projectTypeEl.value,
      domain: domainEl.value.trim() || undefined,
      db_profile: "default",
      region: regionEl.value.trim() || "local",
      retention_days: 30,
      idempotency_key: idk()
    };

    const res = await postJson("/aiir/project/create", body);
    if (res && res.project_ref) {
      projectRefEl.value = res.project_ref;
    }
    if (res && res.db_ref) {
      dbRefEl.value = res.db_ref;
    }
    return res;
  }

  async function execDb() {
    let payload;
    try {
      payload = JSON.parse(payloadJsonEl.value);
    } catch (_err) {
      appendLog("validation", "payload_json non valido", true);
      return;
    }

    const projectRef = projectRefEl.value.trim();
    const dbRef = dbRefEl.value.trim();
    if (!projectRef || !dbRef) {
      appendLog("validation", "project_ref e db_ref obbligatori", true);
      return;
    }

    const body = {
      contract_version: "hal.v1",
      intent: opIdEl.value === "entity.read" ? "read_data" : "save_data",
      project_ref: projectRef,
      db_ref: dbRef,
      op_id: opIdEl.value,
      payload: {
        collection: collectionEl.value.trim() || "customers",
        ...payload
      },
      req_id: reqId()
    };

    return postJson("/aiir/db/exec", body);
  }

  function parseCreateCommand(raw) {
    const m = raw.match(/^crea\s+progetto\s+([a-z0-9._-]+)(?:\s+tipo\s+([a-z0-9._-]+))?(?:\s+dominio\s+([a-z0-9._-]+))?$/i);
    if (!m) {
      return null;
    }
    return {
      name: m[1],
      type: m[2] || "webapp",
      domain: m[3] || ""
    };
  }

  function parseSaveCommand(raw) {
    const m = raw.match(/^salva\s+([a-z0-9._-]+)\s+(.+)$/i);
    if (!m) {
      return null;
    }
    return {
      collection: m[1],
      json: m[2]
    };
  }

  function parseReadCommand(raw) {
    const m = raw.match(/^leggi\s+([a-z0-9._-]+)\s+([a-z0-9._-]+)$/i);
    if (!m) {
      return null;
    }
    return {
      collection: m[1],
      id: m[2]
    };
  }

  async function runChatCommand(message) {
    const raw = message.trim();
    if (!raw) {
      appendChat("chat", "comando vuoto", true);
      return;
    }

    appendChat("human", raw, false);

    if (/^help$/i.test(raw)) {
      appendChat("aiir-help", [
        "crea progetto <nome> [tipo <tipo>] [dominio <dominio>]",
        "salva <collection> <json>",
        "leggi <collection> <id>",
        "stato locale"
      ].join("\n"), false);
      return;
    }

    if (/^stato\s+locale$/i.test(raw)) {
      appendChat("aiir-state", {
        endpoint: endpointEl.value.trim(),
        project_name: projectNameEl.value.trim(),
        project_type: projectTypeEl.value,
        domain: domainEl.value.trim(),
        project_ref: projectRefEl.value.trim(),
        db_ref: dbRefEl.value.trim()
      }, false);
      return;
    }

    const createCmd = parseCreateCommand(raw);
    if (createCmd) {
      projectNameEl.value = createCmd.name;
      projectTypeEl.value = createCmd.type;
      domainEl.value = createCmd.domain;
      const res = await createProject();
      appendChat("aiir-create", res, false);
      return;
    }

    const saveCmd = parseSaveCommand(raw);
    if (saveCmd) {
      let payload;
      try {
        payload = JSON.parse(saveCmd.json);
      } catch (_err) {
        appendChat("aiir-save", "json non valido nel comando salva", true);
        return;
      }
      collectionEl.value = saveCmd.collection;
      opIdEl.value = "entity.upsert";
      payloadJsonEl.value = JSON.stringify(payload, null, 2);
      const res = await execDb();
      appendChat("aiir-save", res, false);
      return;
    }

    const readCmd = parseReadCommand(raw);
    if (readCmd) {
      collectionEl.value = readCmd.collection;
      opIdEl.value = "entity.read";
      payloadJsonEl.value = JSON.stringify({ doc: { id: readCmd.id } }, null, 2);
      const res = await execDb();
      appendChat("aiir-read", res, false);
      return;
    }

    appendChat(
      "aiir-chat",
      "Intent non supportato via gateway HTTP in questa v1. Usa: crea progetto | salva | leggi | stato locale | help",
      true
    );
  }

  modeFormEl.addEventListener("click", () => setMode("form"));
  modeChatEl.addEventListener("click", () => setMode("chat"));

  $("create_project").addEventListener("click", () => {
    createProject().catch((err) => appendLog("create_project", err.message, true));
  });

  $("exec_db").addEventListener("click", () => {
    execDb().catch((err) => appendLog("db_exec", err.message, true));
  });

  $("refresh_state").addEventListener("click", () => {
    appendLog("state", {
      endpoint: endpointEl.value.trim(),
      project_name: projectNameEl.value.trim(),
      project_type: projectTypeEl.value,
      domain: domainEl.value.trim(),
      project_ref: projectRefEl.value.trim(),
      db_ref: dbRefEl.value.trim()
    });
  });

  $("clear_log").addEventListener("click", () => {
    logEl.textContent = "";
  });

  $("send_chat").addEventListener("click", () => {
    runChatCommand(chatInputEl.value).catch((err) => appendChat("chat", err.message, true));
  });

  chatInputEl.addEventListener("keydown", (evt) => {
    if (evt.key === "Enter" && (evt.ctrlKey || evt.metaKey)) {
      runChatCommand(chatInputEl.value).catch((err) => appendChat("chat", err.message, true));
    }
  });

  $("clear_chat").addEventListener("click", () => {
    chatLogEl.textContent = "";
  });

  document.querySelectorAll(".chip").forEach((chip) => {
    chip.addEventListener("click", () => {
      chatInputEl.value = chip.dataset.chat || "";
      chatInputEl.focus();
    });
  });

  setMode("form");
  appendLog("ready", "Human Console v1 pronta (full screen, AIIR gateway mode)");
  appendChat("ready", "Chat operativa v1 pronta (Ctrl/Cmd+Invio per inviare)", false);
})();
