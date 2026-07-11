#!/usr/bin/env python3
"""Exercise concurrent full/preview lanes through one service process."""

import json
import os
import subprocess
import sys
import tempfile


binary = sys.argv[1] if len(sys.argv) > 1 else "service/target/release/typst-concealer-service"
node_count = 80
with tempfile.TemporaryDirectory(prefix="math-conceal-service-lanes-") as root:
    def request(request_id: str, lane: str | None, count: int, workers: int) -> dict:
        payload = {
            "type": "render_formulas",
            "request_id": request_id,
            "cache_key": "lane-test",
            "context_id": "lane-test",
            "context_rev": 1,
            "context_source": "",
            "root": "/tmp",
            "inputs": {},
            "output_dir": os.path.join(root, request_id),
            "ppi": 144,
            "worker_count": workers,
            "nodes": [
                {
                    "node_id": f"{request_id}:{index}",
                    "node_rev": 1,
                    "kind": "math",
                    "source": (
                        "#set page(width: auto, height: auto, margin: 0pt)\n"
                        f"$ sum_(j=1)^{20 + index % 10} j^2 + frac(alpha_{index}, beta_{index}) $"
                    ),
                }
                for index in range(count)
            ],
        }
        if lane is not None:
            payload["lane"] = lane
        return payload

    messages = [
        request("full", None, node_count, 2),
        request("preview", "preview", 1, 1),
        {"type": "shutdown"},
    ]
    result = subprocess.run(
        [binary],
        input="".join(json.dumps(message, separators=(",", ":")) + "\n" for message in messages),
        text=True,
        capture_output=True,
        check=True,
        timeout=60,
    )
    responses = [json.loads(line) for line in result.stdout.splitlines() if line]
    full = [item for item in responses if item.get("request_id") == "full"]
    preview = [item for item in responses if item.get("request_id") == "preview"]

    assert len(full) == node_count, (len(full), result.stderr)
    assert len(preview) == 1, (len(preview), result.stderr)
    preview_index = responses.index(preview[0])
    last_full_index = max(index for index, item in enumerate(responses) if item.get("request_id") == "full")
    assert preview_index < last_full_index, (preview_index, last_full_index)

print("service-lanes-ok")
