import { lazy, StrictMode, type ReactNode } from "react";
import { createBrowserRouter, Navigate, Outlet, RouterProvider, useNavigate } from "react-router-dom";
import { AlertTriangle, ArrowRight, LogOut, RefreshCw } from "lucide-react";
import { AuthProvider, useAuth } from "./app/AuthContext";
import { AppShell } from "./app/AppShell";
import { AuthPage } from "./app/AuthPage";
import { Notice, PageHeading, Surface } from "./components/ui";
import { PlaceholderPage } from "./features/placeholders/PlaceholderPage";
import { placeholderCatalog } from "./features/placeholders/catalog";
import { isSupabaseConfigured, supabase } from "./lib/supabase";

const AssessmentAttemptPage = lazy(() => import("./features/assessments/AssessmentAttemptPage").then((module) => ({ default: module.AssessmentAttemptPage })));
const AssessmentListPage = lazy(() => import("./features/assessments/AssessmentListPage").then((module) => ({ default: module.AssessmentListPage })));
const AssessmentResultsPage = lazy(() => import("./features/assessments/AssessmentResultsPage").then((module) => ({ default: module.AssessmentResultsPage })));
const ReportsPage = lazy(() => import("./features/assessments/ReportsPage").then((module) => ({ default: module.ReportsPage })));
const StudentDashboard = lazy(() => import("./features/assessments/StudentDashboard").then((module) => ({ default: module.StudentDashboard })));
const TeacherClassesPage = lazy(() => import("./features/teacher/TeacherPages").then((module) => ({ default: module.TeacherClassesPage })));
const TeacherDashboardPage = lazy(() => import("./features/teacher/TeacherPages").then((module) => ({ default: module.TeacherDashboardPage })));
const StudentDiagnosisPage = lazy(() => import("./features/diagnosis/DiagnosisPages").then((module) => ({ default: module.StudentDiagnosisPage })));
const TeacherMisconceptionPage = lazy(() => import("./features/diagnosis/DiagnosisPages").then((module) => ({ default: module.TeacherMisconceptionPage })));

function SetupRequired() {
  const navigate = useNavigate();
  return (
    <div className="setup-page">
      <span className="brand-mark" aria-hidden="true">E</span>
      <div className="eyebrow">EDUDRISHTI · LOCAL SETUP</div>
      <h1>Connect your Supabase project</h1>
      <p>The website is ready, but authentication and learner features are disabled until the browser-safe project values are configured.</p>
      <Surface className="setup-card">
        <h2>Set frontend environment variables</h2>
        <p>Create <code>web/.env.local</code> from <code>web/.env.example</code>, then add:</p>
        <pre><code>VITE_SUPABASE_URL=https://your-project.supabase.co{"\n"}VITE_SUPABASE_ANON_KEY=your-anon-or-publishable-key</code></pre>
        <Notice tone="info">Only the Supabase URL and anon/publishable key belong in a browser build. Never add a service-role key.</Notice>
        <p className="muted">Restart the Vite dev server after editing environment variables. For Vercel, add the same two values in Project Settings → Environment Variables.</p>
        <button className="button button-primary" onClick={() => navigate("/auth")}>Open sign-in <ArrowRight size={16} /></button>
      </Surface>
    </div>
  );
}

function AuthBoundary() {
  const { session, profile, loading, profileError, refreshProfile } = useAuth();
  if (!isSupabaseConfigured) return <SetupRequired />;
  if (loading) return <div className="fullscreen-state"><span className="loading-orb" />Loading your secure workspace…</div>;
  if (!session) return <Navigate to="/auth" replace />;
  if (!profile) {
    return (
      <div className="fullscreen-state profile-wait-state">
        <div className="profile-wait-card"><span className="brand-mark" aria-hidden="true">E</span><h1>Preparing your profile</h1><p>{profileError ?? "Your server-provisioned student or teacher profile has not appeared yet."}</p><div className="modal-actions"><button className="button button-secondary" onClick={() => void supabase?.auth.signOut()}><LogOut size={16} /> Sign out</button><button className="button button-primary" onClick={() => void refreshProfile()}><RefreshCw size={16} /> Check again</button></div><small>EduDrishti does not assign or change roles in the browser.</small></div>
      </div>
    );
  }
  return <Outlet />;
}

