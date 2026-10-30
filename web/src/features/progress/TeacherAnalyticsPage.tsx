import { useEffect, useState } from "react";
import { BarChart3, School, Users } from "lucide-react";
import { Link } from "react-router-dom";
import { EmptyState, LoadingState, Notice, PageHeading, StatusBadge, Surface } from "../../components/ui";
import { friendlyBackendError } from "../../lib/backend-errors";
import { listTeacherClasses, type TeacherClass } from "../assessments/api";
import { getClassLearningProgress, type ClassLearningProgress, type ClassTopicProgress, type MasteryStatus } from "./api";

function tone(status: MasteryStatus): "neutral" | "teal" | "amber" | "red" {
  if (status === "secure") return "teal";
  if (status === "developing") return "amber";
  if (status === "emerging") return "red";
  return "neutral";
}

function TopicAggregate({ topic }: { topic: ClassTopicProgress }) {
  return (
    <Surface className="progress-topic-card">
      <div className="progress-topic-heading">
        <div><p className="eyebrow">{topic.subject} · GRADE {topic.grade_level}</p><h3>{topic.topic_title}</h3><span className="muted">{topic.students_with_evidence} learners represented · {topic.evidence_units} evidence units</span></div>
        <StatusBadge tone={tone(topic.status)}>{topic.status.replaceAll("_", " ")}</StatusBadge>
      </div>
      {topic.class_weighted_accuracy_percent === null ? <p className="progress-insufficient">There is not enough recent, repeated class evidence for an aggregate estimate.</p> : (
        <div className="progress-estimate"><div className="progress-estimate-meta"><strong>{topic.class_weighted_accuracy_percent.toFixed(1)}%</strong><span>class-weighted accuracy</span></div><div className="progress-track" role="progressbar" aria-label={`${topic.topic_title} class aggregate`} aria-valuemin={0} aria-valuemax={100} aria-valuenow={topic.class_weighted_accuracy_percent}><span style={{ width: `${Math.max(0, Math.min(100, topic.class_weighted_accuracy_percent))}%` }} /></div></div>
      )}
      <div className="progress-evidence-grid">
        <span><strong>{topic.assessment_attempts}</strong> graded attempts</span>
        <span><strong>{topic.completed_practice_activities}</strong> completed practice activities</span>
        <span><strong>{topic.evidence_days}</strong> evidence days</span>
        <span><strong>{topic.supported_diagnosis_count}</strong> supported diagnosis signals</span>
      </div>
      {topic.objectives.length > 0 && <div className="progress-objectives"><div className="progress-objectives-heading"><h4>Learning objectives</h4><span>Aggregate only; no learner-level rows are returned.</span></div>{topic.objectives.map((objective) => (
        <div className="progress-objective-row" key={objective.learning_objective}><div><strong>{objective.learning_objective.replaceAll("_", " ")}</strong><span>{objective.students_with_evidence} learners · {objective.evidence_units} evidence units</span></div>{objective.class_weighted_accuracy_percent === null ? <StatusBadge>{objective.status.replaceAll("_", " ")}</StatusBadge> : <StatusBadge tone={tone(objective.status)}>{objective.class_weighted_accuracy_percent.toFixed(1)}% · {objective.status}</StatusBadge>}</div>
      ))}</div>}
      <p className="progress-last-evidence">Latest class evidence: {topic.latest_evidence_at ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(new Date(topic.latest_evidence_at)) : "No evidence"}</p>
    </Surface>
  );
}

