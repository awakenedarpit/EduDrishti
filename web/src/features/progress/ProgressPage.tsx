import { useEffect, useState } from "react";
import { BookOpenCheck, ChartNoAxesCombined, Clock3, Target } from "lucide-react";
import { Link } from "react-router-dom";
import { EmptyState, LoadingState, Notice, PageHeading, StatusBadge, Surface } from "../../components/ui";
import { friendlyBackendError } from "../../lib/backend-errors";
import {
  getStudentProgressComparison,
  getStudentProgressOverview,
  getStudentRecentActivity,
  type MasteryStatus,
  type ProgressComparisonItem,
  type RecentLearningActivity,
  type StudentProgressOverview,
  type TopicProgress,
} from "./api";

function dateLabel(value: string | null) {
  if (!value) return "No recorded activity";
  return new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(new Date(value));
}

function statusTone(status: MasteryStatus): "neutral" | "teal" | "amber" | "red" {
  if (status === "secure") return "teal";
  if (status === "developing") return "amber";
  if (status === "emerging") return "red";
  return "neutral";
}

function statusLabel(status: MasteryStatus) {
  return status === "insufficient_evidence" ? "insufficient evidence" : status;
}

function TopicCard({ topic }: { topic: TopicProgress }) {
  const estimateAvailable = topic.mastery_percent !== null;
  return (
    <Surface className="progress-topic-card">
      <div className="progress-topic-heading">
        <div>
          <p className="eyebrow">{topic.subject} · GRADE {topic.grade_level}</p>
          <h3>{topic.topic_title}</h3>
          <span className="muted">{topic.evidence_units} evidence units · {topic.evidence_days} active day{topic.evidence_days === 1 ? "" : "s"}</span>
        </div>
        <StatusBadge tone={statusTone(topic.status)}>{statusLabel(topic.status)}</StatusBadge>
      </div>
      {estimateAvailable ? (
        <div className="progress-estimate">
          <div className="progress-estimate-meta"><strong>{topic.mastery_percent?.toFixed(1)}%</strong><span>recency-weighted estimate</span></div>
          <div className="progress-track" role="progressbar" aria-label={`${topic.topic_title} mastery estimate`} aria-valuemin={0} aria-valuemax={100} aria-valuenow={topic.mastery_percent ?? 0}>
            <span style={{ width: `${Math.max(0, Math.min(100, topic.mastery_percent ?? 0))}%` }} />
          </div>
        </div>
      ) : (
        <p className="progress-insufficient">{topic.evidence_units === 0 ? "No graded answers or completed targeted practice are recorded for this topic yet." : "There is not enough recent, repeated evidence to show a mastery estimate."}</p>
      )}
      <div className="progress-evidence-grid">
        <span><strong>{topic.assessment_items}</strong> assessment items</span>
        <span><strong>{topic.assessment_attempts}</strong> graded attempts</span>
        <span><strong>{topic.completed_practice_activities}</strong> completed practice activities</span>
        <span><strong>{topic.supported_diagnosis_count}</strong> supported diagnosis signals</span>
      </div>
      {topic.objectives.length > 0 && (
        <div className="progress-objectives">
          <div className="progress-objectives-heading"><h4>Learning objectives</h4><span>Evidence is grouped by the question's saved objective.</span></div>
          {topic.objectives.map((objective) => (
            <div className="progress-objective-row" key={objective.learning_objective}>
              <div><strong>{objective.learning_objective.replaceAll("_", " ")}</strong><span>{objective.evidence_units} evidence units · {objective.completed_practice_activities} completed practice</span></div>
              {objective.mastery_percent === null ? <StatusBadge>{statusLabel(objective.status)}</StatusBadge> : <StatusBadge tone={statusTone(objective.status)}>{objective.mastery_percent.toFixed(1)}% · {objective.status}</StatusBadge>}
            </div>
          ))}
        </div>
      )}
      <p className="progress-last-evidence">Latest evidence: {dateLabel(topic.latest_evidence_at)}</p>
    </Surface>
  );
}

function ComparisonCard({ item }: { item: ProgressComparisonItem }) {
  return (
    <div className="comparison-row">
      <div className="comparison-topic"><strong>{item.topic_title}</strong><span>{item.is_topic_level ? "Topic overall" : item.learning_objective.replaceAll("_", " ")}</span></div>
      {item.comparable ? (
        <>
          <div className="comparison-values"><span>Previous <strong>{item.previous.mastery_percent?.toFixed(1)}%</strong></span><span>Current <strong>{item.current.mastery_percent?.toFixed(1)}%</strong></span></div>
          <StatusBadge tone={(item.change_percentage_points ?? 0) >= 0 ? "teal" : "amber"}>{(item.change_percentage_points ?? 0) > 0 ? "+" : ""}{item.change_percentage_points?.toFixed(1)} pp</StatusBadge>
        </>
      ) : (
        <div className="comparison-insufficient"><span>Not enough comparable history yet</span><small>Previous: {item.previous.evidence_units} items · Current: {item.current.evidence_units} items</small></div>
      )}
    </div>
  );
}

