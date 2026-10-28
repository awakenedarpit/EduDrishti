import { useEffect, useState } from "react";
import { ArrowRight, Clock3, FileCheck2 } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { EmptyState, Notice, PageHeading, StatusBadge, Surface } from "../../components/ui";
import { friendlyBackendError } from "../../lib/backend-errors";
import { listAvailableAssessments, startAssessment, type AssessmentSummary } from "./api";

export function AssessmentListPage() {
  const navigate = useNavigate();
  const [items, setItems] = useState<AssessmentSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [startingId, setStartingId] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    listAvailableAssessments()
      .then((result) => { if (alive) setItems(result); })
      .catch((cause) => { if (alive) setError(friendlyBackendError(cause).message); })
      .finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, []);

  async function start(item: AssessmentSummary) {
    setStartingId(item.assessment_id);
    setError(null);
    try {
      const attemptId = await startAssessment(item.assessment_id);
      navigate(`/attempts/${attemptId}?assessmentId=${encodeURIComponent(item.assessment_id)}`);
    } catch (cause) {
      setError(friendlyBackendError(cause).message);
    } finally {
      setStartingId(null);
    }
  }

  return (
    <div className="page-stack">
      <PageHeading eyebrow="STUDENT WORKSPACE" title="Assessments" description="Published assessments available to your account. Questions are retrieved from Supabase when you open an assessment." />
      {error && <Notice tone="error">{error}</Notice>}
      {loading ? <div className="surface loading-placeholder">Loading assessments…</div> : items.length ? <div className="assessment-grid">{items.map((item) => (
        <Surface className="assessment-card" key={item.assessment_id}>
          <div className="assessment-card-top"><span className="metric-icon teal-icon"><FileCheck2 size={18} /></span><StatusBadge tone={item.assessment_type === "diagnostic" ? "teal" : "neutral"}>{item.assessment_type}</StatusBadge></div>
          <h2>{item.title}</h2><p>{item.description || "A focused assessment published for your class or learning path."}</p>
          <div className="assessment-card-meta"><span><Clock3 size={15} />{item.question_count} questions</span><span>{item.total_points} points</span></div>
          <button className="button button-primary button-full" onClick={() => void start(item)} disabled={startingId !== null}>{startingId === item.assessment_id ? "Opening…" : "Start assessment"}<ArrowRight size={16} /></button>
        </Surface>
      ))}</div> : !error && <Surface><EmptyState title="No assessments available">Published assessments assigned to your account will appear here. Ask your teacher if you expected to see one.</EmptyState></Surface>}
    </div>
  );
}
