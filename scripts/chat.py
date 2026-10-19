"""CLI chat against the configured OpenAI-compatible free LLM."""

from __future__ import annotations

import argparse
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


def client() -> tuple[OpenAI, str]:
    load_dotenv(ROOT / ".env")
    base_url = os.environ.get("OPENAI_BASE_URL") or "https://api.llm7.io/v1"
    api_key = os.environ.get("OPENAI_API_KEY") or "unused"
    model = os.environ.get("OPENAI_MODEL") or "codestral-latest"
    return OpenAI(base_url=base_url, api_key=api_key), model


def main() -> int:
    parser = argparse.ArgumentParser(description="Chat with the project free LLM")
    parser.add_argument("prompt", nargs="*", help="User prompt")
    parser.add_argument("--model", help="Override OPENAI_MODEL")
    args = parser.parse_args()
    prompt = " ".join(args.prompt) or "Say hello in one short sentence."

    openai_client, model = client()
    model = args.model or model
    print(f"model={model}", file=sys.stderr)

    response = openai_client.chat.completions.create(
        model=model,
        messages=[{"role": "user", "content": prompt}],
        temperature=0.2,
    )
    message = response.choices[0].message
    text = message.content or getattr(message, "reasoning_content", None) or ""
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
