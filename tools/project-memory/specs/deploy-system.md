# Deploy System Specification

Last reviewed: 2026-07-04

## Purpose

`sub_domen_hub` provides an agent-operated deployment layer that can take a
local folder or git source, optionally build it, and upload the resulting files
to shared hosting.

## Current Contract

- Deploy configuration lives under `tools/deploy/`.
- `ftp.local.example.json` is safe to commit and stores only environment
  variable names for credentials.
- `ftp.local.json` is ignored and may hold local deploy choices.
- Passwords must be supplied through environment variables or another explicit
  secret mechanism, not committed documentation.
- `deploy-ftp.ps1` supports FTP and FTPS upload.
- The deploy operation is additive/overwrite-only: it creates directories and
  uploads files, but does not delete remote files.
- The source may be a local folder or a git repository plus optional ref.
- The build command is optional and runs before file selection.
- The upload root is `build.outputPath` or an explicit `-OutputPath`.
- Project deploy targets are mapped in `tools/deploy/hosting-projects.json`.
- `legacy` mode uploads to folders under `/www/unity-constructor.site`.
- `subdomain` mode uploads to separate roots under
  `/www/<subdomain>.unity-constructor.site`.
- `unityconstructor` remains legacy-only by user decision.
- The root hub page source lives in `sites/root-hub/index.html` and is
  published to `/www/unity-constructor.site/index.html`.
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

- SFTP is not implemented yet. Add it as a separate adapter after deciding
  whether the hosting account will use SSH keys or a trusted local client.
- Remote cleanup/atomic releases are not implemented. They require explicit
  hosting folder and rollback rules before use.
