"""Downloads the four AI4Bharat models (about 5-6 GB) into qbox_ai/models. Run once.

Before running:
  1. Make a free account at https://huggingface.co (email only).
  2. Open each model page below while logged in and click "Agree and access repository":
       https://huggingface.co/ai4bharat/indictrans2-en-indic-dist-200M
       https://huggingface.co/ai4bharat/indictrans2-indic-en-dist-200M
       https://huggingface.co/ai4bharat/indictrans2-indic-indic-dist-320M
       https://huggingface.co/ai4bharat/indic-conformer-600m-multilingual
  3. Settings -> Access Tokens -> Create new token -> type "Read" -> copy it.
  4. Put it in qbox_ai/.env as   HF_TOKEN=<token>   (never commit it, never paste it in chat).

Then (from the qbox_ai folder):
    .venv\\Scripts\\python download_models.py

A broken download continues where it stopped when you run it again.
The token is only needed for this download; the server itself works offline.
"""

import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
# Some routers drop Python's newer secure-connection handshake; use the classic one
# (see network_fix.cnf). Must be set before anything opens an internet connection.
os.environ.setdefault("OPENSSL_CONF", str(ROOT / "network_fix.cnf"))
# The server stays offline; only this download script goes online.
os.environ["HF_HUB_OFFLINE"] = "0"

from ai_server.config import get_settings  # noqa: E402
from ai_server.models import REPOS, model_path  # noqa: E402


def _token() -> str | None:
    token = os.environ.get("HF_TOKEN")
    env = ROOT / ".env"
    if not token and env.exists():
        for line in env.read_text(encoding="utf-8").splitlines():
            key, _, value = line.partition("=")
            if key.strip() == "HF_TOKEN":
                token = value.strip().strip('"').strip("'")
    return token or None


def main() -> int:
    from huggingface_hub import snapshot_download
    from huggingface_hub.errors import GatedRepoError, HfHubHTTPError

    token = _token()
    if not token:
        print("No HF_TOKEN found. Put HF_TOKEN=<your token> in qbox_ai/.env (see the top of this file).")
        return 1
    models_dir = get_settings().models_dir
    only = set(sys.argv[1:])  # e.g.  download_models.py speech
    for name, (repo, revision) in REPOS.items():
        if only and name not in only:
            continue
        target = model_path(models_dir, name)
        print(f"\n== {repo} -> {target}")
        try:
            snapshot_download(
                repo_id=repo,
                revision=revision,
                local_dir=target,
                token=token,
                # The translation repos hold the same weights twice; one copy is enough.
                ignore_patterns=["pytorch_model.bin", "*.md", ".gitattributes"],
                max_workers=4,
            )
        except GatedRepoError:
            print(f"Not allowed yet: open https://huggingface.co/{repo} and click 'Agree and access repository'.")
            return 1
        except HfHubHTTPError as error:
            print(f"Download problem ({error.__class__.__name__}). Run this again to continue.")
            return 1
        print("done")
    print("\nAll models are ready. Start the server:  .venv\\Scripts\\python -m uvicorn ai_server.main:app --port 8090")
    return 0


if __name__ == "__main__":
    sys.exit(main())
