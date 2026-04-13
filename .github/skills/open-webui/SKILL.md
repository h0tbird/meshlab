---
name: open-webui
description: Opens meshlab web UIs (ArgoCD, Argo Workflows, Vault, Prometheus, Grafana, Kiali, Tilt) in the integrated browser. Use this skill when asked to open, access, check, or view any of the lab's web dashboards or UIs.
---

# Open Web UI Skill

This skill opens meshlab service web UIs using the integrated Simple Browser.

## Prerequisites

The VS Code setting `workbench.browser.enableChatTools` must be `true`.

## Services

| Service | URL | Credentials |
|---------|-----|-------------|
| Argo CD | http://127.0.0.1:8080 | admin / meshlab123 |
| Argo Workflows | http://127.0.0.1:8081 | admin / meshlab123 |
| Vault | http://127.0.0.1:8082 | - |
| Prometheus | http://127.0.0.1:8083 | - |
| Grafana | http://127.0.0.1:8084 | admin / meshlab123 |
| Kiali | http://127.0.0.1:8085 | - |
| Tilt pasta-1 | http://127.0.0.1:9091 | - |
| Tilt pasta-2 | http://127.0.0.1:9092 | - |

## Important

Always use the **VS Code built-in browser tools** (`open_browser_page`, `screenshot_page`, `click_element`, `type_in_page`) to interact with the embedded Simple Browser tab. Do **NOT** use `mcp_chromedevtool_*` tools — those control an external Chrome instance, not the embedded tab.

## Procedure

1. Use the `open_browser_page` tool with the service URL from the table above.
2. If the service requires login (e.g. Argo CD), fill in the credentials using `type_in_page` and `click_element`.
3. For Argo CD specifically:
   - The login form has a `Username` textbox and a `Password` textbox.
   - Type `admin` in the Username field, `meshlab123` in the Password field, then click `Sign In`.
4. For Kiali specifically:
   - Kiali uses token-based auth and shows a login page with a `Log In` button.
   - No credentials are needed. Simply click the `Log In` button to proceed.
   - After login, the Overview page loads automatically showing clusters, Istio configs, control planes, data planes, and application health.
