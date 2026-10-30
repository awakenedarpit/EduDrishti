"""Static Stage 5 contracts; these checks do not execute PostgreSQL."""

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = (ROOT / "supabase/migrations/20261030223000_stage5_learning_progress.sql").read_text(encoding="utf-8")
PGTAP = (ROOT / "supabase/tests/learning_progress.test.sql").read_text(encoding="utf-8")


class LearningProgressContractTests(unittest.TestCase):
    def test_mastery_formula_and_thresholds_are_explicit_and_versioned(self):
        self.assertIn("'mastery-v1'", MIGRATION)
        self.assertIn("0.5::numeric", MIGRATION)
        self.assertIn("/ 90::numeric", MIGRATION)
        self.assertIn("p_evidence_units < 5", MIGRATION)
        self.assertIn("p_evidence_days < 2", MIGRATION)
        self.assertIn("p_weighted_accuracy >= 0.80", MIGRATION)
        self.assertIn("p_weighted_accuracy >= 0.60", MIGRATION)

    def test_mastery_evidence_has_a_90_day_window(self):
        self.assertRegex(MIGRATION, r"evidence\.observed_at\s*>=\s*p_as_of\s*-\s*INTERVAL '90 days'")
        self.assertIn("p_latest_evidence < p_as_of - INTERVAL '90 days'", MIGRATION)

    def test_only_answered_graded_responses_count_and_retry_attempts_remain_distinct(self):
        evidence = MIGRATION.split("CREATE OR REPLACE FUNCTION private.learning_progress_evidence", 1)[1]
        evidence = evidence.split("CREATE OR REPLACE FUNCTION private.learning_progress_diagnoses", 1)[0]
        self.assertIn("aa.status = 'graded'", evidence)
        self.assertIn("r.is_answered", evidence)
        self.assertIn("r.is_correct IS NOT NULL", evidence)
        self.assertIn("aa.id AS attempt_id", evidence)
        self.assertIn("aa.student_id", evidence)

    def test_practice_counts_only_fully_answered_activities_and_latest_item_answers(self):
        evidence = MIGRATION.split("CREATE OR REPLACE FUNCTION private.learning_progress_evidence", 1)[1]
        evidence = evidence.split("CREATE OR REPLACE FUNCTION private.learning_progress_diagnoses", 1)[0]
        self.assertIn("HAVING pg_catalog.count(item.item_key) = pg_catalog.count(answer.item_id)", evidence)
        self.assertIn("ORDER BY response.activity_id, response.item_id, response.created_at DESC", evidence)
        self.assertIn("'practice_activity'::text AS evidence_type", evidence)
        self.assertIn("pg_catalog.avg(CASE WHEN answer.is_correct", evidence)

    def test_diagnosis_signals_are_rule_based_and_separate_from_accuracy(self):
        diagnosis = MIGRATION.split("CREATE OR REPLACE FUNCTION private.learning_progress_diagnoses", 1)[1]
        diagnosis = diagnosis.split("CREATE OR REPLACE FUNCTION private.calculate_student_progress", 1)[0]
        self.assertIn("diagnosis.evidence->>'rule_based' = 'true'", diagnosis)
        self.assertIn("supported_diagnosis_count", MIGRATION)
        self.assertNotIn("diagnosis_count *", MIGRATION)

    def test_snapshots_are_idempotent_dated_and_version_tagged(self):
        self.assertIn("CREATE UNIQUE INDEX progress_records_source_snapshot_unique_idx", MIGRATION)
        self.assertIn("ON CONFLICT (", MIGRATION)
        self.assertIn("'mastery-v1'", MIGRATION)
        self.assertIn("assessment_attempt_zz_stage5_progress_snapshot", MIGRATION)
        self.assertIn("ai_practice_response_zz_stage5_progress_snapshot", MIGRATION)
        self.assertIn("Backfill versioned observations", MIGRATION)

    def test_student_apis_derive_identity_from_session(self):
        required = (
            "public.get_student_progress_overview",
            "public.get_student_topic_mastery",
            "public.get_student_assessment_history",
            "public.get_student_recent_learning_activity",
            "public.get_student_mastery_history",
            "public.get_student_progress_comparison",
        )
        for function in required:
            with self.subTest(function=function):
                self.assertIn(f"CREATE OR REPLACE FUNCTION {function}", MIGRATION)
        self.assertGreaterEqual(MIGRATION.count("IF NOT private.is_current_user_student()"), 6)
        self.assertGreaterEqual(MIGRATION.count("auth.uid()"), 6)

    def test_class_api_checks_owner_and_active_enrollment_and_omits_id_rows(self):
        start = MIGRATION.index("CREATE OR REPLACE FUNCTION public.get_class_learning_progress")
        end = MIGRATION.index("REVOKE ALL ON FUNCTION private.learning_recency_weight", start)
        function = MIGRATION[start:end]
        self.assertIn("private.is_current_user_teacher()", function)
        self.assertIn("private.owns_class(p_class_id)", function)
        self.assertIn("enrollment.status = 'active'", function)
        self.assertIn("public.get_class_learning_progress(uuid, uuid)", MIGRATION)
        self.assertNotIn("'student_id'", function)
        self.assertIn("no student identifiers are returned", function)

    def test_internal_functions_and_snapshot_writes_are_not_client_accessible(self):
        lowered = MIGRATION.lower()
        self.assertIn("revoke all on function private.calculate_student_progress", lowered)
        self.assertIn("revoke all on function private.persist_student_progress_snapshots", lowered)
        self.assertRegex(lowered, r"revoke all on function public\.get_student_progress_overview\(\) from public, anon")
        self.assertIn("grant execute on function public.get_student_progress_overview() to authenticated", lowered)
        self.assertNotRegex(lowered, r"grant\s+(?:insert|update|delete).*on\s+public\.progress_records\s+to\s+authenticated")

    def test_pg_tap_exercises_boundaries_comparisons_and_access_denials(self):
        self.assertIn("SELECT extensions.plan(40)", PGTAP)
        for label in (
            "one high score cannot overcome fewer than five evidence units",
            "evidence from one date is not enough",
            "missing evidence is represented by a null estimate rather than zero",
            "the latest repeated answer updates one completed activity score",
            "a single objective response remains insufficient",
            "assessment history preserves all repeated attempts",
            "a one-item objective is not compared as mastery",
            "history API keeps calculations explicitly versioned",
            "a different teacher cannot access another teacher class summary",
        ):
            with self.subTest(assertion=label):
                self.assertIn(label, PGTAP)
        assertion_count = len(re.findall(r"SELECT extensions\.(?:is|ok|has_column|throws_ok)\(", PGTAP))
        self.assertEqual(assertion_count, 40)

    def test_student_and_teacher_screens_are_role_gated_and_no_longer_placeholders(self):
        app = (ROOT / "web/src/App.tsx").read_text(encoding="utf-8")
        self.assertIn('path: "/progress", element: <StudentOnly><ProgressPage />', app)
        self.assertIn('path: "/teacher/analytics", element: <TeacherOnly><TeacherAnalyticsPage />', app)
        self.assertIn('getStudentProgressOverview()', (ROOT / "web/src/features/assessments/StudentDashboard.tsx").read_text())
        self.assertIn('getStudentAssessmentHistory()', (ROOT / "web/src/features/assessments/ReportsPage.tsx").read_text())
        self.assertNotIn('"/progress"', (ROOT / "web/src/features/placeholders/catalog.ts").read_text())
        self.assertNotIn('"/teacher/analytics"', (ROOT / "web/src/features/placeholders/catalog.ts").read_text())


if __name__ == "__main__":
    unittest.main()
