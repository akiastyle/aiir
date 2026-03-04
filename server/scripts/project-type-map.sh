#!/usr/bin/env bash
set -euo pipefail

aiir_map_project_type() {
  local raw_type="${1:-webapp}"
  local t
  t="$(printf '%s' "$raw_type" | tr '[:upper:]' '[:lower:]')"
  case "$t" in
    website|landing_page|cms_content_site|blog_magazine)
      echo "content 30" ;;
    ecommerce|marketplace)
      echo "commerce 180" ;;
    webapp|dashboard_admin)
      echo "app 90" ;;
    backend|api_service)
      echo "service 90" ;;
    frontend)
      echo "edge 30" ;;
    mobileapp|pwa_app)
      echo "mobile 60" ;;
    saas_multitenant)
      echo "saas 180" ;;
    booking_platform|lms_elearning)
      echo "app 120" ;;
    community_forum)
      echo "community 90" ;;
    automation_agentic)
      echo "agent 60" ;;
    *)
      echo "app 90" ;;
  esac
}

aiir_is_known_project_type() {
  local raw_type="${1:-}"
  local t
  t="$(printf '%s' "$raw_type" | tr '[:upper:]' '[:lower:]')"
  case "$t" in
    website|landing_page|cms_content_site|blog_magazine|ecommerce|marketplace|webapp|dashboard_admin|backend|api_service|frontend|mobileapp|pwa_app|saas_multitenant|booking_platform|lms_elearning|community_forum|automation_agentic)
      return 0 ;;
    *)
      return 1 ;;
  esac
}
