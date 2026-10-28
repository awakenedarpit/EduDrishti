import { useState, type FormEvent } from "react";
import { ArrowRight, Eye, EyeOff, GraduationCap } from "lucide-react";
import { Navigate, useNavigate } from "react-router-dom";
import { Notice } from "../components/ui";
import { friendlyBackendError } from "../lib/backend-errors";
import { isSupabaseConfigured, supabase } from "../lib/supabase";
import { useAuth } from "./AuthContext";

export function AuthPage() {
  const { session } = useAuth();
  const navigate = useNavigate();
  const [mode, setMode] = useState<"sign-in" | "sign-up">("sign-in");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  if (session) return <Navigate to="/" replace />;

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    setMessage(null);
    if (!supabase) return;
    setBusy(true);
    try {
      if (mode === "sign-in") {
        const { error: signInError } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
        if (signInError) throw signInError;
        navigate("/", { replace: true });
      } else {
        const { data, error: signUpError } = await supabase.auth.signUp({
          email: email.trim(),
          password,
          options: { data: { display_name: name.trim() } },
        });
        if (signUpError) throw signUpError;
        if (data.session) navigate("/", { replace: true });
        else setMessage("Account created. Check your email to confirm the address, then sign in. Student access is assigned by the database.");
      }
    } catch (cause) {
      setError(friendlyBackendError(cause).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="auth-page">
      <div className="auth-side-note">
        <span className="brand-mark brand-mark-large" aria-hidden="true">E</span>
        <p className="eyebrow">EDUDRISHTI · LEARNER INTELLIGENCE</p>
        <h1>Understand the learner.<br /><em>Transform the learning.</em></h1>
        <p>Focused assessments, thoughtful feedback, and a clearer path through mathematics.</p>
        <div className="auth-side-points"><span><GraduationCap size={16} /> Class 10 Mathematics</span><span>Server-scored assessments</span><span>Private learner records</span></div>
      </div>
      <div className="auth-form-wrap">
        <div className="auth-card">
          <div className="auth-card-heading"><p className="eyebrow">YOUR LEARNING SPACE</p><h2>{mode === "sign-in" ? "Sign in" : "Create a student account"}</h2><p>{mode === "sign-in" ? "Continue where you left off." : "Your account starts with student access."}</p></div>
          {!isSupabaseConfigured && <Notice tone="error" title="Supabase configuration required">Set <code>VITE_SUPABASE_URL</code> and <code>VITE_SUPABASE_ANON_KEY</code> in <code>web/.env.local</code> before signing in.</Notice>}
          {error && <Notice tone="error">{error}</Notice>}
          {message && <Notice tone="success">{message}</Notice>}
          <form className="auth-form" onSubmit={submit}>
            {mode === "sign-up" && <label>Display name<input autoComplete="name" maxLength={100} required value={name} onChange={(event) => setName(event.target.value)} placeholder="Your name" /></label>}
            <label>Email address<input autoComplete="email" type="email" required value={email} onChange={(event) => setEmail(event.target.value)} placeholder="you@example.com" /></label>
            <label>Password<div className="password-control"><input autoComplete={mode === "sign-in" ? "current-password" : "new-password"} type={showPassword ? "text" : "password"} required minLength={6} value={password} onChange={(event) => setPassword(event.target.value)} placeholder="At least 6 characters" /><button className="icon-button" type="button" aria-label={showPassword ? "Hide password" : "Show password"} onClick={() => setShowPassword((value) => !value)}>{showPassword ? <EyeOff size={17} /> : <Eye size={17} />}</button></div></label>
            <button className="button button-primary auth-submit" type="submit" disabled={!isSupabaseConfigured || busy}>
              {busy ? "Please wait…" : mode === "sign-in" ? "Sign in" : "Create student account"}<ArrowRight size={17} />
            </button>
          </form>
          <div className="auth-switch">{mode === "sign-in" ? "New to EduDrishti?" : "Already have an account?"}<button type="button" className="text-button" onClick={() => { setMode(mode === "sign-in" ? "sign-up" : "sign-in"); setError(null); setMessage(null); }}>{mode === "sign-in" ? "Create a student account" : "Sign in"}</button></div>
          <p className="auth-role-note">Teacher access is provisioned by an authorized administrator; it cannot be selected or changed here.</p>
        </div>
      </div>
    </div>
  );
}