function StudentOnly({ children }: { children: ReactNode }) {
  const { profile } = useAuth();
  return profile?.app_role === "student" ? children : <Navigate to="/teacher" replace />;
}

function TeacherOnly({ children }: { children: ReactNode }) {
  const { profile } = useAuth();
  return profile?.app_role === "teacher" ? children : <Navigate to="/" replace />;
}

function HomeRoute() {
  const { profile } = useAuth();
  return profile?.app_role === "teacher" ? <TeacherDashboardPage /> : <StudentDashboard />;
}

function PlaceholderRoute({ path, teacher = false }: { path: string; teacher?: boolean }) {
  const copy = placeholderCatalog[path];
  if (!copy) return <NotFound />;
  const page = <PlaceholderPage copy={copy} />;
  return teacher ? <TeacherOnly>{page}</TeacherOnly> : <StudentOnly>{page}</StudentOnly>;
}

function NotFound() {
  return <div className="page-stack"><PageHeading eyebrow="NOT FOUND" title="We could not find that page" description="Choose a destination from your workspace navigation." /><Surface><div className="not-found-copy"><AlertTriangle size={22} /><p>The requested route is not part of this EduDrishti app.</p></div></Surface></div>;
}

const router = createBrowserRouter([
  { path: "/auth", element: <AuthPage /> },
  {
    element: <AuthBoundary />,
    children: [
      {
        element: <AppShell />,
        children: [
          { path: "/", element: <HomeRoute /> },
          { path: "/assessments", element: <StudentOnly><AssessmentListPage /></StudentOnly> },
          { path: "/attempts/:attemptId", element: <StudentOnly><AssessmentAttemptPage /></StudentOnly> },
          { path: "/attempts/:attemptId/results", element: <StudentOnly><AssessmentResultsPage /></StudentOnly> },
          { path: "/reports", element: <StudentOnly><ReportsPage /></StudentOnly> },
          { path: "/diagnosis", element: <StudentOnly><StudentDiagnosisPage /></StudentOnly> },
          { path: "/learning-hub", element: <PlaceholderRoute path="/learning-hub" /> },
          { path: "/learning-hub/concepts", element: <PlaceholderRoute path="/learning-hub/concepts" /> },
          { path: "/learning-hub/explanations", element: <PlaceholderRoute path="/learning-hub/explanations" /> },
          { path: "/tutor", element: <PlaceholderRoute path="/tutor" /> },
          { path: "/practice", element: <PlaceholderRoute path="/practice" /> },
          { path: "/study-plan", element: <PlaceholderRoute path="/study-plan" /> },
          { path: "/progress", element: <PlaceholderRoute path="/progress" /> },
          { path: "/teacher", element: <TeacherOnly><TeacherDashboardPage /></TeacherOnly> },
          { path: "/teacher/classes", element: <TeacherOnly><TeacherClassesPage /></TeacherOnly> },
          { path: "/teacher/students", element: <PlaceholderRoute path="/teacher/students" teacher /> },
          { path: "/teacher/assessments", element: <PlaceholderRoute path="/teacher/assessments" teacher /> },
          { path: "/teacher/analytics", element: <PlaceholderRoute path="/teacher/analytics" teacher /> },
          { path: "/teacher/misconceptions", element: <TeacherOnly><TeacherMisconceptionPage /></TeacherOnly> },
          { path: "/teacher/practice-allocator", element: <PlaceholderRoute path="/teacher/practice-allocator" teacher /> },
          { path: "/teacher/teaching-insights", element: <PlaceholderRoute path="/teacher/teaching-insights" teacher /> },
          { path: "/teacher/reports", element: <PlaceholderRoute path="/teacher/reports" teacher /> },
          { path: "*", element: <NotFound /> },
        ],
      },
    ],
  },
]);

export function App() {
  return <AuthProvider><RouterProvider router={router} /></AuthProvider>;
}

export function AppRoot() {
  return <StrictMode><App /></StrictMode>;
}
