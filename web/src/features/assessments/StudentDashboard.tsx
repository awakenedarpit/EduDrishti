import { useEffect, useState } from "react";
import { ArrowRight, BookOpenCheck, ClipboardList, Clock3, Sparkles } from "lucide-react";
import { Link, useNavigate } from "react-router-dom";
import { EmptyState, Notice, PageHeading, StatusBadge, Surface } from "../../components/ui";
import { friendlyBackendError } from "../../lib/backend-errors";
import { listAvailableAssessments, listMyAttempts, startAssessment, type AssessmentSummary, type AttemptRow } from "./api";
import { getStudentProgressOverview, type StudentProgressOverview } from "../progress/api";

function dateLabel(value: string) {
  return new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", year: "numeric" }).format(new Date(value));
}

export function StudentDashboard() {
  const navigate = useNavigate();
  const [assessments, setAssessments] = useState<AssessmentSummary[]>([]);
  const [attempts, setAttempts] = useState<AttemptRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [starting, setStarting] = useState(false);
  const [progress, setProgress] = useState<StudentProgressOverview | null>(null);
  const [progressLoading, setProgressLoading] = useState(true);
  const [progressError, setProgressError] = useState(false);

  useEffect(() => {
    let alive = true;
    Promise.all([listAvailableAssessments(), listMyAttempts()])
      .then(([available, history]) => { if (alive) { setAssessments(available); setAttempts(history); } })
      .catch((cause) => { if (alive) setError(friendlyBackendError(cause).message); })
      .finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, []);

  useEffect(() => {
    let alive = true;
    getStudentProgressOverview().then((result) => {
      if (alive) setProgress(result);
    }).catch(() => {
      if (alive) setProgressError(true);
    }).finally(() => {
      if (alive) setProgressLoading(false);
    });
    return () => { alive = false; };
  }, []);

  async function begin(assessmentId: string) {
    setStarting(true);
    setError(null);
    try {
      const attemptId = await startAssessment(assessmentId);
      navigate(`/attempts/${attemptId}?assessmentId=${encodeURIComponent(assessmentId)}`);
    } catch (cause) {
      setError(friendlyBackendError(cause).message);
    } finally {
      setStarting(false);
    }
  }

  const completed = attempts.filter((attempt) => attempt.status === "graded");
  const resumable = attempts.find((attempt) => attempt.status === "in_progress");
  const highlighted = assessments[0];

  return (
    <div className="page-stack">
      <PageHeading eyebrow="STUDENT WORKSPACE" title="Your learning, in focus" description="A calm place to check what is available and choose your next step." action={<Link to="/assessments" className="button button-secondary"><ClipboardList size={16} /> Assessments</Link>} />
      {error && <Notice tone="error">{error}</Notice>}
      <div className="metric-grid metric-grid-three">
        <Surface className="metric-card"><div className="metric-heading"><span>AVAILABLE ASSESSMENTS</span><span className="metric-icon teal-icon"><ClipboardList size={17} /></span></div><strong>{loading ? "—" : assessments.length}</strong><span className="metric-foot">Available to this account</span></Surface>
        <Surface className="metric-card"><div className="metric-heading"><span>COMPLETED ATTEMPTS</span><span className="metric-icon amber-icon"><BookOpenCheck size={17} /></span></div><strong>{loading ? "—" : completed.length}</strong><span className="metric-foot">Server-graded submissions</span></Surface>
        <Surface className="metric-card"><div className="metric-heading"><span>IN PROGRESS</span><span className="metric-icon blue-icon"><Clock3 size={17} /></span></div><strong>{loading ? "—" : attempts.filter((attempt) => attempt.status === "in_progress").length}</strong><span className="metric-foot">Saved by the assessment service</span></Surface>
      </div>

      <div className="section-heading"><div><p className="eyebrow">PROGRESS SNAPSHOT</p><h2>What your evidence shows</h2></div><Link className="text-link" to="/progress">Open progress <ArrowRight size={15} /></Link></div>
      <Surface className="dashboard-progress-preview">
        {progressLoading ? <p className="muted">Loading your progress summary…</p> : progress ? <div className="dashboard-progress-stats"><div><strong>{progress.totals.topics_with_evidence}</strong><span>topics with evidence</span></div><div><strong>{progress.totals.secure_topics}</strong><span>topics meeting the secure threshold</span></div><p>These are versioned summaries from graded assessment answers and completed practice. Topics without enough evidence remain unclassified.</p></div> : <EmptyState title="Progress summary unavailable">The Stage 5 progress service could not be reached. Your assessment dashboard remains available; try the progress view again after the service is configured.</EmptyState>}
        {progressError && !progressLoading && <p className="honesty-note">The summary is not treated as zero or inferred when the database does not return it.</p>}
      </Surface>

      {highlighted ? (
        <Surface className="dashboard-feature">
          <div className="feature-copy"><StatusBadge tone="teal">{highlighted.assessment_type === "diagnostic" ? "Diagnostic assessment" : highlighted.assessment_type}</StatusBadge><h2>{highlighted.title}</h2><p>{highlighted.description || "A focused assessment assigned to your learning space."}</p><div className="feature-meta"><span>{highlighted.question_count} questions</span><span>{highlighted.total_points} points possible</span></div>
            <div className="feature-actions">
              {resumable ? <Link className="button button-primary" to={`/attempts/${resumable.id}`}>Resume assessment <ArrowRight size={16} /></Link> : <button className="button button-primary" onClick={() => void begin(highlighted.assessment_id)} disabled={starting}>{starting ? "Opening…" : "Start assessment"}<ArrowRight size={16} /></button>}
              <Link to="/assessments" className="text-link">Browse all assessments</Link>
            </div>
          </div>
          <div className="feature-art" aria-hidden="true"><div className="feature-orbit orbit-one" /><div className="feature-orbit orbit-two" /><div className="feature-equation">x² + bx + c = 0</div><Sparkles className="feature-spark" size={24} /></div>
        </Surface>
      ) : !loading ? (
        <Surface><EmptyState title="No assessment is available yet">When an assessment is published for your account, it will appear here. Your dashboard will only show records returned for this signed-in learner.</EmptyState></Surface>
      ) : null}

      <div className="section-heading"><div><p className="eyebrow">RECENT ACTIVITY</p><h2>Your assessment history</h2></div><Link className="text-link" to="/reports">View reports <ArrowRight size={15} /></Link></div>
      <Surface className="activity-panel">
        {loading ? <p className="muted">Loading your private assessment history…</p> : attempts.length ? <div className="activity-list">{attempts.slice(0, 4).map((attempt) => (
          <div className="activity-row" key={attempt.id}><span className="activity-dot" /><div className="activity-copy"><strong>{attempt.status === "in_progress" ? "Assessment in progress" : attempt.status === "graded" ? "Assessment completed" : "Assessment activity"}</strong><span>Attempt {attempt.attempt_number} · {dateLabel(attempt.started_at)}</span></div><StatusBadge tone={attempt.status === "graded" ? "teal" : "amber"}>{attempt.status === "graded" ? `${Number(attempt.score_percent ?? 0).toFixed(0)}%` : attempt.status.replace("_", " ")}</StatusBadge><Link className="icon-link" aria-label={attempt.status === "graded" ? "Open result" : "Resume attempt"} to={attempt.status === "graded" ? `/attempts/${attempt.id}/results` : `/attempts/${attempt.id}`}><ArrowRight size={17} /></Link></div>
        ))}</div> : <EmptyState title="Your first assessment is waiting">Completed submissions will appear here after the database has graded them.</EmptyState>}
      </Surface>
      <p className="honesty-note">Scores and attempt states above are read from your own Supabase records; this interface does not estimate performance.</p>
    </div>
  );
}
