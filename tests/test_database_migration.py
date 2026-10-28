"""Static contract checks for the Stage 1 SQL migration.

These tests do not execute PostgreSQL or prove RLS behavior. The pgTAP suite
under supabase/tests/ is the database integration test suite.
"""

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
MIGRATION_PATH = ROOT / "supabase/migrations/20261028061647_stage1_database_auth_rls.sql"
MIGRATION = MIGRATION_PATH.read_text(encoding="utf-8")


class DatabaseMigrationContractTests(unittest.TestCase):
    def test_required_domain_tables_and_normalized_support_tables_exist(self):
        expected = {
            "profiles",
            "classes",
            "enrollments",
            "topics",
            "questions",
            "question_answer_keys",
            "assessments",
            "assessment_questions",
            "assessment_attempts",
            "responses",
            "diagnoses",
            "learning_sessions",
            "progress_records",
        }
        created = set(re.findall(r"CREATE TABLE public\.([a-z_]+)", MIGRATION, re.IGNORECASE))
        self.assertTrue(expected.issubset(created), expected - created)

    def test_every_public_table_has_rls_enabled(self):
        tables = re.findall(r"CREATE TABLE public\.([a-z_]+)", MIGRATION, re.IGNORECASE)
        enabled = set(re.findall(r"ALTER TABLE public\.([a-z_]+) ENABLE ROW LEVEL SECURITY", MIGRATION, re.IGNORECASE))
        self.assertEqual(set(tables), enabled)

    def test_client_grants_are_revoked_before_explicit_allowlist(self):
        revoke = MIGRATION.index("REVOKE ALL ON TABLE")
        grants = MIGRATION.index("GRANT ALL ON TABLE")
        policies = MIGRATION.index("CREATE POLICY profiles_select_self")
        self.assertLess(revoke, grants)
        self.assertLess(grants, policies)
        self.assertIn("FROM PUBLIC, anon, authenticated", MIGRATION[revoke:grants])

    def test_signup_trigger_ignores_user_supplied_role(self):
        start = MIGRATION.index("CREATE FUNCTION private.handle_new_auth_user()")
        end = MIGRATION.index("CREATE FUNCTION private.is_current_user_teacher()")
        body = MIGRATION[start:end]
        self.assertIn("VALUES (", body)
        self.assertIn("'student'", body)
        self.assertNotRegex(body, r"raw_user_meta_data\s*->>\s*'?(?:app_role|role)'?")

    def test_authenticated_users_cannot_update_profile_role_or_insert_classes(self):
        self.assertIn("GRANT UPDATE (display_name) ON public.profiles TO authenticated", MIGRATION)
        self.assertNotRegex(MIGRATION, r"GRANT\s+UPDATE\s*\([^)]*app_role")
        self.assertNotRegex(MIGRATION, r"GRANT\s+INSERT\s+ON\s+public\.classes\s+TO\s+authenticated")
        self.assertIn("CREATE FUNCTION public.create_class(", MIGRATION)
        self.assertIn("VALUES ((SELECT auth.uid()), p_name", MIGRATION)

    def test_sensitive_writes_use_scoped_functions_or_server_role(self):
        for function in (
            "public.enroll_student",
            "public.start_assessment",
            "public.save_response",
            "public.submit_assessment",
        ):
            with self.subTest(function=function):
                self.assertIn(f"CREATE FUNCTION {function}(", MIGRATION)
        self.assertIn("GRANT SELECT ON public.assessment_attempts, public.responses, public.diagnoses,", MIGRATION)
        self.assertNotRegex(MIGRATION, r"GRANT\s+(?:INSERT|UPDATE|DELETE).*?ON\s+public\.(?:responses|diagnoses|learning_sessions|progress_records)\s+TO\s+authenticated")

    def test_answer_keys_are_not_part_of_question_rows_or_student_read_policy(self):
        question_table = MIGRATION.split("CREATE TABLE public.questions (", 1)[1].split("CREATE TABLE public.question_answer_keys", 1)[0]
        self.assertNotIn("answer_config", question_table)
        self.assertIn("CREATE POLICY question_answer_keys_select_author", MIGRATION)
        self.assertIn("USING (private.is_question_author(question_id))", MIGRATION)

    def test_migration_contains_no_destructive_schema_statements(self):
        self.assertNotRegex(MIGRATION, r"(?im)^\s*(DROP\s+(?:TABLE|SCHEMA|FUNCTION|TRIGGER)|TRUNCATE\s+)")

    def test_supabase_config_does_not_expose_private_schema(self):
        config = (ROOT / "supabase/config.toml").read_text(encoding="utf-8")
        self.assertIn('schemas = ["public", "graphql_public"]', config)
        self.assertNotIn('"private"', config)


if __name__ == "__main__":
    unittest.main()
