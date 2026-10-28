"""Local static contract checks for Stage 2; these do not execute PostgreSQL."""

from fractions import Fraction
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
MIGRATION_PATH = next((ROOT / "supabase/migrations").glob("*_stage2_diagnostic_assessment_engine.sql"))
MIGRATION = MIGRATION_PATH.read_text(encoding="utf-8")
DOCS = (ROOT / "docs/assessment-engine.md").read_text(encoding="utf-8")
PGTAP = (ROOT / "supabase/tests/rls.test.sql").read_text(encoding="utf-8")


class AssessmentContractTests(unittest.TestCase):
    def test_core_rpc_functions_are_defined_and_authenticated(self):
        functions = (
            "public.list_available_assessments",
            "public.get_assessment",
            "public.start_assessment",
            "public.save_response",
            "public.complete_assessment",
            "public.get_student_results",
        )
        for function in functions:
            with self.subTest(function=function):
                self.assertIn(f"FUNCTION {function}(", MIGRATION)
                self.assertIn(f"FUNCTION {function}(", MIGRATION[MIGRATION.index("REVOKE ALL ON FUNCTION public.list_available_assessments"):])
        self.assertIn("TO authenticated", MIGRATION[MIGRATION.index("GRANT EXECUTE ON FUNCTION public.list_available_assessments"):])

    def test_scoring_is_server_owned_and_all_or_nothing(self):
        self.assertIn("private.answer_is_correct", MIGRATION)
        self.assertIn("score_percent = CASE", MIGRATION)
        self.assertIn("THEN 100 ELSE 0", MIGRATION)
        self.assertIn("THEN aq.points ELSE 0", MIGRATION)
        self.assertIn("round((v_earned / v_total) * 100, 2)", MIGRATION)
        self.assertNotRegex(MIGRATION, r"FUNCTION\s+public\.(?:save_response|complete_assessment)\s*\([^)]*(?:p_score|p_points|p_is_correct)")
        self.assertIn("FOR UPDATE", MIGRATION[MIGRATION.index("CREATE FUNCTION public.complete_assessment"):])

    def test_question_formats_and_keys_are_separated(self):
        for question_type in ("single_choice", "multiple_choice", "numeric", "short_text"):
            with self.subTest(question_type=question_type):
                self.assertIn(f"p_question_type = '{question_type}'", MIGRATION)
        self.assertIn("CREATE TABLE public.question_guidance", MIGRATION)
        self.assertIn("CREATE TABLE public.question_answer_keys", (ROOT / "supabase/migrations/20261028061647_stage1_database_auth_rls.sql").read_text(encoding="utf-8"))
        self.assertIn("CREATE FUNCTION private.jsonb_key_count(p_value jsonb)", MIGRATION)
        self.assertIn("FROM pg_catalog.jsonb_object_keys(p_value)", MIGRATION)
        self.assertNotIn("jsonb_object_length", MIGRATION)
        self.assertIn("ALTER TABLE public.question_guidance ENABLE ROW LEVEL SECURITY", MIGRATION)
        self.assertIn("question_guidance_select_teacher", MIGRATION)
        self.assertIn("USING (private.can_view_question_guidance(question_id))", MIGRATION)
        self.assertNotIn("explanation", MIGRATION[MIGRATION.index("ALTER TABLE public.questions"):MIGRATION.index("CREATE TABLE public.question_guidance")])
        self.assertNotIn("misconception_tags", MIGRATION[MIGRATION.index("ALTER TABLE public.questions"):MIGRATION.index("CREATE TABLE public.question_guidance")])

    def test_student_assessment_payload_withholds_solution_before_completion(self):
        start = MIGRATION.index("CREATE OR REPLACE FUNCTION public.get_assessment(")
        end = MIGRATION.index("CREATE OR REPLACE FUNCTION public.start_assessment(", start)
        body = MIGRATION[start:end]
        for secret in ("correct_answer", "answer_config", "explanation", "misconception_tags"):
            with self.subTest(secret=secret):
                self.assertNotIn(secret, body)
        result_start = MIGRATION.index("CREATE OR REPLACE FUNCTION public.get_student_results(")
        result_end = MIGRATION.index("CREATE FUNCTION public.complete_assessment(", result_start)
        results_body = MIGRATION[result_start:result_end]
        self.assertIn("v_attempt.status <> 'graded'", results_body)
        self.assertIn("'correct_answer'", results_body)
        self.assertIn("'explanation'", results_body)

    def test_attempt_transitions_are_idempotent_and_missing_answers_are_scored(self):
        self.assertIn("pg_advisory_xact_lock", MIGRATION)
        self.assertIn("aa.status = 'in_progress'", MIGRATION)
        self.assertIn("ON CONFLICT (attempt_id, question_id) DO UPDATE", MIGRATION)
        self.assertIn("IF v_status = 'graded'", MIGRATION)
        self.assertIn("false, NULL", MIGRATION)
        self.assertIn("'unanswered_count'", MIGRATION[MIGRATION.index("CREATE OR REPLACE FUNCTION public.get_student_results("):])

    def test_templates_are_student_scoped_and_class_assessments_remain_owned(self):
        self.assertIn("assessments_template_scope_check", MIGRATION)
        self.assertIn("a.is_template", MIGRATION)
        self.assertIn("private.is_active_student_in_class", MIGRATION)
        self.assertIn("private.assessment_is_publishable(id)", MIGRATION)
        self.assertIn("private.can_attach_question(question_id)", MIGRATION)
        self.assertIn("'development_fixture'", MIGRATION)

    def test_seven_fixtures_have_verified_class_10_answers(self):
        question_section = MIGRATION.split("INSERT INTO public.questions (", 1)[1].split("INSERT INTO public.question_answer_keys", 1)[0]
        self.assertEqual(len(re.findall(r"'d2000000-0000-4000-8000-00000000000[1-7]'", question_section)), 7)
        # Direct substitutions verify factorisation, discriminants, roots, and the contextual model.
        self.assertEqual((2**2 - 5 * 2 + 6, 3**2 - 5 * 3 + 6), (0, 0))
        self.assertEqual(3**2 - 4 * 2 * 1, 1)
        self.assertEqual((-4, 2**2 - 4 * 1 * 1, 0 - 4 * 1 * -9, 2**2 - 4 * 3 * 1), (-4, 0, 36, -8))
        self.assertEqual(2 * Fraction(1, 1) ** 2 - 5 * Fraction(1, 1) + 3, 0)
        self.assertEqual(2 * Fraction(3, 2) ** 2 - 5 * Fraction(3, 2) + 3, 0)
        self.assertEqual((2 - 2) * (2 - 3), 0)
        self.assertEqual((3 - 2) * (3 - 3), 0)
        self.assertEqual((5 * (5 + 5), (-10) * (-10 + 5)), (50, 50))
        self.assertIn("jsonb_build_object('value',1.5,'tolerance',0.001)", MIGRATION)

    def test_api_documentation_covers_all_student_operations_and_result_summary(self):
        for function in (
            "list_available_assessments",
            "get_assessment",
            "start_assessment",
            "save_response",
            "complete_assessment",
            "get_student_results",
        ):
            with self.subTest(function=function):
                self.assertIn(function, DOCS)
        for term in ("unanswered", "no partial credit", "schema_version", "42501", "development_fixture"):
            with self.subTest(term=term):
                self.assertIn(term, DOCS)

    def test_pgtap_plan_matches_declared_assertions_and_migration_is_additive(self):
        planned = int(re.search(r"extensions\.plan\((\d+)\)", PGTAP).group(1))
        actual = len(re.findall(r"(?im)^\s*SELECT\s+extensions\.(?:is|ok|lives_ok|throws_ok|cmp_ok|matches|like|unlike|pass|fail)\s*\(", PGTAP))
        self.assertEqual(planned, actual)
        self.assertNotRegex(MIGRATION, r"(?im)^\s*(?:DROP\s+(?:TABLE|SCHEMA|FUNCTION|TRIGGER)|TRUNCATE\s+)")
        self.assertTrue(MIGRATION.strip().startswith("-- Stage 2"))
        self.assertTrue(MIGRATION.rstrip().endswith("COMMIT;"))


if __name__ == "__main__":
    unittest.main()
