"""Download W1/W2/W3 models via direct Hugging Face HTTP streaming.

Use this when huggingface_hub stalls on Windows/Xet. The model catalog and
profile selection mirror drivers/download_models.py in this cleaned repo.
"""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path
from time import sleep
from time import monotonic

import requests

from download_models import (
    MODEL_LIST_12GB,
    MODEL_LIST_24GB,
    final_dest,
    load_token,
)


def curl_download(url: str, dest_file: Path, token: str | None) -> None:
    temp_file = dest_file.with_suffix(dest_file.suffix + ".part")
    curl_bin = shutil.which("curl.exe") or shutil.which("curl")
    if not curl_bin:
        raise RuntimeError("curl executable not found")

    cmd = [
        curl_bin,
        "--location",
        "--continue-at",
        "-",
        "--fail",
        "--retry",
        "8",
        "--retry-all-errors",
        "--http1.1",
        "--output",
        str(temp_file),
    ]
    if token:
        cmd.extend(["-H", f"Authorization: Bearer {token}"])
    cmd.append(url)

    subprocess.run(cmd, check=True)
    temp_file.replace(dest_file)


def stream_download(url: str, dest_file: Path, token: str | None) -> None:
    headers = {}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    headers["Accept-Encoding"] = "identity"
    headers["User-Agent"] = "comfyui-2d-character-pipeline-downloader/1.0"

    temp_file = dest_file.with_suffix(dest_file.suffix + ".part")
    downloaded = temp_file.stat().st_size if temp_file.exists() else 0
    total = 0
    last_report = monotonic()
    retries = 0
    max_retries = 8

    while True:
        req_headers = dict(headers)
        if downloaded:
            req_headers["Range"] = f"bytes={downloaded}-"

        try:
            with requests.get(
                url,
                headers=req_headers,
                stream=True,
                timeout=(30, 300),
                allow_redirects=True,
            ) as resp:
                resp.raise_for_status()

                if downloaded and resp.status_code == 200:
                    # Server ignored Range; restart from scratch rather than
                    # corrupting the partial file by appending duplicate bytes.
                    temp_file.unlink(missing_ok=True)
                    downloaded = 0
                    total = 0
                    continue

                if not total:
                    content_range = resp.headers.get("Content-Range", "")
                    if "/" in content_range:
                        total = int(content_range.rsplit("/", 1)[1])
                    else:
                        total = downloaded + int(resp.headers.get("Content-Length", "0") or "0")

                with temp_file.open("ab" if downloaded else "wb", buffering=0) as fh:
                    for chunk in resp.iter_content(chunk_size=8 * 1024 * 1024):
                        if not chunk:
                            continue
                        fh.write(chunk)
                        downloaded += len(chunk)
                        now = monotonic()
                        if total and (now - last_report >= 0.5 or downloaded == total):
                            pct = downloaded * 100 / total
                            print(
                                f"    {pct:5.1f}%  {downloaded / (1024**3):.2f}/{total / (1024**3):.2f} GB",
                                end="\r",
                                flush=True,
                            )
                            last_report = now
                        elif not total and now - last_report >= 0.5:
                            print(f"    {downloaded / (1024**3):.2f} GB", end="\r", flush=True)
                            last_report = now

                retries = 0
                if not total or downloaded >= total:
                    break

        except (requests.exceptions.ChunkedEncodingError, requests.exceptions.ConnectionError, requests.exceptions.Timeout) as exc:
            retries += 1
            if retries > max_retries:
                raise RuntimeError(
                    f"download failed after {max_retries} retries at {downloaded} bytes"
                ) from exc
            print(
                f"\n    connection interrupted at {downloaded / (1024**3):.2f} GB; "
                f"retry {retries}/{max_retries}",
                flush=True,
            )
            sleep(min(5 * retries, 30))

    if total:
        print(f"    100.0%  {downloaded / (1024**3):.2f}/{total / (1024**3):.2f} GB", flush=True)
    else:
        print(f"    {downloaded / (1024**3):.2f} GB", flush=True)
    temp_file.replace(dest_file)


def download_one(repo_id: str, filename_in_repo: str, dest_folder: Path, size: str, token: str | None, dest_name: str | None) -> None:
    dest_file = final_dest(dest_folder, filename_in_repo, dest_name)
    if dest_file.exists():
        print(f"  [skip]  {dest_file.name}  (already exists)")
        return

    dest_folder.mkdir(parents=True, exist_ok=True)
    url = f"https://huggingface.co/{repo_id}/resolve/main/{filename_in_repo}"
    print(f"  [download]  {dest_file.name}  ({size})")
    print(f"              from {url}")
    prefer_curl = os.name == "nt" and (shutil.which("curl.exe") or shutil.which("curl"))
    if prefer_curl:
        print("              transport: curl resume")
        try:
            curl_download(url, dest_file, token)
        except Exception as exc:
            print(f"    curl path failed ({exc}); falling back to requests")
            stream_download(url, dest_file, token)
    else:
        stream_download(url, dest_file, token)
    print(f"  [done]  {dest_file}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Download W1/W2/W3 models via direct HTTP")
    parser.add_argument("--comfyui-root", required=True, help="Path to your ComfyUI installation")
    parser.add_argument("--w1", action="store_true", help="Download W1 models")
    parser.add_argument("--w2", action="store_true", help="Download W2 models")
    parser.add_argument("--w3", action="store_true", help="Download W3 models")
    parser.add_argument("--all", action="store_true", help="Download all W1/W2/W3 models")
    parser.add_argument("--profile", choices=("24gb", "12gb"), default=os.environ.get("CG_MODEL_PROFILE", "24gb"))
    parser.add_argument("--token", default=None, help="Hugging Face token")
    args = parser.parse_args()

    comfyui_root = Path(args.comfyui_root).expanduser().resolve()
    models_dir = comfyui_root / "models"
    if not models_dir.exists():
        raise SystemExit(f"models directory not found: {models_dir}")

    if args.all:
        workflows = {"W1", "W2", "W3"}
    else:
        workflows = set()
        if args.w1:
            workflows.add("W1")
        if args.w2:
            workflows.add("W2")
        if args.w3:
            workflows.add("W3")
        if not workflows:
            raise SystemExit("Choose --all and/or one of --w1 --w2 --w3")

    token = load_token(args.token)
    if token:
        print(f"  Using HF token: {token[:8]}{'*' * max(0, len(token) - 8)}")

    model_list = MODEL_LIST_12GB if args.profile == "12gb" else MODEL_LIST_24GB
    targets = [m for m in model_list if m[0] in workflows]

    print(f"\nDownloading {len(targets)} file(s) for workflows: {', '.join(sorted(workflows))}")
    print(f"  profile: {args.profile}\n")

    for wf, repo, fname, folder, size, dest_name in targets:
        download_one(repo, fname, models_dir / folder, size, token, dest_name)

    print("\nAll done.")
    print(f"Models are in: {models_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
