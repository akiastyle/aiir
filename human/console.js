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

  const reqId = () => `req_${Date.now()}`;
  const idk = () => `idk_${Date.now()}`;

  function appendLog(title, data, isErr) {
    const stamp = new Date().toISOString();
    const prefix = isErr ? "ERR" : "OK";
    const body = typeof data === "string" ? data : JSON.stringify(data, null, 2);
    logEl.textContent = `[${stamp}] ${prefix} ${title}\n${body}\n\n` + logEl.textContent;
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

    await postJson("/aiir/db/exec", body);
  }

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

  appendLog("ready", "Human Console v1 pronta (full screen, AIIR gateway mode)");
})();
