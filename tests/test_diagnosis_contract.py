"""Static repository checks for the Stage 3 deterministic diagnosis migration."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = (ROOT / "supabase/migrations/20261028093000_stage3_misconception_engine.sql").read_text(encoding="utf-8")
PGTAP = (ROOT / "supabase/tests/diagnosis_engine.test.sql").read_text(encoding="utf-8")
DOCS = (ROOT / "docs/misconception-engine.md").read_text(encoding="utf-8")


class DiagnosisContractTests(unittest.TestCase):
    def test_only_exact_reviewed_rules_create_diagnoses(self):
        self.assertIn("rule.answer_pattern", MIGRATION)
        self.assertIn("private.answer_matches_misconception_rule(r.answer, rule.answer_pattern)", MIGRATION)
        self.assertIn("AND r.is_correct IS FALSE", MIGRATION)
        self.assertIn("AND r.is_answered", MIGRATION)
        self.assertIn("'rule_based', true", MIGRATION)
        self.assertIn("INSERT INTO public.diagnoses", MIGRATION)

    def test_rule_table_is_not_client_exposed_and_rules_are_bounded(self):
        self.assertIn("REVOKE ALL ON TABLE private.misconception_rules FROM PUBLIC, anon, authenticated", MIGRATION)
        self.assertIn("confidence numeric(4,3) NOT NULL CHECK (confidence BETWEEN 0 AND 1)", MIGRATION)
        self.assertIn("UNIQUE (question_id, misconception_code, answer_pattern)", MIGRATION)

    def test_rpc_auth_and_scopes(self):
        self.assertIn("public.get_student_diagnoses(p_attempt_id uuid)", MIGRATION)
        self.assertIn("aa.id = p_attempt_id AND aa.student_id = (SELECT auth.uid())", MIGRATION)
        self.assertIn("public.get_class_misconception_summary", MIGRATION)
        self.assertIn("NOT private.is_current_user_teacher() OR NOT private.owns_class(p_class_id)", MIGRATION)
        self.assertIn("'affected_students'", MIGRATION)
        self.assertNotIn("'student_id'", MIGRATION[MIGRATION.index("CREATE OR REPLACE FUNCTION public.get_class_misconception_summary"):])

    def test_multiple_choice_matching_is_order_independent(self):
        self.assertIn("jsonb_array_elements_text(p_answer->'selected_options')", MIGRATION)
        self.assertIn("jsonb_array_elements_text(p_pattern->'selected_options')", MIGRATION)
        self.assertIn("ON CONFLICT (source_attempt_id, topic_id, misconception_code)", MIGRATION)

    def test_migration_and_pgtap_are_transactional_and_plan_matches(self):
        planned = int(re.search(r"extensions\.plan\((\d+)\)", PGTAP).group(1))
        actual = len(re.findall(r"(?im)^\s*SELECT\s+extensions\.(?:is|ok|lives_ok|throws_ok|cmp_ok|matches|like|unlike|pass|fail)\s*\(", PGTAP))
        self.assertEqual(planned, actual)
        self.assertTrue(MIGRATION.strip().startswith("-- Stage 3"))
        self.assertTrue(MIGRATION.rstrip().endswith("COMMIT;"))
        self.assertTrue(PGTAP.strip().startswith("-- Stage 3"))
        self.assertTrue(PGTAP.rstrip().endswith("ROLLBACK;"))
        self.assertNotRegex(MIGRATION, r"(?im)^\s*(?:DROP\s+(?:TABLE|SCHEMA|FUNCTION|TRIGGER)|TRUNCATE\s+)")
        self.assertIn("unmatched incorrect response is left undiagnosed", PGTAP)
        self.assertIn("does not infer a learner's mental state from any arbitrary wrong answer", DOCS)


if __name__ == "__main__":
    unittest.main()
