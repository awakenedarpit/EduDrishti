import { useEffect, useState } from "react";
import { ArrowLeft, CheckCircle2, CircleX, FileCheck2 } from "lucide-react";
import { Link, useParams } from "react-router-dom";
import { Notice, PageHeading, StatusBadge, Surface } from "../../components/ui";
import { friendlyBackendError } from "../../lib/backend-errors";
import type { Json } from "../../lib/database.types";
import { getStudentResults, type AssessmentResult, type ResultItem } from "./api";

function answerLabel(value: Json): string {
  if (value === null) return "No answer";
  if (typeof value !== "object" || Array.isArray(value)) return String(value);
  const record = value as Record<string, Json | undefined>;
  if (typeof record.selected_option === "string") return `Option ${record.selected_option}`;
  if (Array.isArray(record.selected_options)) return `Options ${record.selected_options.filter((item): item is string => typeof item === "string").join(", ")}`;
  if (typeof record.value === "string" || typeof record.value === "number") return String(record.value);
  return "Response recorded";
}

function correctLabel(item: ResultItem): string {
  const value = item.correct_answer;
  if (!value || typeof value !== "object" || Array.isArray(value)) return answerLabel(value);
  const record = value as Record<string, Json | undefined>;
  if (typeof record.correct_option === "string") return `Option ${record.correct_option}`;
  if (Array.isArray(record.correct_options)) return `Options ${record.correct_options.filter((item): item is string => typeof item === "string").join(", ")}`;
  if (typeof record.value === "number" || typeof record.value === "string") return String(record.value);
  if (Array.isArray(record.accepted_answers)) return record.accepted_answers.filter((item): item is string => typeof item === "string").join(" · ");
  return "See explanation";
}

export function AssessmentResultsPage() {
  const { attemptId = "" } = useParams();
  const [result, setResult] = useState<AssessmentResult | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    getStudentResults(attemptId).then((data) => { if (alive) setResult(data); }).catch((cause) => { if (alive) setError(friendlyBackendError(cause).message); }).finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, [attemptId]);

  if (loading) return <div className="page-stack"><div className="surface loading-placeholder">Loading your result…</div></div>;
  if (error || !result) return <div className="page-stack"><Notice tone="error">{error ?? "Result not available."}</Notice><Link className="button button-secondary" to={`/attempts/${attemptId}`}><ArrowLeft size={16} /> Return to attempt</Link></div>;

  return (
    <div className="page-stack">
      <PageHeading eyebrow="PRIVATE LEARNER REPORT" title={result.attempt.assessment_title} description={`Attempt ${result.attempt.attempt_number} · submitted ${new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(new Date(result.attempt.submitted_at))}`} action={<Link to="/reports" className="button button-secondary"><ArrowLeft size={16} /> My reports</Link>} />
      <Surface className="result-hero"><div className="result-score"><span>SERVER-GRADED SCORE</span><strong>{Number(result.attempt.score_percent).toFixed(0)}<small>%</small></strong><StatusBadge tone="teal">Completed</StatusBadge></div><div className="result-summary-grid"><div><span>Correct</span><strong>{result.summary.correct_count}</strong></div><div><span>Incorrect</span><strong>{result.summary.incorrect_count}</strong></div><div><span>Unanswered</span><strong>{result.summary.unanswered_count}</strong></div><div><span>Points</span><strong>{result.summary.earned_points} / {result.summary.total_points}</strong></div></div></Surface>
      <div className="section-heading"><div><p className="eyebrow">ITEM REVIEW</p><h2>Answers & explanations</h2></div><StatusBadge tone="neutral">{result.items.length} questions</StatusBadge></div>
      <div className="result-items">{result.items.map((item) => <Surface className={`result-item${item.is_correct ? " result-correct" : " result-incorrect"}`} key={item.question_id}>
        <div className="result-item-heading"><div className="result-item-icon">{item.is_correct ? <CheckCircle2 size={19} /> : <CircleX size={19} />}</div><div><p className="eyebrow">QUESTION {item.position}</p><h3>{item.prompt}</h3></div><StatusBadge tone={item.is_correct ? "teal" : item.is_answered ? "red" : "amber"}>{item.is_correct ? "Correct" : item.is_answered ? "Review" : "Unanswered"}</StatusBadge></div>
        <div className="answer-review-grid"><div><span>Your answer</span><strong>{item.is_answered ? answerLabel(item.answer) : "No response"}</strong></div>{!item.is_correct && <div><span>Expected answer</span><strong>{correctLabel(item)}</strong></div>}</div>
        {item.explanation && <div className="explanation-box"><FileCheck2 size={16} /><div><strong>Explanation</strong><p>{item.explanation}</p></div></div>}
      </Surface>)}</div>
      <Notice tone="info" title="About this report">The score and correctness shown here are returned by the assessment service after submission. An incorrect answer alone is not treated as proof of a specific misconception.</Notice>
    </div>
  );
}
