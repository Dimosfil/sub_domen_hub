# Deploy System

This project owns a small agent-friendly deploy layer for uploading build
artifacts to shared hosting by FTP or FTPS.

## Goal

- Accept a local source folder or a git repository.
- Run a project-specific build command when configured.
- Upload the selected build output to the configured hosting folder.
- Keep passwords and private deploy targets out of committed files.

## Files

- `tools/deploy/deploy-ftp.ps1` - deploy runner.
- `tools/deploy/hosting-projects.json` - legacy/subdomain target map.
- `tools/deploy/provision-subdomain.ps1` - ISPmanager subdomain helper.
- `tools/deploy/ispmanager-file-edit.mjs` - UTF-8 text-file uploader through
  ISPmanager.
- `tools/deploy/ftp.local.example.json` - safe config template.
- `tools/deploy/ftp.local.json` - local ignored config, if needed.
- `sites/root-hub/index.html` - source for the root hub page.

## Local Setup

Create `tools/deploy/ftp.local.json` from the example and set these environment
variables outside git:

```powershell
$env:SUB_DOMEN_HUB_FTP_HOST = "..."
$env:SUB_DOMEN_HUB_FTP_USER = "..."
$env:SUB_DOMEN_HUB_FTP_PASSWORD = "..."
```

Set `target.remotePath` to the hosting folder that serves the domain.

Use `build.command` when the source must be built before upload, and set
`build.outputPath` to the produced folder such as `dist`, `build`, `public`, or
another project-specific artifact directory.

## Target Modes

The hosting currently supports two deploy modes:

- `legacy` - upload into a folder under `/www/unity-constructor.site`.
- `subdomain` - upload into a separate site root under
  `/www/<subdomain>.unity-constructor.site`.

Known project targets are stored in `tools/deploy/hosting-projects.json`.
`unityconstructor` stays legacy-only. Shared folders such as `assets` and
`uploads` are not promoted to subdomains.

## Commands

Dry-run a configured deploy:

```powershell
.\tools\deploy\deploy-ftp.ps1 -DryRun
```

Deploy a local folder:

```powershell
.\tools\deploy\deploy-ftp.ps1 -SourcePath D:\path\to\source
```

Deploy a mapped project to its current folder-based path:

```powershell
.\tools\deploy\deploy-ftp.ps1 -Project webassist -DeployMode legacy
```

Deploy a mapped project to its subdomain path:

```powershell
.\tools\deploy\deploy-ftp.ps1 -Project webassist -DeployMode subdomain
```

Deploy a git repository:

```powershell
.\tools\deploy\deploy-ftp.ps1 -GitUrl https://example.com/repo.git -Ref main
```

Override the build command or output folder for one run:

```powershell
.\tools\deploy\deploy-ftp.ps1 -BuildCommand "npm ci; npm run build" -OutputPath dist
```

## Safety

The deploy script uploads and overwrites matching files. It does not delete
remote files. Use `-DryRun` before the first real upload or after changing
`remotePath`, `build.outputPath`, or exclude rules.

The current runner supports FTP and FTPS. SFTP should be added as a separate
adapter after choosing a non-interactive credential strategy such as SSH keys.

## Subdomain Provisioning

Before using a subdomain target for the first time, create the webdomain/site in
ISPmanager:

```powershell
$env:SUB_DOMEN_HUB_PANEL_USER = "..."
$env:SUB_DOMEN_HUB_PANEL_PASSWORD = "..."
.\tools\deploy\provision-subdomain.ps1 -Project webassist -DryRun
```

Run without `-DryRun` only after checking the selected project, hostname, and
document root. The helper also requests a Let's Encrypt certificate unless
`-SkipLetsEncrypt` is passed.

## Root Hub

The root site `https://unity-constructor.site/` is a static hub page with links
to both legacy folder URLs and prepared subdomain URLs. Publish it with:

```powershell
$env:SUB_DOMEN_HUB_PANEL_USER = "..."
$env:SUB_DOMEN_HUB_PANEL_PASSWORD = "..."
node .\tools\deploy\ispmanager-file-edit.mjs --local .\sites\root-hub\index.html --remote /www/unity-constructor.site/index.html --expect "Unity Constructor Hub"
```
