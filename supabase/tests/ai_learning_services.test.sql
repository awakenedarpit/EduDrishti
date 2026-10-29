BEGIN;
SELECT plan(12);

SELECT has_table('private', 'ai_request_buckets', 'private per-user request buckets exist');
SELECT has_table('private', 'ai_learning_activities', 'AI learning artifacts are stored in private schema');
SELECT has_table('private', 'ai_practice_responses', 'practice responses are stored in private schema');
SELECT ok(NOT has_table_privilege('anon', 'private.ai_learning_activities', 'SELECT'), 'anonymous clients cannot read AI artifacts');
SELECT ok(NOT has_table_privilege('authenticated', 'private.ai_learning_activities', 'SELECT'), 'authenticated clients cannot read private answer keys');
SELECT ok(NOT has_table_privilege('authenticated', 'private.ai_practice_responses', 'SELECT'), 'authenticated clients cannot read private practice responses');
SELECT ok(NOT has_table_privilege('service_role', 'private.ai_learning_activities', 'SELECT'), 'Edge code uses restricted RPCs rather than direct artifact table access');
SELECT ok(NOT has_function_privilege('anon', 'public.consume_ai_request(uuid,text)', 'EXECUTE'), 'anonymous clients cannot consume or probe rate limits');
SELECT ok(NOT has_function_privilege('authenticated', 'public.consume_ai_request(uuid,text)', 'EXECUTE'), 'browser sessions cannot forge rate-limit identities');
SELECT ok(has_function_privilege('service_role', 'public.consume_ai_request(uuid,text)', 'EXECUTE'), 'Edge service can consume rate limits');
SELECT ok(NOT has_function_privilege('authenticated', 'public.store_ai_learning_activity(uuid,uuid,uuid,text,jsonb,text,text)', 'EXECUTE'), 'browser sessions cannot write AI artifacts');
SELECT ok(NOT has_function_privilege('authenticated', 'public.get_ai_learning_activity(uuid,uuid)', 'EXECUTE'), 'browser sessions cannot retrieve stored answer keys');

SELECT * FROM finish();
ROLLBACK;
