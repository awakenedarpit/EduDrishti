import { useCallback, useEffect, useState, type FormEvent } from "react";
import { ArrowRight, Plus, School, Users } from "lucide-react";
import { Link } from "react-router-dom";
import { EmptyState, Notice, PageHeading, StatusBadge, Surface } from "../../components/ui";
import { friendlyBackendError } from "../../lib/backend-errors";
import { createTeacherClass, listTeacherClasses, type TeacherClass } from "../assessments/api";

function useTeacherClasses() {
  const [classes, setClasses] = useState<TeacherClass[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const refresh = useCallback(async () => {
    setLoading(true);
    setError(null);
    try { setClasses(await listTeacherClasses()); }
    catch (cause) { setError(friendlyBackendError(cause).message); }
    finally { setLoading(false); }
  }, []);
  useEffect(() => { void refresh(); }, [refresh]);
  return { classes, loading, error, refresh };
}

export function TeacherDashboardPage() {
  const { classes, loading, error } = useTeacherClasses();
  return (
    <div className="page-stack">
      <PageHeading eyebrow="TEACHER WORKSPACE" title="Teaching dashboard" description="A clear view of the classes this database-authorized teacher account manages." action={<Link to="/teacher/classes" className="button button-primary"><Plus size={16} /> Manage classes</Link>} />
      {error && <Notice tone="error">{error}</Notice>}
      <div className="metric-grid metric-grid-three">
        <Surface className="metric-card"><div className="metric-heading"><span>YOUR CLASSES</span><span className="metric-icon teal-icon"><School size={17} /></span></div><strong>{loading ? "—" : classes.length}</strong><span className="metric-foot">RLS-scoped to this teacher</span></Surface>
        <Surface className="metric-card"><div className="metric-heading"><span>LEARNER RECORDS</span><span className="metric-icon blue-icon"><Users size={17} /></span></div><strong>—</strong><span className="metric-foot">Roster insights are not connected</span></Surface>
        <Surface className="metric-card"><div className="metric-heading"><span>DIAGNOSIS ANALYTICS</span><span className="metric-icon amber-icon"><School size={17} /></span></div><strong>—</strong><span className="metric-foot">Stage 3 RPCs not installed</span></Surface>
      </div>
      <div className="section-heading"><div><p className="eyebrow">CLASSROOMS</p><h2>Classes you manage</h2></div><Link to="/teacher/classes" className="text-link">Open classes <ArrowRight size={15} /></Link></div>
      <Surface>
        {error ? <EmptyState title="Class list unavailable">The database did not return this teacher's authorized classes. Review the access message above.</EmptyState> : loading ? <p className="muted">Loading your classes…</p> : classes.length ? <div className="class-list">{classes.slice(0, 4).map((item) => <ClassCard item={item} key={item.id} />)}</div> : <EmptyState title="No classes yet">Create a class to begin organizing your teaching workspace.</EmptyState>}
      </Surface>
      <Notice tone="info" title="What is connected">Class listing and creation are live. Student insights, practice allocation, reports, and misconception analytics are shown as placeholders until their services are available.</Notice>
    </div>
  );
}

export function TeacherClassesPage() {
  const { classes, loading, error, refresh } = useTeacherClasses();
  const [formOpen, setFormOpen] = useState(false);
  const [name, setName] = useState("");
  const [grade, setGrade] = useState("10");
  const [subject, setSubject] = useState("Mathematics");
  const [description, setDescription] = useState("");
  const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setFormError(null);
    setSuccess(null);
    setSaving(true);
    try {
      await createTeacherClass({ name, gradeLevel: Number(grade), subject, description });
      setName(""); setDescription(""); setSuccess("Class created. Ownership was assigned by the database to this signed-in teacher.");
      setFormOpen(false);
      await refresh();
    } catch (cause) { setFormError(friendlyBackendError(cause).message); }
    finally { setSaving(false); }
  }

  return (
    <div className="page-stack">
      <PageHeading eyebrow="TEACHER WORKSPACE" title="Classes & rosters" description="Create and view classes owned by the signed-in teacher. Class ownership and access are enforced by Supabase." action={<button className="button button-primary" onClick={() => setFormOpen((value) => !value)}><Plus size={16} /> {formOpen ? "Close form" : "Create class"}</button>} />
      {error && <Notice tone="error">{error}</Notice>}{formError && <Notice tone="error">{formError}</Notice>}{success && <Notice tone="success">{success}</Notice>}
      {formOpen && <Surface className="class-form-panel"><div className="section-heading compact-heading"><div><p className="eyebrow">DATABASE-OWNED CLASS</p><h2>New class</h2></div><StatusBadge tone="teal">Teacher only</StatusBadge></div>
        <form className="class-form" onSubmit={(event) => void submit(event)}>
          <label>Class name<input required maxLength={120} value={name} onChange={(event) => setName(event.target.value)} placeholder="e.g. Class 10 · Section A" /></label>
          <label>Grade level<select value={grade} onChange={(event) => setGrade(event.target.value)}>{Array.from({ length: 12 }, (_, i) => String(i + 1)).map((item) => <option key={item} value={item}>Grade {item}</option>)}</select></label>
          <label>Subject<input required maxLength={80} value={subject} onChange={(event) => setSubject(event.target.value)} /></label>
          <label className="field-wide">Description <span className="optional">Optional</span><textarea maxLength={1000} rows={3} value={description} onChange={(event) => setDescription(event.target.value)} placeholder="A short note for this class" /></label>
          <div className="field-wide form-actions"><button className="button button-primary" type="submit" disabled={saving}>{saving ? "Creating…" : "Create class"}<ArrowRight size={16} /></button><span className="muted">Teacher identity is derived from the authenticated session; it is not entered here.</span></div>
        </form>
      </Surface>}
      <Surface>{loading ? <p className="muted">Loading your classes…</p> : classes.length ? <div className="class-list">{classes.map((item) => <ClassCard item={item} key={item.id} />)}</div> : !error && <EmptyState title="No classes yet">Create a class to establish a teacher-owned workspace. Student enrollment controls are not included on this screen.</EmptyState>}</Surface>
      <Notice tone="info" title="Roster scope">The class list is live and RLS-scoped. Student names, roster editing, and enrollment actions remain unavailable until their authorized workflow is connected.</Notice>
    </div>
  );
}

function ClassCard({ item }: { item: TeacherClass }) {
  return (
    <article className="class-card"><div className="class-card-icon"><School size={19} /></div><div className="class-card-main"><div className="class-title-row"><h3>{item.name}</h3><StatusBadge tone="neutral">Grade {item.grade_level}</StatusBadge></div><p>{item.subject}{item.description ? ` · ${item.description}` : ""}</p></div><span className="class-card-created">Created {new Intl.DateTimeFormat(undefined, { month: "short", year: "numeric" }).format(new Date(item.created_at))}</span></article>
  );
}
