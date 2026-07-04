# Deploy System Specification

Last reviewed: 2026-07-04

## Purpose

`sub_domen_hub` provides an agent-operated deployment layer that can take a
local folder or git source, optionally build it, and upload the resulting files
to shared hosting.

## Current Contract

- Deploy configuration lives under `tools/deploy/`.
- `sftp.local.example.json` and `ftp.local.example.json` are safe to commit and
  store only environment variable names for credentials.
- `ftp.local.json` is ignored and may hold local deploy choices.
- `sftp.local.json` is ignored and may hold local deploy choices.
- Passwords must be supplied through environment variables or another explicit
  secret mechanism, not committed documentation.
- `deploy.ps1` is the single command entrypoint for `gi ftp`; it selects the
  local SFTP or FTP config and forwards source, git, build, project, and target
  arguments.
- `deploy-sftp.ps1` is the preferred REG.RU upload path and uses Python
  `paramiko`. Install it outside the repository with
  `python -m pip install --user paramiko` when missing.
- `deploy-ftp.ps1` supports FTP and FTPS upload.
- The deploy operation is additive/overwrite-only: it creates directories and
  uploads files, but does not delete remote files.
- The source may be a local folder or a git repository plus optional ref.
- The build command is optional and runs before file selection.
- The upload root is `build.outputPath` or an explicit `-OutputPath`.
- For this REG.RU account, SFTP uses real filesystem paths under the hosting
  account. Keep the exact private path in ignored `sftp.local.json`; ISPmanager
  and hosting maps may still use `/www/...` shorthand.
- Project deploy targets are mapped in `tools/deploy/hosting-projects.json`.
- The default deploy mode is `subdomain`; external agents should pass `-Project`
  and may omit `-DeployMode` for projects marked `subdomain-active`.
- `legacy` mode uploads to folders under `/www/unity-constructor.site`.
- `subdomain` mode uploads to separate roots under
  `/www/<subdomain>.unity-constructor.site`.
- `unityconstructor` remains legacy-only by user decision and requires
  `-DeployMode legacy`.
- The editable root hub website now lives in `D:\AI\ai-automation-studio\`.
  Its active source file is `D:\AI\ai-automation-studio\index.html`, and its
  built `dist` is published to `/www/unity-constructor.site/`.
- The root hub project-card workflow is documented in
  `docs/root-hub-project-cards.md`. New public projects deployed through
  `gi ftp` should leave pending card records in
  `docs/root-hub-project-card-inbox.md`. When the user asks to update the public
  hub, apply approved inbox records to `D:\AI\ai-automation-studio\index.html`,
  build `D:\AI\ai-automation-studio`, and publish that build through the deploy
  gateway. Keep `tools/deploy/hosting-projects.json` as the deploy target map.
- `tools/deploy/ispmanager-file-edit.mjs` can upload UTF-8 text files through
  ISPmanager `file.edit` with readback verification.

## Verification

- Use `-DryRun` to check selected files, remote path, and directory creation
  plan before a first production upload.
- Use `provision-subdomain.ps1 -DryRun` before creating a new ISPmanager
  webdomain/site.
- Provisioned subdomains should use `letsencrypt.generate` for trusted HTTPS.
  On this hosting, setting `ssl_cert=letsencrypt` via `webdomain.edit` can leave
  the webdomain on a self-signed certificate.
- A real deploy is considered complete when the script finishes with
  `Deploy completed.` and the public domain or hosting panel confirms the
  expected files.

## Gaps

- Remote cleanup/atomic releases are not implemented. They require explicit
  hosting folder and rollback rules before use.