function ActivityRow({ item }: { item: RecentLearningActivity }) {
  const label = item.activity_type === "assessment" ? item.title : item.title;
  const detail = item.topic_title
    ? `${item.topic_title}${item.learning_objective ? ` · ${item.learning_objective.replaceAll("_", " ")}` : ""}`
    : item.activity_type === "assessment" ? `Attempt ${item.attempt_number ?? "—"}` : item.activity_type;
  const tone = item.status === "graded" || item.status === "completed" ? "teal" : item.status === "in_progress" ? "amber" : "neutral";
  return (
    <div className="activity-row">
      <span className="activity-dot" />
      <div className="activity-copy"><strong>{label}</strong><span>{detail} · {dateLabel(item.completed_at ?? item.started_at)}</span></div>
      <StatusBadge tone={tone}>{item.status.replaceAll("_", " ")}</StatusBadge>
    </div>
  );
}

export function ProgressPage() {
  const [overview, setOverview] = useState<StudentProgressOverview | null>(null);
  const [comparisons, setComparisons] = useState<ProgressComparisonItem[]>([]);
  const [activity, setActivity] = useState<RecentLearningActivity[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    Promise.all([
      getStudentProgressOverview(),
      getStudentProgressComparison(30),
      getStudentRecentActivity(8),
    ]).then(([progress, comparison, recent]) => {
      if (!alive) return;
      setOverview(progress);
      setComparisons(comparison.comparisons);
      setActivity(recent.activity);
    }).catch((cause) => {
      if (alive) setError(friendlyBackendError(cause).message);
    }).finally(() => {
      if (alive) setLoading(false);
    });
    return () => { alive = false; };
  }, []);

  const topicComparisons = comparisons.filter((item) => item.is_topic_level);

  return (
    <div className="page-stack">
      <PageHeading
        eyebrow="YOUR LEARNING RECORD"
        title="Progress & mastery"
        description="A dated view of what your completed assessments and targeted practice show so far."
        action={<Link to="/reports" className="button button-secondary"><BookOpenCheck size={16} /> Assessment reports</Link>}
      />
      {error && <Notice tone="error" title="Progress data could not be loaded">{error} Confirm the Stage 5 database migration is installed and try again.</Notice>}
      {loading ? <LoadingState label="Loading your recorded progress…" /> : overview ? (
        <>
          <div className="metric-grid metric-grid-three">
            <Surface className="metric-card"><div className="metric-heading"><span>TOPICS WITH EVIDENCE</span><span className="metric-icon teal-icon"><Target size={17} /></span></div><strong>{overview.totals.topics_with_evidence}</strong><span className="metric-foot">Of {overview.totals.published_topics} published topics</span></Surface>
            <Surface className="metric-card"><div className="metric-heading"><span>SECURE TOPICS</span><span className="metric-icon blue-icon"><ChartNoAxesCombined size={17} /></span></div><strong>{overview.totals.secure_topics}</strong><span className="metric-foot">Evidence met the versioned threshold</span></Surface>
            <Surface className="metric-card"><div className="metric-heading"><span>CALCULATION</span><span className="metric-icon amber-icon"><Clock3 size={17} /></span></div><strong>{overview.calculation_version}</strong><span className="metric-foot">As of {dateLabel(overview.as_of)}</span></Surface>
          </div>

          <div className="section-heading"><div><p className="eyebrow">TOPIC & OBJECTIVE VIEW</p><h2>Your evidence so far</h2></div><span className="muted">Estimates require repeated, recent evidence</span></div>
          {overview.topics.length ? <div className="progress-topic-grid">{overview.topics.map((topic) => <TopicCard key={topic.topic_id} topic={topic} />)}</div> : <Surface><EmptyState title="No published topics">Topic summaries will appear when curriculum topics are available.</EmptyState></Surface>}

          <div className="section-heading"><div><p className="eyebrow">CHANGE OVER TIME</p><h2>Last 30 days vs. the prior 30</h2></div></div>
          <Surface className="comparison-panel">
            {topicComparisons.length ? <div className="comparison-list">{topicComparisons.map((item) => <ComparisonCard key={`${item.topic_id}:${item.learning_objective}`} item={item} />)}</div> : <EmptyState title="No comparable periods yet">A change is shown only when both periods have enough recent evidence. New activity alone is not reported as improvement or decline.</EmptyState>}
          </Surface>

          <div className="section-heading"><div><p className="eyebrow">RECENT LEARNING ACTIVITY</p><h2>Assessments and practice</h2></div></div>
          <Surface className="activity-panel">
            {activity.length ? <div className="activity-list">{activity.map((item) => <ActivityRow key={`${item.activity_type}:${item.id}`} item={item} />)}</div> : <EmptyState title="No learning activity recorded">Graded attempts, explanations, and practice will appear here when available.</EmptyState>}
          </Surface>
          <Notice tone="info" title="How to read this estimate">
            The baseline uses one unit per graded assessment item and one unit per fully completed practice activity. Evidence is weighted with a 90-day half-life; an estimate requires at least five units across two UTC dates and evidence within 90 days. Emerging is below 60%, developing is 60–79.9%, and secure is 80% or more. This is a transparent progress indicator, not a scientifically calibrated ability score. Rule-based diagnosis signals are shown separately and do not change the score.
          </Notice>
        </>
      ) : !error ? <Surface><EmptyState title="Progress is not available">No progress response was returned for this account.</EmptyState></Surface> : null}
    </div>
  );
}
