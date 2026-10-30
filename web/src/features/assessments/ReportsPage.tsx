import { useEffect, useState } from "react";
import { ArrowRight, FileText } from "lucide-react";
import { Link } from "react-router-dom";
import { EmptyState, Notice, PageHeading, StatusBadge, Surface } from "../../components/ui";
import { friendlyBackendError } from "../../lib/backend-errors";
import { getStudentAssessmentHistory, type AssessmentHistoryAttempt } from "../progress/api";

function attemptTone(status: AssessmentHistoryAttempt["status"]): "neutral" | "teal" | "amber" {
  if (status === "graded") return "teal";
  if (status === "in_progress") return "amber";
  return "neutral";
}

export function ReportsPage() {
  const [attempts, setAttempts] = useState<AssessmentHistoryAttempt[]>([]);
  const [totalAttempts, setTotalAttempts] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    getStudentAssessmentHistory().then((history) => {
      if (alive) {
        setAttempts(history.attempts);
        setTotalAttempts(history.total_attempts);
      }
    }).catch((cause) => {
      if (alive) setError(friendlyBackendError(cause).message);
    }).finally(() => {
      if (alive) setLoading(false);
    });
    return () => { alive = false; };
  }, []);

  return (
    <div className="page-stack">
      <PageHeading eyebrow="PRIVATE LEARNER RECORDS" title="Assessment reports" description="Your authorized assessment history, including server-graded outcomes and response counts." action={<Link className="button button-secondary" to="/progress">View progress</Link>} />
      {error && <Notice tone="error" title="Assessment history could not be loaded">{error} Confirm the Stage 5 database migration is installed and try again.</Notice>}
      <Surface className="report-list-panel">
        {loading ? <p className="muted">Loading your assessment history…</p> : attempts.length ? <div className="report-list">{attempts.map((attempt) => (
          <div className="report-row" key={attempt.attempt_id}>
            <div className="report-icon"><FileText size={18} /></div>
            <div className="report-main">
              <strong>{attempt.assessment_title} · attempt {attempt.attempt_number}</strong>
              <span>Started {new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(new Date(attempt.started_at))} · {attempt.answered_count} answered · {attempt.correct_count} correct{attempt.diagnosis_count ? ` · ${attempt.diagnosis_count} supported diagnosis signals` : ""}</span>
            </div>
            <StatusBadge tone={attemptTone(attempt.status)}>{attempt.status === "graded" ? `${Number(attempt.score_percent ?? 0).toFixed(0)}% · graded` : attempt.status.replaceAll("_", " ")}</StatusBadge>
            <Link className="icon-link" to={attempt.status === "graded" ? `/attempts/${attempt.attempt_id}/results` : attempt.status === "in_progress" ? `/attempts/${attempt.attempt_id}` : "/assessments"} aria-label={attempt.status === "graded" ? "Open result" : "Open attempt"}><ArrowRight size={17} /></Link>
          </div>
        ))}</div> : !error && <EmptyState title="No reports yet">Your completed assessment reports will appear here after server-side grading. New attempts are added to the history without replacing earlier scores.</EmptyState>}
      </Surface>
      {!loading && totalAttempts > attempts.length && <p className="muted">Showing the {attempts.length} most recent of {totalAttempts} attempts.</p>}
      <p className="honesty-note">This history is returned for the signed-in student only. It includes repeated attempts and does not replace earlier records.</p>
    </div>
  );
}
