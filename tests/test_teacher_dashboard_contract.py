"""Static Stage 6 checks; PostgreSQL behavior is exercised by pgTAP separately."""

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
MIGRATION_PATH = ROOT / "supabase/migrations/20261031010000_stage6_teacher_dashboard.sql"
MIGRATION = MIGRATION_PATH.read_text(encoding="utf-8")
DOCS = (ROOT / "docs/teacher-dashboard-backend.md").read_text(encoding="utf-8")
PGTAP = (ROOT / "supabase/tests/teacher_dashboard.test.sql").read_text(encoding="utf-8")
TYPES = (ROOT / "web/src/lib/database.types.ts").read_text(encoding="utf-8")

PUBLIC_APIS = (
    "list_teacher_classes",
    "get_teacher_class_overview",
    "get_teacher_assessment_analytics",
    "get_teacher_misconception_heatmap",
    "get_teacher_students_needing_support",
    "get_teacher_student_learning_detail",
    "get_teacher_teaching_recommendations",
    "get_teacher_assessment_report_data",
)


def function_body(name: str) -> str:
    start = MIGRATION.index(f"CREATE FUNCTION public.{name}(")
    next_function = MIGRATION.find("CREATE FUNCTION public.", start + 1)
    end = next_function if next_function >= 0 else MIGRATION.index("REVOKE ALL ON FUNCTION", start)
    return MIGRATION[start:end]


class TeacherDashboardContractTests(unittest.TestCase):
    def test_migration_is_additive_and_exposes_all_dashboard_contracts(self):
        self.assertTrue(MIGRATION.startswith("-- Stage 6"))
        self.assertTrue(MIGRATION.rstrip().endswith("COMMIT;"))
        self.assertNotRegex(MIGRATION, r"(?im)^\s*(?:DROP\s+(?:TABLE|SCHEMA|FUNCTION|TRIGGER)|TRUNCATE\s+)")
        for name in PUBLIC_APIS:
            with self.subTest(function=name):
                self.assertIn(f"CREATE FUNCTION public.{name}(", MIGRATION)
                self.assertIn(f"{name}:", TYPES)
                self.assertIn(f"public.{name}", DOCS)

    def test_public_rpcs_are_teacher_gated_security_definers_with_fixed_paths(self):
        for name in PUBLIC_APIS:
            body = function_body(name)
            with self.subTest(function=name):
                self.assertIn("SECURITY DEFINER", body)
                self.assertIn("SET search_path = ''", body)
                self.assertIn(f"REVOKE ALL ON FUNCTION public.{name}", MIGRATION)
                self.assertIn(f"GRANT EXECUTE ON FUNCTION public.{name}", MIGRATION)
                if name == "list_teacher_classes":
                    self.assertIn("private.is_current_user_teacher()", body)
                    self.assertIn("c.teacher_id = v_user_id", body)
                else:
                    self.assertIn("private.assert_teacher_class", body)

    def test_authorization_checks_bind_assessment_and_student_to_class(self):
        self.assertIn("NOT private.owns_class(p_class_id)", MIGRATION)
        self.assertIn("a.id = p_assessment_id AND a.class_id = p_class_id", MIGRATION)
        self.assertIn("e.class_id = p_class_id AND e.student_id = p_student_id", function_body("get_teacher_student_learning_detail"))
        heatmap = function_body("get_teacher_misconception_heatmap")
        self.assertIn("JOIN public.assessments AS a ON a.id = lg.assessment_id", heatmap)
        self.assertIn("WHERE a.class_id = p_class_id", heatmap)
        self.assertIn("WHERE c.teacher_id = v_user_id", function_body("list_teacher_classes"))

    def test_metric_denominators_and_incomplete_attempt_rules_are_explicit(self):
        for term in (
            "participation_denominator",
            "active-roster learners with at least one graded attempt",
            "unfinished_attempt_count",
            "aa.status = 'graded'",
            "latest graded attempt per active learner and class assessment",
            "below_40_further_practice",
            "40_to_below_70_developing",
            "70_or_above_secure_for_now",
        ):
            with self.subTest(term=term):
                self.assertIn(term, MIGRATION)
        self.assertIn("latest **graded** attempt per active enrolled learner", DOCS)

    def test_diagnoses_and_recommendations_preserve_uncertainty_and_supportive_tone(self):
        for phrase in (
            "possible_pattern_not_confirmed",
            "candidate_interpretation",
            "not a label or conclusion",
            "insufficient_evidence",
            "candidate records",
        ):
            with self.subTest(phrase=phrase):
                self.assertIn(phrase, MIGRATION + DOCS)
        detail = function_body("get_teacher_student_learning_detail")
        self.assertIn("candidate_signal_interpretation", detail)
        self.assertNotIn("answer_config", detail)
        self.assertNotIn("r.answer", detail)

    def test_report_is_aggregate_only_and_excludes_answer_content(self):
        report = function_body("get_teacher_assessment_report_data")
        for phrase in (
            "contains_student_identifiers', false",
            "contains_submitted_answers', false",
            "contains_answer_keys', false",
            "latest graded attempt per active enrolled learner",
        ):
            with self.subTest(phrase=phrase):
                self.assertIn(phrase, report)
        self.assertNotIn("'student_id'", report)
        self.assertNotIn("answer_config", report)

    def test_pgtap_plan_covers_accuracy_empty_scope_and_security_scenarios(self):
        planned = int(re.search(r"extensions\.plan\((\d+)\)", PGTAP).group(1))
        actual = len(re.findall(r"(?im)^\s*SELECT\s+extensions\.(?:is|ok|lives_ok|throws_ok|cmp_ok|matches|like|unlike|pass|fail)\s*\(", PGTAP))
        self.assertEqual(planned, actual)
        for phrase in (
            "latest graded attempt per assessment",
            "in-progress retake",
            "repeated wrong responses are counted",
            "empty class",
            "another teacher class overview",
            "student outside the class",
            "student role cannot call",
            "candidate evidence as uncertain",
        ):
            with self.subTest(phrase=phrase):
                self.assertIn(phrase, PGTAP)


if __name__ == "__main__":
    unittest.main()
