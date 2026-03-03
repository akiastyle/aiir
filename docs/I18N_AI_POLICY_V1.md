# I18N AI Policy v1

## Goal
Keep core contracts language-neutral while AI handles text localization for browser users.

## Principles

- Source texts remain canonical in a base language
- AI generates browser-language translations at runtime
- UI direction is selected automatically:
  - LTR for left-to-right languages
  - RTL for right-to-left languages

## Runtime Rules

- Determine locale from browser preferences (`Accept-Language`) or explicit user preference
- Resolve direction:
  - `rtl` for languages like `ar`, `he`, `fa`, `ur`
  - `ltr` otherwise
- Apply direction at page root (`dir=ltr|rtl`)
- Keep payload contracts unchanged across locales

## Human/AI Responsibilities

- human:
  - defines content intent and approves key wording where needed
- AI:
  - translates text for target locale
  - enforces RTL/LTR layout mode
  - keeps semantic consistency across localized variants

## Technical Notes

- Do not duplicate business logic per language
- Localize labels/messages only
- Audit source text and locale used for generated outputs when needed
