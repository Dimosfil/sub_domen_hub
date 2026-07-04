# Root Hub Project Cards

This instruction is mandatory when adding, removing, or changing public project
cards for projects deployed through `gi ftp` / `tools/deploy/deploy.ps1`.

The public root hub is `https://unity-constructor.site/`.

Current split of responsibility:

- `D:\AI\sub_domen_hub\` is the deploy gateway and hosting target registry.
- `D:\AI\ai-automation-studio\` is the editable website project for the public
  root hub.
- The active public hub source file is
  `D:\AI\ai-automation-studio\index.html`.

Do not edit or publish `D:\AI\ai-automation-studio\` during a background/new
project deploy unless the user explicitly asks to update the public hub. New
project deploy agents should leave a structured pending record in this repo
instead.

## Sources Of Truth

- Deploy targets: `tools/deploy/hosting-projects.json`.
- Pending card records: `docs/root-hub-project-card-inbox.md`.
- Public hub markup: `D:\AI\ai-automation-studio\index.html`.
- Deploy/runbook notes: `docs/deploy.md`.
- Deploy behavior contract: `tools/project-memory/specs/deploy-system.md`.

`hosting-projects.json` controls where `gi ftp` uploads a mapped project. The
current public hub page does not render cards from that JSON automatically.
Agents that deploy a new public project record the desired card in the inbox
first. When the user later asks to update the public hub, apply approved inbox
entries to `D:\AI\ai-automation-studio\index.html`, build that project, and
publish the built `dist` through the configured deploy gateway.

## Card Request Inbox

When a new public project is deployed and should appear on the public hub, append
one entry to `docs/root-hub-project-card-inbox.md` using this shape:

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

Rules for agents leaving records:

- Do not put secrets, host credentials, private panel paths, logs, screenshots,
  or raw deploy output in the inbox.
- Keep one project per entry.
- Use `Status: pending` until the card is actually added to
  `D:\AI\ai-automation-studio\index.html` and published.
- If the user says the project is hidden, private, legacy-only, or shared-folder
  only, either do not add an inbox entry or mark that fact in the entry.
- Do not duplicate an existing pending entry for the same project id or public
  URL; update the existing entry when needed.

## Add A New Subdomain Project

1. Choose a stable project id for deploy commands. Use the id that agents will
   pass as `-Project`, for example `client_portal`.
2. Add the project to `tools/deploy/hosting-projects.json`:

   ```json
   {
     "id": "client_portal",
     "legacyPath": "/www/unity-constructor.site/client_portal",
     "subdomain": "client-portal.unity-constructor.site",
     "subdomainPath": "/www/client-portal.unity-constructor.site",
     "status": "subdomain-active"
   }
   ```

3. If the subdomain/site does not exist yet, run the documented provisioning
   flow from `docs/deploy.md` first with `-DryRun`, then without `-DryRun` only
   after checking hostname and document root.
4. Append a pending card request to `docs/root-hub-project-card-inbox.md`.
5. Only when the user asks to update the public hub, add a project card inside
   `D:\AI\ai-automation-studio\index.html` in `<div class="project-list">`.
6. Use this card shape:

   ```html
   <article class="project">
     <div class="project-title">
       <span class="project-icon">CP</span>
       <div>
         <h3>Client Portal</h3>
         <p>Short human description of the project.</p>
       </div>
     </div>
     <div class="links">
       <div class="link-row">
         <span class="tag ready">поддомен</span>
         <span class="url">client-portal.unity-constructor.site</span>
       </div>
     </div>
     <div class="actions">
       <a class="button dark" href="https://client-portal.unity-constructor.site/">Открыть</a>
     </div>
   </article>
   ```

7. If a legacy folder URL should remain visible, add a matching row to the
   `Legacy адреса` block:

   ```html
   <div class="legacy-row">
     <span class="legacy-name">Client Portal</span>
     <span class="url">unity-constructor.site/client_portal/</span>
     <a class="button secondary" href="/client_portal/">Открыть старый путь</a>
   </div>
   ```

8. Update the visible counters in the profile/status strip: `Поддомены` must
   match visible subdomain project cards, and `Legacy-пути` must match rows in
   the legacy block.
9. Build and publish the public hub from `D:\AI\ai-automation-studio`:

   ```powershell
   cd D:\AI\ai-automation-studio
   npm run build
   D:\AI\sub_domen_hub\tools\deploy\deploy.ps1 -SourcePath D:\AI\ai-automation-studio -BuildCommand "npm run build" -OutputPath dist
   ```

10. After successful publication, mark the inbox entry as `Status: published`
    and add a short published note with the date.

## Add A Legacy-Only Project

Use this only when the user or hosting constraint says the project must not have
a subdomain.

1. Add an entry to `tools/deploy/hosting-projects.json` with an empty
   `subdomain`, empty `subdomainPath`, and `status` set to `legacy-only`.
2. Append a pending inbox record unless the user asked to edit the public hub
   immediately.
3. When approved, add it to the `Legacy адреса` block in
   `D:\AI\ai-automation-studio\index.html`.
4. Do not add a primary card unless the user explicitly wants a legacy-only
   project promoted in the main card list.
5. Update the `Legacy-пути` counter.

Shared service folders such as `assets` and `uploads` are not project cards.
Keep them out of the main project list and leave them documented as shared
directories.

## Remove Or Hide A Project

Never delete remote hosting files or DNS records just because a card is removed.
Remote cleanup requires an explicit user request.

To remove a visible card:

1. Remove the matching `<article class="project">` from
   `D:\AI\ai-automation-studio\index.html`.
2. Decide what should happen to `tools/deploy/hosting-projects.json`: keep the
   entry if `gi ftp -Project <id>` must still work, or remove it only when the
   deploy target is intentionally retired.
3. Remove the legacy row only if the legacy address should no longer be shown.
4. Update `Поддомены` and `Legacy-пути` counters.
5. Build and publish the public hub from `D:\AI\ai-automation-studio`.

To hide a project but keep deploy working, keep its deploy-map entry and remove
only the public card/legacy row.

## Change A Card

For display-only changes, edit only the card title, icon letters, description,
URL text, and link in `D:\AI\ai-automation-studio\index.html`.

For deploy target changes, update both:

- `tools/deploy/hosting-projects.json` for the actual upload target.
- `D:\AI\ai-automation-studio\index.html` for the public visible link.

When changing a subdomain name, verify or provision the new webdomain and HTTPS
certificate before reporting success.

## Verification Checklist

Before reporting the task done:

- Run a JSON parse check for `tools/deploy/hosting-projects.json`.
- Count visible subdomain cards and legacy rows, then compare them with the
  `Поддомены` and `Legacy-пути` counters in
  `D:\AI\ai-automation-studio\index.html`.
- Check that each visible card link uses `https://` and ends with `/`.
- Build `D:\AI\ai-automation-studio`.
- Run a dry deploy when deploy configuration is available:

  ```powershell
  D:\AI\sub_domen_hub\tools\deploy\deploy.ps1 -SourcePath D:\AI\ai-automation-studio -BuildCommand "npm run build" -OutputPath dist -DryRun
  ```

- For a real publication, run the same gateway command without `-DryRun` and
  verify the public hub page after upload.

If credentials or local deploy config are missing, do not invent them and do not
print secrets. Report that the public hub source was updated and publication
still needs configured credentials.
