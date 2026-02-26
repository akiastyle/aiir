# Git Publishing

## 1) Inizializzazione repository
```bash
cd /var/www/aiir
git init
git checkout -b main
git add .
git commit -m "aiir: initial publish baseline"
```

## 2) Remote
```bash
git remote add origin <git-url>
git push -u origin main
```

## 3) Branch model consigliato
- `main`: stabile
- `release/*`: candidate rilascio
- `feat/*`: nuove funzioni
- `fix/*`: bugfix

## 4) Regole commit
- commit piccoli e atomici
- messaggi con prefisso:
  - `core:`
  - `runtime:`
  - `security:`
  - `docs:`
  - `ops:`

Esempio:
```bash
git commit -m "security: add peer revocation and anti-replay ledger"
```

## 5) Cosa non pubblicare
- chiavi private (`ai/keys/local/*/signing_priv.pem`)
- stato runtime sensibile (`ai/state/*.wal`)
- backup locali non necessari

## 6) Tag release
```bash
git tag -a v0.1.0 -m "AIIR baseline stable"
git push origin v0.1.0
```
