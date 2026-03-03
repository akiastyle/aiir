# Human Project Types v1

This catalog belongs to the `human` layer only.
Runtime AIIR stays generic and clean.

## Core Types

| project_type | default db_profile | default retention_days | primary use |
|---|---|---:|---|
| `website` | `content` | 30 | standard business website |
| `ecommerce` | `commerce` | 180 | product/catalog/order flows |
| `webapp` | `app` | 90 | interactive web application |
| `backend` | `service` | 90 | API/service-focused project |
| `frontend` | `edge` | 30 | UI-only frontend project |
| `mobileapp` | `mobile` | 60 | mobile-first app backend |

## Extended Types

| project_type | default db_profile | default retention_days | primary use |
|---|---|---:|---|
| `landing_page` | `content` | 30 | campaign/landing pages |
| `cms_content_site` | `content` | 30 | managed content site |
| `blog_magazine` | `content` | 30 | publishing/editorial |
| `dashboard_admin` | `app` | 90 | admin/internal tools |
| `api_service` | `service` | 90 | API-only workloads |
| `saas_multitenant` | `saas` | 180 | multi-tenant SaaS |
| `marketplace` | `commerce` | 180 | multi-vendor commerce |
| `booking_platform` | `app` | 120 | booking/scheduling systems |
| `lms_elearning` | `app` | 120 | training and e-learning |
| `community_forum` | `community` | 90 | social/community interactions |
| `automation_agentic` | `agent` | 60 | workflow/AI automation |
| `pwa_app` | `mobile` | 60 | progressive web app |

## Human -> AIIR Mapping

Human action:
- choose `project_name`
- choose `project_type`
- optionally pass `domain`

Human adapter translates type into defaults and calls AIIR provisioning:
- `/var/www/aiir/server/scripts/provision-project-domain.sh <project-name> [domain]`

No project-type logic is required in AIIR runtime.
