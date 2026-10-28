import { useEffect, useState } from "react";
import { BookOpenCheck, BrainCircuit, RefreshCw } from "lucide-react";
import { Notice, EmptyState, PageHeading, StatusBadge, Surface } from "../../components/ui";
import { friendlyBackendError } from "../../lib/backend-errors";
import { supabase } from "../../lib/supabase";
import { listTeacherClasses, type TeacherClass } from "../assessments/api";

type Evidence = { prompt?: string; submitted_answer?: unknown; correct_answer?: Record<string, unknown>; explanation?: string; corrective_example?: string; followup_question?: string; rule_based?: boolean };
type Finding = { id?: string; misconception_code: string; summary: string; confidence?: number; evidence?: { matches?: Evidence[] } };
type Recent = { attempt_id: string; assessment_title: string; submitted_at: string; score_percent: number; diagnoses: Finding[] };
type ClassSummary = { diagnoses: Array<{ topic_id: string; misconception_code: string; summary: string; affected_students: number; evidence_count: number }> };

function answerText(value: unknown): string {
  if (value === null || value === undefined) return "No response";
  if (typeof value !== "object") return String(value);
  const v = value as Record<string, unknown>;
  if (typeof v.selected_option === "string") return `Option ${v.selected_option}`;
  if (Array.isArray(v.selected_options)) return `Options ${v.selected_options.join(", ")}`;
  if (typeof v.value === "string" || typeof v.value === "number") return String(v.value);
  return "Response recorded";
}

export function StudentDiagnosisPage() {
  const [items, setItems] = useState<Recent[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  async function load() {
    setLoading(true); setError(null);
    try {
      const { data, error: cause } = await supabase!.rpc("get_my_recent_diagnoses", { p_limit: 20 });
      if (cause) throw cause;
      setItems((data ?? []) as unknown as Recent[]);
    } catch (cause) { setError(friendlyBackendError(cause).message); }
    finally { setLoading(false); }
  }
  useEffect(() => { void load(); }, []);
  return <div className="page-stack">
    <PageHeading eyebrow="EVIDENCE-LINKED LEARNING" title="Diagnosis & misconceptions" description="Specific feedback appears only when your submitted answer matches a reviewed rule. Other incorrect answers are left unclassified." action={<button className="button button-secondary" onClick={() => void load()}><RefreshCw size={16}/> Refresh</button>} />
    {error && <Notice tone="error" title="Diagnosis service unavailable">{error}. The Stage 3 migration must be installed in the connected Supabase project.</Notice>}
    {loading ? <Surface><p className="muted">Loading completed diagnosis findings…</p></Surface> : !items.length ? <Surface><EmptyState title="No matched findings yet">Complete an assessment with a reviewed distractor rule to see a private, evidence-linked explanation here. An incorrect answer by itself does not create a diagnosis.</EmptyState></Surface> : items.map((attempt) => <section className="page-stack" key={attempt.attempt_id}>
      <div className="section-heading"><div><p className="eyebrow">{new Date(attempt.submitted_at).toLocaleString()}</p><h2>{attempt.assessment_title}</h2></div><StatusBadge tone="neutral">{Number(attempt.score_percent).toFixed(0)}% · server graded</StatusBadge></div>
      {attempt.diagnoses.map((finding, i) => <Surface key={finding.id ?? `${attempt.attempt_id}-${i}`} className="result-item"><div className="result-item-heading"><div className="result-item-icon"><BrainCircuit size={19}/></div><div><p className="eyebrow">{finding.misconception_code.replaceAll("_", " ")}</p><h3>{finding.summary}</h3></div><StatusBadge tone="teal">Reviewed pattern match</StatusBadge></div>
        {(finding.evidence?.matches ?? []).map((match, j) => <div className="explanation-box" key={j}><BookOpenCheck size={16}/><div>{match.prompt && <p><strong>Question:</strong> {match.prompt}</p>}<p><strong>Your answer:</strong> {answerText(match.submitted_answer)}</p>{match.explanation && <p><strong>Why:</strong> {match.explanation}</p>}{match.corrective_example && <p><strong>Try this:</strong> {match.corrective_example}</p>}{match.followup_question && <p><strong>Check your understanding:</strong> {match.followup_question}</p>}</div></div>)}
      </Surface>)}
    </section>)}
    <Notice tone="info" title="How to read these findings">Findings are deterministic matches to reviewed answer patterns, not AI-generated assessments of ability. Review them as learning prompts, not labels.</Notice>
  </div>;
}

export function TeacherMisconceptionPage() {
  const [classes, setClasses] = useState<TeacherClass[]>([]);
  const [classId, setClassId] = useState("");
  const [data, setData] = useState<ClassSummary | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { listTeacherClasses().then((rows) => { setClasses(rows); if (rows[0]) setClassId(rows[0].id); }).catch((cause) => setError(friendlyBackendError(cause).message)).finally(() => setLoading(false)); }, []);
  useEffect(() => {
    if (!classId) { setData(null); return; }
    let alive = true; setLoading(true); setError(null);
    async function loadSummary() {
      try {
        const { data: result, error: cause } = await supabase!.rpc("get_class_misconception_summary", { p_class_id: classId, p_assessment_id: null });
        if (cause) throw cause;
        if (alive) setData(result as unknown as ClassSummary);
      } catch (cause) { if (alive) setError(friendlyBackendError(cause).message); }
      finally { if (alive) setLoading(false); }
    }
    void loadSummary();
    return () => { alive = false; };
  }, [classId]);
  return <div className="page-stack">
    <PageHeading eyebrow="TEACHER WORKSPACE" title="Misconception heatmap" description="Aggregate counts from matched findings in classes you own. No student names are returned." />
    {classes.length > 0 && <Surface><label>Class<select value={classId} onChange={(event) => setClassId(event.target.value)}>{classes.map((item) => <option key={item.id} value={item.id}>{item.name} · Grade {item.grade_level}</option>)}</select></label></Surface>}
    {error && <Notice tone="error" title="Class summary unavailable">{error}. The Stage 3 migration must be installed and this teacher must own the selected class.</Notice>}
    {loading ? <Surface><p className="muted">Loading class-level matched findings…</p></Surface> : !classes.length ? <Surface><EmptyState title="No authorized classes">Create a class or ask an administrator to verify your teacher profile.</EmptyState></Surface> : !data?.diagnoses.length ? <Surface><EmptyState title="No matched findings">No reviewed-rule matches are recorded for this class yet.</EmptyState></Surface> : <Surface className="result-items">{data.diagnoses.map((item) => <article className="result-item" key={`${item.topic_id}-${item.misconception_code}`}><div className="result-item-heading"><div className="result-item-icon"><BrainCircuit size={19}/></div><div><p className="eyebrow">{item.misconception_code.replaceAll("_", " ")}</p><h3>{item.summary}</h3></div><StatusBadge tone="amber">{item.affected_students} learners</StatusBadge></div><p className="muted">{item.evidence_count} matched response{item.evidence_count === 1 ? "" : "s"} · aggregate only</p></article>)}</Surface>}
    <Notice tone="info" title="Aggregation safeguard">The service returns category counts, not learner identities or individual evidence. Only the owning teacher can query a class.</Notice>
  </div>;
}
