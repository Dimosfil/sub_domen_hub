# Root Hub Project Card Inbox

Agents that deploy new public projects through `gi ftp` should leave pending
card records here. Do not store secrets, credentials, private hosting paths,
raw logs, screenshots, or full deploy output.

When the user asks to update the public hub, apply approved pending records to
`D:\AI\ai-automation-studio\index.html`, build `D:\AI\ai-automation-studio`, and
publish it through the configured deploy gateway.

## Entry Template

```markdown
## YYYY-MM-DD project_id

- Status: pending
- Project id: client_portal
- Title: Client Portal
- Icon: CP
- Description: Short human description of the project.
- Public URL: https://client-portal.unity-constructor.site/
- Display host: client-portal.unity-constructor.site
- Legacy URL: /client_portal/
- Deploy map status: subdomain-active
- Source/deploy notes: optional short note
```

## Pending

No pending card records.

## Published

## 2026-07-04 teiko

- Status: published
- Project id: teiko
- Title: TEIKO
- Icon: TK
- Description: Витрина автохимии TEIKO с каталогом товаров и переходом на маркетплейсы.
- Public URL: https://teiko.unity-constructor.site/
- Display host: teiko.unity-constructor.site
- Legacy URL: /teiko/
- Deploy map status: subdomain-active
- Source/deploy notes: Uploaded static TEIKO storefront artifact to the project-scoped subdomain target on 2026-07-04. Public hub card published on 2026-07-04. HTTPS verified with Let's Encrypt on 2026-07-04.
