import { useEffect, useState } from "react";
import { ArrowRight, FileText } from "lucide-react";
import { Link } from "react-router-dom";
import { EmptyState, Notice, PageHeading, StatusBadge, Surface } from "../../components/ui";
import { friendlyBackendError } from "../../lib/backend-errors";
import { listMyAttempts, type AttemptRow } from "./api";

export function ReportsPage() {
  const [attempts, setAttempts] = useState<AttemptRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    listMyAttempts().then((rows) => { if (alive) setAttempts(rows); }).catch((cause) => { if (alive) setError(friendlyBackendError(cause).message); }).finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, []);

  return (
    <div className="page-stack">
      <PageHeading eyebrow="PRIVATE LEARNER RECORDS" title="Assessment reports" description="Your own attempt history. Results are available only after the assessment service completes server-side grading." />
      {error && <Notice tone="error">{error}</Notice>}
      <Surface className="report-list-panel">
        {loading ? <p className="muted">Loading your attempts…</p> : attempts.length ? <div className="report-list">{attempts.map((attempt) => (
          <div className="report-row" key={attempt.id}><div className="report-icon"><FileText size={18} /></div><div className="report-main"><strong>Assessment attempt {attempt.attempt_number}</strong><span>Started {new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(new Date(attempt.started_at))}</span></div><StatusBadge tone={attempt.status === "graded" ? "teal" : attempt.status === "in_progress" ? "amber" : "neutral"}>{attempt.status === "graded" ? `${Number(attempt.score_percent ?? 0).toFixed(0)}% · graded` : attempt.status.replace("_", " ")}</StatusBadge><Link className="icon-link" to={attempt.status === "graded" ? `/attempts/${attempt.id}/results` : attempt.status === "in_progress" ? `/attempts/${attempt.id}` : "/assessments"} aria-label={attempt.status === "graded" ? "Open result" : "Open attempt"}><ArrowRight size={17} /></Link></div>
        ))}</div> : !error && <EmptyState title="No reports yet">Your completed assessment reports will appear here after server-side grading.</EmptyState>}
      </Surface>
      <p className="honesty-note">This history is read under the signed-in student's database policy. No other student's results are queried or displayed.</p>
    </div>
  );
}
