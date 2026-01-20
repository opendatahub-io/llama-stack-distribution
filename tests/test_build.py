#!/usr/bin/env python3
import sys
from pathlib import Path
import subprocess
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from distribution import build  # noqa: E402


class GetDependenciesTests(unittest.TestCase):
    def test_get_dependencies_transforms_and_groups(self) -> None:
        fake_stdout = "\n".join(
            [
                "uv pip install pillow 'fastapi==1.0' aiosqlite 'pymilvus>=2.4.10'",
                "uv pip install 'pymilvus==2.4.1'",
                "uv pip install 'llama_stack_provider_ragas.extra==0.5.1'",
                "uv pip install --extra-index-url https://download.pytorch.org/whl/cu121 'torch==2.2.0'",
                "uv pip install sentence-transformers --no-deps",
                "uv pip install --no-deps 'llama-stack-client==1.2.3'",
                "uv pip install --no-cache 'somepkg>=1.0'",
                "uv pip install 'llama_stack_provider_lmeval==0.4.2'",
            ]
        )
        completed = subprocess.CompletedProcess(
            args=["llama", "stack", "list-deps", "--format", "uv"],
            returncode=0,
            stdout=fake_stdout,
            stderr="",
        )

        with mock.patch(
            "distribution.build.subprocess.run", return_value=completed
        ) as run:
            deps = build.get_dependencies()

        run.assert_called_once()

        # Pinned deps must be first.
        first_line = deps.splitlines()[0]
        self.assertTrue(
            first_line.startswith("RUN uv pip install --prerelease=allow --upgrade"),
            msg=first_line,
        )

        # Verify conversions are applied.
        self.assertIn("pymilvus[milvus-lite]==2.4.1", deps)
        self.assertIn("llama_stack_provider_ragas[extra]==0.5.1", deps)

        # Quote rules are enforced by list-deps --format uv (per upstream):
        # quoted: contains comparison operators or equals; unquoted: plain names.
        self.assertIn("pillow", deps)
        self.assertIn("sentence-transformers --no-deps", deps)
        self.assertIn("'pymilvus[milvus-lite]>=2.4.10'", deps)
        self.assertIn("'llama_stack_provider_lmeval==0.4.2'", deps)

        # Verify special flags are preserved.
        self.assertIn("--extra-index-url https://download.pytorch.org/whl/cu121", deps)
        self.assertIn("--no-deps 'llama-stack-client==1.2.3'", deps)
        self.assertIn("--no-cache 'somepkg>=1.0'", deps)

        # Ensure each install command uses prerelease allow.
        for line in deps.splitlines():
            if line.startswith("RUN uv pip install"):
                self.assertIn("--prerelease=allow", line)


if __name__ == "__main__":
    unittest.main()
