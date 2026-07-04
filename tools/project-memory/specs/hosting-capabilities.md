# Hosting Capabilities

Last reviewed: 2026-07-04

## Scope

Verified against the REG.RU ISPmanager panel for the hosting account connected
to `unity-constructor.site`. This file must not contain panel, FTP, SSH, SFTP,
or database passwords.

## Panel

- Panel product: ISPmanager 6.
- Verified panel version: 6.144.1-2026.06.02_17:12.
- User level: hosting user.
- Available relevant sections include Sites (`webdomain`), DNS management
  (`domain` and `domain.record`), databases, FTP users, SSL certificates,
  scheduler, logs, and file manager.

## Domain

- Primary domain: `unity-constructor.site`.
- Site document root reported by ISPmanager: `/www/unity-constructor.site`.
- IPv4 address: `31.31.198.142`.
- IPv6 address: `2a00:f940:2:2:1:1:0:15`.
- Name servers resolved publicly: `ns1.hosting.reg.ru`,
  `ns2.hosting.reg.ru`.
- DNS zone is visible and editable through ISPmanager.

## Current File Layout

- `/www` currently contains one site folder: `unity-constructor.site`.
- Existing projects/assets are currently placed as folders inside
  `/www/unity-constructor.site`, not as separate webdomains.
- Observed folders inside `/www/unity-constructor.site`:
  - `ai-automation-studio`
  - `api`
  - `assets`
  - `test_site_usmanova`
  - `unityconstructor`
  - `uploads`
  - `webassist`
  - `web-assist`
  - `work_search`
- The root also contains top-level site files such as `index.html`, `app.js`,
  `styles.css`, `.htaccess`, `health`, and `visual-settings.json`.
- Root `index.html` is now a hub page that lists current legacy folder links
  and active subdomain links for projects. Legacy assets and project folders
  remain in place. Legacy folder links are shown in a separate collapsible
  "Legacy адреса" block, while primary project cards link to subdomains.

## Subdomain Capability

- Subdomains can be created on this account.
- Evidence:
  - `webdomain` section is available and lists `unity-constructor.site`.
  - `webdomain.edit` creation form is available.
  - The account reports `limit_domains = 100`.
  - `autosubdomain` is available on the main webdomain and currently `off`.
  - `domain.record` lists DNS records for `unity-constructor.site`.
  - `domain.record.edit` creation form is available for the zone.

## Recommended Approach

For controlled deployments, create each application subdomain as a separate
webdomain/site with its own document root, then create matching DNS A/AAAA
records when the panel does not do it automatically.

Autopoddomains can also be enabled, but they share behavior with the parent
site and are less explicit for agent-operated deploys.

## Migration Decision

- Keep the current folder-based layout as the legacy deployment route.
- Add a second subdomain deployment route for project sites.
- Do not migrate or remove `unityconstructor`; it remains under
  `/www/unity-constructor.site/unityconstructor`.
- Do not promote shared folders `assets` and `uploads` to subdomains.
- Active project subdomains:
  - `ai-automation-studio.unity-constructor.site`
  - `api.unity-constructor.site`
  - `test-site-usmanova.unity-constructor.site`
  - `teiko.unity-constructor.site`
  - `webassist.unity-constructor.site`
  - `web-assist.unity-constructor.site`
  - `work-search.unity-constructor.site`

## Created Subdomains

Created and verified on 2026-07-04:

- `ai-automation-studio.unity-constructor.site` ->
  `/www/ai-automation-studio.unity-constructor.site`
- `api.unity-constructor.site` -> `/www/api.unity-constructor.site`
- `test-site-usmanova.unity-constructor.site` ->
  `/www/test-site-usmanova.unity-constructor.site`
- `teiko.unity-constructor.site` -> `/www/teiko.unity-constructor.site`
- `webassist.unity-constructor.site` ->
  `/www/webassist.unity-constructor.site`
- `web-assist.unity-constructor.site` ->
  `/www/web-assist.unity-constructor.site`
- `work-search.unity-constructor.site` ->
  `/www/work-search.unity-constructor.site`

Each created subdomain has DNS records in the `unity-constructor.site` DNS zone.
Each created subdomain has an active Let's Encrypt certificate valid until
2026-10-02 and returned HTTPS 200 during verification.
