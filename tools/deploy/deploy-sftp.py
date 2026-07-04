#!/usr/bin/env python
import argparse
import fnmatch
import json
import os
import posixpath
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import paramiko


SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent


def env_value(name):
    value = os.environ.get(name)
    if value:
        return value
    if os.name != "nt":
        return None
    try:
        import winreg

        for root, key in (
            (winreg.HKEY_CURRENT_USER, "Environment"),
            (
                winreg.HKEY_LOCAL_MACHINE,
                r"SYSTEM\CurrentControlSet\Control\Session Manager\Environment",
            ),
        ):
            try:
                with winreg.OpenKey(root, key) as handle:
                    value, _ = winreg.QueryValueEx(handle, name)
                    if value:
                        return value
            except FileNotFoundError:
                continue
            except OSError:
                continue
    except Exception:
        return None
    return None


def resolve_path(value, base):
    path = Path(value)
    if path.is_absolute():
        return path.resolve()
    return (base / path).resolve()


def run(command, cwd):
    if not command:
        return
    print(f"Running build command in {cwd}")
    completed = subprocess.run(
        ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", command],
        cwd=cwd,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(f"Build command failed with exit code {completed.returncode}.")


def create_workspace(source_path, git_url, ref):
    if git_url:
        temp_root = Path(tempfile.mkdtemp(prefix="sub-domen-hub-deploy-"))
        command = ["git", "clone", "--depth", "1"]
        if ref:
            command += ["--branch", ref]
        command += [git_url, str(temp_root)]
        subprocess.run(command, cwd=PROJECT_ROOT, check=True)
        return temp_root, True
    if not source_path:
        raise RuntimeError("Source path or Git URL is required.")
    return resolve_path(source_path, PROJECT_ROOT), False


def is_excluded(relative_path, patterns):
    normalized = relative_path.replace("\\", "/")
    for pattern in patterns:
        pattern = pattern.replace("\\", "/")
        if fnmatch.fnmatch(normalized, pattern):
            return True
        folder_pattern = pattern.rstrip("/").rstrip("*").rstrip("/")
        if folder_pattern and normalized.startswith(folder_pattern + "/"):
            return True
    return False


def collect_files(root, exclude_patterns):
    files = []
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(root).as_posix()
        if is_excluded(relative, exclude_patterns):
            continue
        files.append(
            {
                "full": path,
                "relative": relative,
                "size": path.stat().st_size,
            }
        )
    return files


def remote_join(base, relative="."):
    if not relative or relative == ".":
        relative = ""
    return "/" + "/".join(
        part
        for part in (base.strip("/") + "/" + relative.strip("/")).split("/")
        if part
    )


def read_project_map(config, config_path):
    map_path = config.get("projectMapPath") or "hosting-projects.json"
    map_file = Path(map_path)
    if not map_file.is_absolute():
        map_file = config_path.parent / map_file
    with map_file.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def rewrite_remote_path(remote_path, target):
    rewritten = remote_path
    for rule in target.get("pathRewrites") or []:
        source = (rule.get("from") or "").rstrip("/")
        destination = (rule.get("to") or "").rstrip("/")
        if source and destination and (rewritten == source or rewritten.startswith(source + "/")):
            rewritten = destination + rewritten[len(source) :]
            break
    return rewritten


def resolve_project_remote_path(config, config_path, target, project_id, deploy_mode):
    if not project_id:
        return None
    project_map = read_project_map(config, config_path)
    selected_mode = resolve_deploy_mode(config, config_path, deploy_mode)
    project = next((item for item in project_map.get("projects", []) if item.get("id") == project_id), None)
    if not project:
        known = ", ".join(item.get("id", "") for item in project_map.get("projects", []))
        raise RuntimeError(f"Unknown deploy project '{project_id}'. Known projects: {known}.")
    path_key = "legacyPath" if selected_mode == "legacy" else "subdomainPath"
    remote_path = project.get(path_key)
    if not remote_path:
        raise RuntimeError(
            f"Project '{project_id}' has no '{selected_mode}' deploy path. Status: {project.get('status', '')}."
        )
    return rewrite_remote_path(remote_path, target)


def resolve_deploy_mode(config, config_path, deploy_mode):
    if deploy_mode:
        return deploy_mode
    if config.get("deployMode"):
        return config["deployMode"]
    project_map = read_project_map(config, config_path)
    return project_map.get("defaultMode") or "legacy"


def prepare_artifact_root(upload_root, project_id, deploy_mode):
    if not project_id or deploy_mode != "subdomain":
        return upload_root, None

    legacy_prefix = f"/{project_id.strip('/')}/"
    rewrite_suffixes = {".html", ".htm", ".js", ".mjs", ".css", ".json", ".webmanifest", ".svg"}
    matching_files = []
    for path in upload_root.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in rewrite_suffixes:
            continue
        try:
            if legacy_prefix in path.read_text(encoding="utf-8"):
                matching_files.append(path)
        except UnicodeDecodeError:
            continue

    if not matching_files:
        return upload_root, None

    prepared_root = Path(tempfile.mkdtemp(prefix="sub-domen-hub-artifact-"))
    shutil.copytree(upload_root, prepared_root, dirs_exist_ok=True)
    for path in prepared_root.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in rewrite_suffixes:
            continue
        try:
            content = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        if legacy_prefix in content:
            path.write_text(content.replace(legacy_prefix, "/"), encoding="utf-8")

    print(f"Rewrote legacy base path {legacy_prefix} to / for subdomain deploy.")
    return prepared_root, prepared_root


def mkdir_p(sftp, remote_dir):
    current = ""
    for part in [part for part in remote_dir.split("/") if part]:
        current = posixpath.join(current, part)
        target = "/" + current
        try:
            sftp.mkdir(target)
        except OSError:
            pass


def deploy(config, config_path, args):
    source_config = config.get("source") or {}
    build_config = config.get("build") or {}
    target = config.get("target") or {}

    source_path = args.source or source_config.get("path")
    git_url = args.git_url or source_config.get("gitUrl")
    ref = args.ref or source_config.get("ref")
    build_command = args.build_command if args.build_command is not None else build_config.get("command")
    output_path = args.output_path or build_config.get("outputPath") or "."
    selected_deploy_mode = resolve_deploy_mode(config, config_path, args.deploy_mode)
    project_remote_path = resolve_project_remote_path(config, config_path, target, args.project, selected_deploy_mode)
    remote_path = args.remote_path or project_remote_path or target.get("remotePath")
    exclude = config.get("exclude") or []

    if not remote_path:
        raise RuntimeError("Remote path is required.")

    workspace = None
    temporary = False
    try:
        workspace, temporary = create_workspace(source_path, git_url, ref)
        if not args.skip_build:
            run(build_command, workspace)
        upload_root = resolve_path(output_path, workspace)
        if not upload_root.is_dir():
            raise RuntimeError(f"Build output folder does not exist: {upload_root}")
        upload_root, prepared_root = prepare_artifact_root(upload_root, args.project, selected_deploy_mode)
        files = collect_files(upload_root, exclude)
        if not files:
            raise RuntimeError(f"No files selected for upload from {upload_root}.")
        total = sum(file["size"] for file in files)
        print(f"Deploy source: {workspace}")
        print(f"Upload root: {upload_root}")
        print(f"Remote path: {remote_path}")
        print(f"Selected files: {len(files)}, bytes: {total}")

        directories = {remote_join(remote_path)}
        for file in files:
            directories.add(remote_join(remote_path, posixpath.dirname(file["relative"])))

        if args.dry_run:
            for directory in sorted(directories, key=len):
                print(f"[dry-run] ensure remote directory {directory}")
            for file in files:
                print(f"[dry-run] upload {file['relative']} -> {remote_join(remote_path, file['relative'])}")
            print("Dry run completed.")
            return

        password_env = target.get("passwordEnv")
        password = env_value(password_env) if password_env else target.get("password")
        host_env = target.get("hostEnv")
        username_env = target.get("usernameEnv")
        host = env_value(host_env) if host_env else target.get("host")
        username = env_value(username_env) if username_env else target.get("username")
        if not host:
            raise RuntimeError("SFTP host is required.")
        if not username:
            raise RuntimeError("SFTP username is required.")
        if not password:
            raise RuntimeError(f"Required environment variable is missing or empty: {password_env} (SFTP password).")

        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            hostname=host,
            port=int(target.get("port") or 22),
            username=username,
            password=password,
            timeout=20,
            banner_timeout=20,
            auth_timeout=20,
        )
        try:
            sftp = client.open_sftp()
            try:
                for directory in sorted(directories, key=len):
                    mkdir_p(sftp, directory)
                for file in files:
                    destination = remote_join(remote_path, file["relative"])
                    sftp.put(str(file["full"]), destination)
                    print(f"Uploaded {file['relative']}")
            finally:
                sftp.close()
        finally:
            client.close()
        print("Deploy completed.")
    finally:
        if "prepared_root" in locals() and prepared_root and prepared_root.exists():
            shutil.rmtree(prepared_root, ignore_errors=True)
        if temporary and workspace and workspace.exists():
            shutil.rmtree(workspace, ignore_errors=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=str(SCRIPT_DIR / "sftp.local.json"))
    parser.add_argument("--source")
    parser.add_argument("--git-url")
    parser.add_argument("--ref")
    parser.add_argument("--build-command")
    parser.add_argument("--output-path")
    parser.add_argument("--project")
    parser.add_argument("--deploy-mode", choices=["legacy", "subdomain"])
    parser.add_argument("--remote-path")
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    config_path = resolve_path(args.config, PROJECT_ROOT)
    with config_path.open("r", encoding="utf-8") as handle:
        config = json.load(handle)
    deploy(config, config_path, args)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(error, file=sys.stderr)
        sys.exit(1)
