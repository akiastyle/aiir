# Human Layer

Human Console v1 (full-screen, fluid, no boxed layout):
- [console.html](/var/www/aiir/human/console.html)
- [console.css](/var/www/aiir/human/console.css)
- [console.js](/var/www/aiir/human/console.js)
- logo: [aiir-logo.svg](/var/www/aiir/human/assets/aiir-logo.svg)

Views:
- `Form`: create project + db exec
- `Chat`: operational prompt (gateway-backed intents)

Run:
```bash
cd /var/www/aiir/human
python3 -m http.server 8090
```

Open:
- `http://127.0.0.1:8090/console.html`

Gateway defaults:
- endpoint UI default: `http://127.0.0.1:3000`
- project create: `POST /aiir/project/create`
- db exec: `POST /aiir/db/exec`

Chat intents in v1:
- `crea progetto <nome> [tipo <tipo>] [dominio <dominio>]`
- `salva <collection> <json>`
- `leggi <collection> <id>`
- `stato locale`
- `help`

Operational provisioning remains AI-first and can still be managed via chat CLI:
```bash
/var/www/aiir/server/scripts/aiir chat "crea progetto <name> tipo <type> dominio <domain>"
```
