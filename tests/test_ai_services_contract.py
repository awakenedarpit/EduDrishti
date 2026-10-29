import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
FUNCTIONS = ROOT / "supabase" / "functions"
MIGRATION = ROOT / "supabase" / "migrations" / "20261029222500_stage4_ai_learning_services.sql"


class AIServicesContractTests(unittest.TestCase):
    def test_all_endpoints_enable_jwt_verification(self):
        config = (ROOT / "supabase" / "config.toml").read_text()
        for name in ("personalized-explanation", "targeted-practice", "check-practice-answer"):
            self.assertRegex(config, rf"\[functions\.{re.escape(name)}\]\s+verify_jwt\s*=\s*true")

    def test_gemini_secret_is_server_only_and_not_put_in_url(self):
        source = "\n".join(path.read_text() for path in FUNCTIONS.rglob("*.ts"))
        self.assertIn('env("GEMINI_API_KEY")', source)
        self.assertIn('"x-goog-api-key": config.apiKey', source)
        self.assertNotRegex(source, r"\?key=|key=\$\{.*GEMINI")
        web_source = "\n".join(path.read_text() for path in (ROOT / "web" / "src").rglob("*.ts*"))
        self.assertNotIn("GEMINI_API_KEY", web_source)

    def test_database_artifacts_remain_private_and_rpc_is_service_only(self):
        sql = MIGRATION.read_text().lower()
        self.assertIn("create table private.ai_learning_activities", sql)
        self.assertIn("create table private.ai_practice_responses", sql)
        self.assertIn("revoke all on function public.store_ai_learning_activity", sql)
        self.assertIn("to service_role", sql)
        self.assertIn("revoke all on function public.get_ai_learning_activity", sql)
        self.assertIn("char_length", sql)
        self.assertIn("octet_length", sql)

    def test_practice_answer_uses_supported_postgresql_json_functions(self):
        sql = MIGRATION.read_text().lower()
        self.assertIn("jsonb_object_keys", sql)
        self.assertNotIn("jsonb_object_length", sql)

    def test_service_loads_only_own_graded_assessment_context(self):
        handler = (FUNCTIONS / "_shared" / "handler.ts").read_text()
        backend = (FUNCTIONS / "_shared" / "backend.ts").read_text()
        self.assertIn('"get_student_results"', backend)
        self.assertIn('"get_student_diagnoses"', backend)
        self.assertIn('profile?.app_role !== "student"', backend)
        self.assertIn('result.attempt.status !== "graded"', handler)
        self.assertIn('candidate.question_id === questionId', handler)

    def test_limits_timeouts_and_no_raw_free_text(self):
        handler = (FUNCTIONS / "_shared" / "handler.ts").read_text()
        gemini = (FUNCTIONS / "_shared" / "gemini.ts").read_text()
        self.assertIn("MAX_BODY_BYTES = 8_192", handler)
        self.assertIn("omitted to avoid sending free-form personal data", handler)
        self.assertIn("timeoutMs: 12_000", (FUNCTIONS / "_shared" / "backend.ts").read_text())
        self.assertIn("maxOutputTokens", gemini)
        self.assertIn("responseSchema", gemini)


if __name__ == "__main__":
    unittest.main()
