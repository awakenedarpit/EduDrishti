"""Sanity checks for the Stage 0 repository foundation."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class FoundationTests(unittest.TestCase):
    def test_expected_foundation_documents_exist(self):
        expected = [
            "README.md",
            "docs/architecture.md",
            "docs/development.md",
            "supabase/README.md",
            ".env.example",
            ".gitignore",
        ]
        for relative_path in expected:
            with self.subTest(path=relative_path):
                self.assertTrue((ROOT / relative_path).is_file())

    def test_environment_example_uses_placeholders(self):
        env_example = (ROOT / ".env.example").read_text(encoding="utf-8")
        self.assertIn("your-project-ref", env_example)
        self.assertIn("replace-with-your-supabase-publishable-or-anon-key", env_example)
        self.assertIn("replace-with-your-server-only-service-role-key", env_example)
        self.assertIn("replace-with-your-server-only-gemini-api-key", env_example)
        self.assertNotIn("AIza", env_example)

    def test_gitignore_excludes_local_secrets_and_build_artifacts(self):
        gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8").splitlines()
        for rule in (".env", ".env.*", "!.env.example", "node_modules/", "dist/"):
            with self.subTest(rule=rule):
                self.assertIn(rule, gitignore)

    def test_architecture_keeps_ai_keys_server_side(self):
        architecture = (ROOT / "docs/architecture.md").read_text(encoding="utf-8")
        self.assertIn("server-side secret", architecture)
        self.assertIn("service-role", architecture)
        self.assertIn("Row Level Security", architecture)


if __name__ == "__main__":
    unittest.main()
