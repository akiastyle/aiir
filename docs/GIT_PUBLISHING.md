# Git Publishing

## 1) Initialize Repository
```bash
cd /var/www/aiir
git init
git checkout -b main
git add .
git commit -m "aiir: initial publish baseline"
```

## 2) Add Remote
```bash
git remote add origin <git-url>
git push -u origin main
```

## 3) Recommended Branch Model
- `main`: stable
- `release/*`: release candidates
- `feat/*`: new features
- `fix/*`: bug fixes

## 4) Commit Rules
- keep commits small and atomic
- use commit prefixes:
  - `core:`
  - `runtime:`
  - `security:`
  - `docs:`
  - `ops:`

Example:
```bash
git commit -m "security: add peer revocation and anti-replay ledger"
```

## 5) What Not to Publish
- private keys (`ai/keys/local/*/signing_priv.pem`)
- sensitive runtime state (`ai/state/*.wal`)
- unnecessary local backups

## 6) Tag Release
```bash
git tag -a v0.1.0 -m "AIIR baseline stable"
git push origin v0.1.0
```