export function TeacherAnalyticsPage() {
  const [classes, setClasses] = useState<TeacherClass[]>([]);
  const [classId, setClassId] = useState("");
  const [progress, setProgress] = useState<ClassLearningProgress | null>(null);
  const [classesLoading, setClassesLoading] = useState(true);
  const [progressLoading, setProgressLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    listTeacherClasses().then((items) => {
      if (!alive) return;
      setClasses(items);
      setClassId((current) => current || items[0]?.id || "");
    }).catch((cause) => {
      if (alive) setError(friendlyBackendError(cause).message);
    }).finally(() => {
      if (alive) setClassesLoading(false);
    });
    return () => { alive = false; };
  }, []);

  useEffect(() => {
    if (!classId) {
      setProgress(null);
      return;
    }
    let alive = true;
    setProgressLoading(true);
    setError(null);
    getClassLearningProgress(classId).then((data) => {
      if (alive) setProgress(data);
    }).catch((cause) => {
      if (alive) setError(friendlyBackendError(cause).message);
    }).finally(() => {
      if (alive) setProgressLoading(false);
    });
    return () => { alive = false; };
  }, [classId]);

  const selectedClass = classes.find((item) => item.id === classId);
  const topicsWithEvidence = progress?.topics.filter((item) => item.evidence_units > 0).length ?? 0;
  const evidenceUnits = progress?.topics.filter((item) => item.evidence_units > 0).reduce((total, item) => total + item.evidence_units, 0) ?? 0;
  const secureTopics = progress?.topics.filter((item) => item.status === "secure").length ?? 0;

  return (
    <div className="page-stack">
      <PageHeading eyebrow="TEACHER WORKSPACE" title="Class progress analytics" description="Topic and objective trends from this teacher's own classes, aggregated across active enrolled learners." action={<Link to="/teacher/classes" className="button button-secondary"><School size={16} /> Manage classes</Link>} />
      {error && <Notice tone="error" title="Class progress could not be loaded">{error} Confirm the Stage 5 migration is installed and that this class belongs to your teacher account.</Notice>}
      <Surface className="class-selector-panel">
        <label htmlFor="progress-class">Select a class</label>
        <select id="progress-class" value={classId} onChange={(event) => setClassId(event.target.value)} disabled={classesLoading || classes.length === 0}>
          {classes.length === 0 ? <option value="">No classes available</option> : classes.map((item) => <option value={item.id} key={item.id}>{item.name} · Grade {item.grade_level} {item.subject}</option>)}
        </select>
        {selectedClass && <span className="muted">Summary is restricted by the database to {selectedClass.name}.</span>}
      </Surface>

      {classesLoading ? <LoadingState label="Loading your authorized classes…" /> : classes.length === 0 ? <Surface><EmptyState title="No classes yet">Create a class before opening class-level progress analytics.</EmptyState></Surface> : progressLoading ? <LoadingState label="Loading class-level progress…" /> : progress ? (
        <>
          <div className="metric-grid metric-grid-three">
            <Surface className="metric-card"><div className="metric-heading"><span>ACTIVE ENROLLMENTS</span><span className="metric-icon teal-icon"><Users size={17} /></span></div><strong>{progress.active_students}</strong><span className="metric-foot">Aggregate class size only</span></Surface>
            <Surface className="metric-card"><div className="metric-heading"><span>TOPICS WITH EVIDENCE</span><span className="metric-icon blue-icon"><BarChart3 size={17} /></span></div><strong>{topicsWithEvidence}</strong><span className="metric-foot">Of {progress.topics.length} published topics</span></Surface>
            <Surface className="metric-card"><div className="metric-heading"><span>EVIDENCE UNITS</span><span className="metric-icon amber-icon"><School size={17} /></span></div><strong>{evidenceUnits}</strong><span className="metric-foot">{secureTopics} topic aggregates meet the baseline</span></Surface>
          </div>
          <div className="section-heading"><div><p className="eyebrow">{selectedClass?.name ?? "CLASS"}</p><h2>Topic and objective summaries</h2></div><span className="muted">As of {new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(new Date(progress.as_of))}</span></div>
          {progress.topics.length ? <div className="progress-topic-grid">{progress.topics.map((topic) => <TopicAggregate topic={topic} key={topic.topic_id} />)}</div> : <Surface><EmptyState title="No published topics">Class progress will appear when published curriculum topics are available.</EmptyState></Surface>}
          <Notice tone="info" title="Aggregate view, not learner ranking">The API returns class totals and counts only; it omits student IDs, names, and individual rows. Only graded assessments assigned to this class and active enrolled students contribute. A class aggregate is not an estimate of any one learner's mastery.</Notice>
        </>
      ) : !error ? <Surface><EmptyState title="No progress summary returned">The selected class has no progress summary available yet.</EmptyState></Surface> : null}
      <p className="honesty-note">Class accuracy and status are calculated with the same versioned baseline as student summaries, but pooled at class level. Empty or insufficient data is shown explicitly; no learner performance is invented.</p>
    </div>
  );
}
