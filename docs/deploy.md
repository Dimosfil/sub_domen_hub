# Deploy System

This project owns a small agent-friendly deploy layer for uploading build
artifacts to shared hosting by SFTP, FTP, or FTPS.

## Goal

- Accept a local source folder or a git repository.
- Run a project-specific build command when configured.
- Upload the selected build output to the configured hosting folder.
- Keep passwords and private deploy targets out of committed files.

## Files

- `tools/deploy/deploy.ps1` - single deploy entrypoint used by `gi ftp`.
- `tools/deploy/deploy-sftp.ps1` - preferred REG.RU SFTP deploy runner.
- `tools/deploy/deploy-sftp.py` - Python/Paramiko implementation used by the
  SFTP runner.
- `tools/deploy/deploy-ftp.ps1` - legacy FTP/FTPS deploy runner.
- `tools/deploy/hosting-projects.json` - legacy/subdomain target map.
- `tools/deploy/provision-subdomain.ps1` - ISPmanager subdomain helper.
- `tools/deploy/ispmanager-file-edit.mjs` - UTF-8 text-file uploader through
  ISPmanager.
- `tools/deploy/sftp.local.example.json` - safe SFTP config template.
- `tools/deploy/ftp.local.example.json` - safe FTP/FTPS config template.
- `tools/deploy/ftp.local.json` - local ignored config, if needed.
- `tools/deploy/sftp.local.json` - local ignored SFTP config, if needed.
- `sites/root-hub/index.html` - source for the root hub page.

## Local Setup

Create `tools/deploy/sftp.local.json` from the example and set these environment
variables outside git:

```powershell
$env:SUB_DOMEN_HUB_SFTP_HOST = "..."
$env:SUB_DOMEN_HUB_SFTP_USER = "..."
$env:SUB_DOMEN_HUB_SFTP_PASSWORD = "..."
```

For the current REG.RU hosting, SFTP is preferred. The account-level SFTP root
uses a real filesystem path under the hosting account. Keep that exact path in
ignored `tools/deploy/sftp.local.json`; the hosting-panel shorthand `/www/...`
is still used in ISPmanager docs and project target maps.

FTP/FTPS remains available through `tools/deploy/deploy-ftp.ps1`. Create
`tools/deploy/ftp.local.json` from the example and set these environment
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
The default deploy mode is `subdomain`; external agents should pass `-Project`
and may omit `-DeployMode` for projects marked `subdomain-active`.
`unityconstructor` stays legacy-only and must be deployed with
`-DeployMode legacy`. Shared folders such as `assets` and `uploads` are not
promoted to subdomains.

## Commands

Dry-run a configured deploy:

```powershell
.\tools\deploy\deploy.ps1 -DryRun
```

Deploy the configured source:

```powershell
.\tools\deploy\deploy.ps1
```

Deploy a local folder:

```powershell
.\tools\deploy\deploy.ps1 -SourcePath D:\path\to\source
```

Deploy a mapped project to its default subdomain path:

```powershell
.\tools\deploy\deploy.ps1 -Project webassist
```

Deploy a mapped project to its legacy folder path:

```powershell
.\tools\deploy\deploy.ps1 -Project webassist -DeployMode legacy
```

Deploy a git repository:

```powershell
.\tools\deploy\deploy.ps1 -GitUrl https://example.com/repo.git -Ref main
```

Override the build command or output folder for one run:

```powershell
.\tools\deploy\deploy.ps1 -BuildCommand "npm ci; npm run build" -OutputPath dist
```

Deploy a mapped hosting project through the current config:

```powershell
.\tools\deploy\deploy.ps1 -Project webassist
```

## Safety

The deploy scripts upload and overwrite matching files. They do not delete
remote files. Use `-DryRun` before the first real upload or after changing
`remotePath`, `build.outputPath`, or exclude rules.

The SFTP runner uses Python `paramiko` and reads host, username, and password
from direct config values or environment variables, including Windows User
environment. Do not pass passwords in CLI arguments and do not store raw
passwords in committed files.

If `paramiko` is missing on a new machine, install it outside the repository:

```powershell
python -m pip install --user paramiko
```

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
node .\tools\deploy\ispmanager-file-edit.mjs --local .\sites\root-hub\index.html --remote /www/unity-constructor.site/index.html --expect "Когника"
```

Preferred SFTP publish command for the root hub:

```powershell
.\tools\deploy\deploy.ps1
```
