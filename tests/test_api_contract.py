from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = ROOT / "docs/api/openapi.yaml"
GUIDE = ROOT / "docs/frontend-integration.md"
TYPES = ROOT / "web/src/lib/api-contracts.ts"
CLIENT = ROOT / "web/src/lib/supabase.ts"


class ApiContractTests(unittest.TestCase):
    def test_openapi_covers_installed_stage6_rpc_names(self):
        spec = SPEC.read_text()
        for name in (
            "list_teacher_classes",
            "get_teacher_class_overview",
            "get_teacher_assessment_analytics",
            "get_teacher_misconception_heatmap",
            "get_teacher_students_needing_support",
            "get_teacher_student_learning_detail",
            "get_teacher_teaching_recommendations",
            "get_teacher_assessment_report_data",
        ):
            self.assertIn(f"/rest/v1/rpc/{name}:", spec)

    def test_edge_functions_are_marked_source_only(self):
        spec = SPEC.read_text()
        for name in ("personalized-explanation", "targeted-practice", "check-practice-answer"):
            segment = spec.split(f"/functions/v1/{name}:", 1)[1].split("\n  /", 1)[0]
            self.assertIn("x-deployment-status: source-defined-not-deployed", segment)

    def test_auth_and_ownership_boundaries_are_documented(self):
        guide = GUIDE.read_text()
        for text in ("Authorization: Bearer", "class ownership", "student detail additionally requires enrollment", "service-role/secret key"):
            self.assertIn(text.lower(), guide.lower())
        self.assertIn("Stage 5's source migration", guide)
        self.assertIn("get_student_diagnoses", guide)

    def test_frontend_client_never_reads_privileged_credentials(self):
        client = CLIENT.read_text()
        env_example = (ROOT / "web/.env.example").read_text()
        self.assertIn("VITE_SUPABASE_URL", client)
        self.assertIn("VITE_SUPABASE_ANON_KEY", client)
        self.assertNotRegex(client, re.compile(r"SERVICE_ROLE|SECRET_KEY|GEMINI_API_KEY", re.I))
        self.assertNotRegex(env_example, re.compile(r"SERVICE_ROLE|SECRET_KEY|GEMINI_API_KEY", re.I))
        self.assertIn("anon", env_example.lower())

    def test_shared_types_include_safe_error_and_ui_states(self):
        types = TYPES.read_text()
        self.assertIn('"unauthenticated"', types)
        self.assertIn('"rate_limited"', types)
        self.assertIn('"not_found"', types)
        for state in ("loading", "success", "empty", "error"):
            self.assertIn(f'status: "{state}"', types)

    def test_openapi_preserves_standard_supabase_auth_headers(self):
        spec = SPEC.read_text()
        self.assertIn("name: apikey", spec)
        self.assertIn("scheme: bearer", spec)
        self.assertIn("PostgrestError", spec)
        self.assertIn("EdgeError", spec)


if __name__ == "__main__":
    unittest.main()
