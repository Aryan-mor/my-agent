"""List live models from the configured OpenAI-compatible endpoint."""

from __future__ import annotations

import os
import sys
from pathlib import Path

from openai import OpenAI

ROOT = Path(__file__).resolve().parents[1]


def load_dotenv(path: Path) -> None:
    if not path.exists():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = value.strip().strip('"').strip("'")
        if value:  # empty values in .env are ignored
            os.environ.setdefault(key.strip(), value)


def main() -> int:
    load_dotenv(ROOT / ".env")
    base_url = os.environ.get("OPENAI_BASE_URL") or "https://api.llm7.io/v1"
    api_key = os.environ.get("OPENAI_API_KEY") or "unused"
    client = OpenAI(base_url=base_url, api_key=api_key)
    models = client.models.list()
    print(f"endpoint={base_url}", file=sys.stderr)
    for model in models.data:
        extra = []
        tier = getattr(model, "tier", None)
        tools = getattr(model, "tools_calling", None)
        if tier:
            extra.append(str(tier))
        if tools:
            extra.append("tools")
        suffix = f"  [{', '.join(extra)}]" if extra else ""
        print(f"{model.id}{suffix}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
