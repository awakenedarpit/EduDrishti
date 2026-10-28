import { useEffect, useMemo, useState } from "react";
import { ArrowLeft, Check, ChevronLeft, ChevronRight, CircleHelp, LoaderCircle, Send } from "lucide-react";
import { Link, useNavigate, useParams, useSearchParams } from "react-router-dom";
import { EmptyState, Notice, StatusBadge, Surface } from "../../components/ui";
import { AppError, friendlyBackendError } from "../../lib/backend-errors";
import type { Json } from "../../lib/database.types";
import { answerDraftFromSaved, toAnswerPayload, type AnswerDraft } from "./answer";
import { completeAssessment, getAssessment, getMyAttempt, listAttemptResponses, saveResponse, type AssessmentEnvelope, type AssessmentQuestion } from "./api";

function blankDraft(question: AssessmentQuestion): AnswerDraft {
  return question.question_type === "multiple_choice" ? [] : "";
}

function isBlank(draft: AnswerDraft) {
  return Array.isArray(draft) ? draft.length === 0 : !draft.trim();
}

export function AssessmentAttemptPage() {
  const { attemptId = "" } = useParams();
  const [search] = useSearchParams();
  const navigate = useNavigate();
  const [assessment, setAssessment] = useState<AssessmentEnvelope | null>(null);
  const [index, setIndex] = useState(0);
  const [drafts, setDrafts] = useState<Record<string, AnswerDraft>>({});
  const [savedIds, setSavedIds] = useState<Set<string>>(() => new Set());
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saveMessage, setSaveMessage] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    async function load() {
      try {
        const attempt = await getMyAttempt(attemptId);
        if (attempt.status === "graded") { navigate(`/attempts/${attemptId}/results`, { replace: true }); return; }
        if (attempt.status !== "in_progress") throw new AppError("This attempt is not open for answers.");
        const assessmentId = search.get("assessmentId") || attempt.assessment_id;
        if (assessmentId !== attempt.assessment_id) throw new AppError("The assessment does not match this attempt.");
        const [details, saved] = await Promise.all([getAssessment(assessmentId), listAttemptResponses(attemptId)]);
        if (!alive) return;
        setAssessment(details);
        const restored: Record<string, AnswerDraft> = {};
        const ids = new Set<string>();
        for (const row of saved) {
          const question = details.questions.find((item) => item.question_id === row.question_id);
          if (!question || !row.is_answered) continue;
          restored[row.question_id] = answerDraftFromSaved(question.question_type, row.answer as Json);
          ids.add(row.question_id);
        }
        setDrafts(restored); setSavedIds(ids);
      } catch (cause) { if (alive) setError(friendlyBackendError(cause).message); }
      finally { if (alive) setLoading(false); }
    }
    if (attemptId) void load(); else { setError("Attempt identifier is missing."); setLoading(false); }
    return () => { alive = false; };
  }, [attemptId, navigate, search]);

  const questions = assessment?.questions ?? [];
  const question = questions[index];
  const draft = question ? drafts[question.question_id] ?? blankDraft(question) : "";
  const validAnsweredCount = useMemo(() => questions.filter((item) => {
    const current = drafts[item.question_id] ?? blankDraft(item);
    return toAnswerPayload(item.question_type, current, item.options.map((option) => option.id)) !== null;
  }).length, [drafts, questions]);

  function changeDraft(value: AnswerDraft) {
    if (!question) return;
    setDrafts((current) => ({ ...current, [question.question_id]: value }));
    setSaveMessage(null);
  }

  async function saveQuestion(item: AssessmentQuestion, currentDraft: AnswerDraft) {
    if (isBlank(currentDraft)) return false;
    const payload = toAnswerPayload(item.question_type, currentDraft, item.options.map((option) => option.id));
    if (!payload) throw new AppError("This answer format is incomplete or invalid. Review the response before continuing.");
    await saveResponse(attemptId, item.question_id, payload);
    setSavedIds((current) => new Set(current).add(item.question_id));
    return true;
  }

  async function goTo(nextIndex: number) {
    if (!question || nextIndex < 0 || nextIndex >= questions.length || busy) return;
    setError(null); setBusy(true);
    try {
      const currentDraft = drafts[question.question_id] ?? blankDraft(question);
      const saved = await saveQuestion(question, currentDraft);
      setIndex(nextIndex);
      setSaveMessage(saved ? "Answer saved securely." : null);
    } catch (cause) { setError(friendlyBackendError(cause).message); }
    finally { setBusy(false); }
  }

  async function finish() {
    if (!question) return;
    setError(null); setBusy(true);
    try {
      const currentDraft = drafts[question.question_id] ?? blankDraft(question);
      await saveQuestion(question, currentDraft);
      const result = await completeAssessment(attemptId);
      if (result.attempt?.id !== attemptId || result.attempt.status !== "graded") throw new AppError("The assessment service did not return a completed result.");
      navigate(`/attempts/${attemptId}/results`, { replace: true });
    } catch (cause) { setError(friendlyBackendError(cause).message); setConfirmOpen(false); }
    finally { setBusy(false); }
  }

  if (loading) return <div className="page-stack"><div className="surface loading-placeholder"><LoaderCircle className="spin" size={18} /> Loading your assessment…</div></div>;
  if (error && !assessment) return <div className="page-stack"><Notice tone="error">{error}</Notice><Link className="button button-secondary" to="/assessments"><ArrowLeft size={16} /> Back to assessments</Link></div>;
  if (!assessment || !question) return <Surface><EmptyState title="Assessment unavailable">The assessment questions could not be loaded for this attempt.</EmptyState></Surface>;

  const unanswered = questions.length - validAnsweredCount;
  const progress = questions.length ? ((index + 1) / questions.length) * 100 : 0;

  return (
    <div className="page-stack assessment-runner">
      <div className="runner-topline"><Link to="/assessments" className="text-link"><ArrowLeft size={15} /> Assessments</Link><StatusBadge tone="teal">In progress</StatusBadge></div>
      <Surface className="runner-summary">
        <div className="runner-title"><div><p className="eyebrow">{assessment.assessment.assessment_type} · {assessment.questions[0]?.topic.title ?? "Assessment"}</p><h1>{assessment.assessment.title}</h1><p>{assessment.assessment.description}</p></div><div className="runner-count"><strong>{index + 1}<span> / {questions.length}</span></strong><small>QUESTION</small></div></div>
        <div className="progress-track" aria-label={`Question ${index + 1} of ${questions.length}`}><span style={{ width: `${progress}%` }} /></div>
        <div className="runner-progress-copy"><span>Question {index + 1} of {questions.length}</span><span>{validAnsweredCount} response{validAnsweredCount === 1 ? "" : "s"} entered</span></div>
      </Surface>

      <div className="runner-layout">
        <Surface className="question-card">
          <div className="question-meta"><StatusBadge tone="neutral">{question.concept.replaceAll("_", " ")}</StatusBadge><span>{question.points} {question.points === 1 ? "point" : "points"}</span><span>Difficulty {question.difficulty}/5</span></div>
          <p className="question-number">Question {question.position}</p>
          <h2 className="question-prompt">{question.prompt}</h2>
          <div className="answer-area">
            {question.question_type === "single_choice" && <fieldset className="option-list"><legend>Select one answer</legend>{question.options.map((option) => <label key={option.id} className={`option-tile${draft === option.id ? " option-selected" : ""}`}><input type="radio" name={question.question_id} value={option.id} checked={draft === option.id} onChange={() => changeDraft(option.id)} /><span className="option-key">{option.id}</span><span>{option.text}</span>{draft === option.id && <Check className="option-check" size={17} />}</label>)}</fieldset>}
            {question.question_type === "multiple_choice" && <fieldset className="option-list"><legend>Select all that apply</legend>{question.options.map((option) => { const selected = Array.isArray(draft) && draft.includes(option.id); return <label key={option.id} className={`option-tile${selected ? " option-selected" : ""}`}><input type="checkbox" checked={selected} onChange={() => { const current = Array.isArray(draft) ? draft : []; changeDraft(selected ? current.filter((id) => id !== option.id) : [...current, option.id]); }} /><span className="option-key">{option.id}</span><span>{option.text}</span>{selected && <Check className="option-check" size={17} />}</label>; })}</fieldset>}
            {question.question_type === "numeric" && <label className="answer-input-label">Enter a numeric answer<input className="answer-input math-input" type="number" step="any" inputMode="decimal" value={typeof draft === "string" ? draft : ""} onChange={(event) => changeDraft(event.target.value)} placeholder="Your answer" /></label>}
            {question.question_type === "short_text" && <label className="answer-input-label">Enter your answer in standard form<input className="answer-input math-input" type="text" maxLength={500} value={typeof draft === "string" ? draft : ""} onChange={(event) => changeDraft(event.target.value)} placeholder="Type your mathematical answer" /></label>}
          </div>
          <div className="privacy-hint"><CircleHelp size={16} /><span>Your answer is saved to this attempt. Correct answers and scoring stay hidden until you submit.</span></div>
          {saveMessage && <p className="save-message"><Check size={15} />{saveMessage}</p>}
          {error && <Notice tone="error">{error}</Notice>}
          <div className="runner-actions"><button className="button button-secondary" onClick={() => void goTo(index - 1)} disabled={index === 0 || busy}><ChevronLeft size={17} /> Previous</button><button className="button button-primary" onClick={() => index === questions.length - 1 ? setConfirmOpen(true) : void goTo(index + 1)} disabled={busy}>{index === questions.length - 1 ? <>Review & submit <Send size={16} /></> : <>Save & continue <ChevronRight size={17} /></>}</button></div>
        </Surface>
        <aside className="question-rail">
          <Surface><div className="rail-heading"><strong>Question palette</strong><span>{questions.length} items</span></div><div className="question-palette">{questions.map((item, itemIndex) => <button key={item.question_id} className={`palette-item${itemIndex === index ? " palette-current" : ""}${savedIds.has(item.question_id) ? " palette-saved" : ""}`} aria-label={`Go to question ${item.position}${savedIds.has(item.question_id) ? ", answered" : ""}`} onClick={() => void goTo(itemIndex)} disabled={busy}>{item.position}{savedIds.has(item.question_id) && <span aria-hidden="true">•</span>}</button>)}</div><p className="palette-legend"><span className="legend-dot legend-active" />Current <span className="legend-dot legend-saved" />Saved <span className="legend-dot legend-empty" />Unanswered</p></Surface>
          <Notice tone="info" title="Scoring">The server grades each submitted answer. Unanswered items receive zero points; no partial credit is configured for this assessment.</Notice>
        </aside>
      </div>

      {confirmOpen && <div className="modal-backdrop" role="presentation"><section className="confirm-modal" role="dialog" aria-modal="true" aria-labelledby="submit-title"><div className="modal-mark"><Send size={19} /></div><p className="eyebrow">ASSESSMENT SUBMISSION</p><h2 id="submit-title">Submit this assessment?</h2><p>{unanswered > 0 ? `${unanswered} question${unanswered === 1 ? " is" : "s are"} unanswered and will receive zero points.` : "Your answers will be graded by the server and your result will become available."} You cannot edit a graded attempt.</p><div className="modal-actions"><button className="button button-secondary" onClick={() => setConfirmOpen(false)} disabled={busy}>Keep working</button><button className="button button-primary" onClick={() => void finish()} disabled={busy}>{busy ? "Submitting…" : "Submit & see results"}<Send size={16} /></button></div></section></div>}
    </div>
  );
}
