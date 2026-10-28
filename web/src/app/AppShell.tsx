import { Suspense, useState } from "react";
import { NavLink, Outlet, useNavigate } from "react-router-dom";
import {
  Activity, BarChart3, BookOpen, BrainCircuit, CalendarDays, ClipboardList, FileText, LoaderCircle,
  GraduationCap, LayoutDashboard, Lightbulb, Menu, MessageCircle, PanelLeftClose,
  School, Settings2, Sparkles, Target, Users, X,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { useAuth } from "./AuthContext";
import { supabase } from "../lib/supabase";

const studentNav: Array<{ to: string; label: string; icon: LucideIcon }> = [
  { to: "/", label: "Dashboard", icon: LayoutDashboard },
  { to: "/assessments", label: "Assessments", icon: ClipboardList },
  { to: "/diagnosis", label: "Diagnosis", icon: BrainCircuit },
  { to: "/learning-hub", label: "Learning hub", icon: BookOpen },
  { to: "/learning-hub/concepts", label: "Concept hub", icon: Lightbulb },
  { to: "/learning-hub/explanations", label: "AI explanations", icon: Sparkles },
  { to: "/tutor", label: "AI tutor", icon: MessageCircle },
  { to: "/practice", label: "Practice lab", icon: Target },
  { to: "/study-plan", label: "Study plan", icon: CalendarDays },
  { to: "/progress", label: "Progress", icon: Activity },
  { to: "/reports", label: "Reports", icon: FileText },
];

const teacherNav: Array<{ to: string; label: string; icon: LucideIcon }> = [
  { to: "/teacher", label: "Dashboard", icon: LayoutDashboard },
  { to: "/teacher/classes", label: "Classes & rosters", icon: School },
  { to: "/teacher/students", label: "Students", icon: Users },
  { to: "/teacher/assessments", label: "Assessments", icon: ClipboardList },
  { to: "/teacher/analytics", label: "Analytics & mastery", icon: BarChart3 },
  { to: "/teacher/misconceptions", label: "Misconception heatmap", icon: BrainCircuit },
  { to: "/teacher/practice-allocator", label: "Practice allocator", icon: Target },
  { to: "/teacher/teaching-insights", label: "Teaching insights", icon: Lightbulb },
  { to: "/teacher/reports", label: "Reports & transcripts", icon: FileText },
];

function initials(name: string) {
  return name.split(/\s+/).filter(Boolean).slice(0, 2).map((part) => part[0]?.toUpperCase()).join("") || "E";
}

export function AppShell() {
  const { profile, session } = useAuth();
  const [menuOpen, setMenuOpen] = useState(false);
  const navigate = useNavigate();
  const isTeacher = profile?.app_role === "teacher";
  const nav = isTeacher ? teacherNav : studentNav;
  const name = profile?.display_name?.trim() || session?.user.email || (isTeacher ? "Teacher" : "Learner");

  async function signOut() {
    await supabase?.auth.signOut();
    navigate("/auth", { replace: true });
  }

  return (
    <div className="app-frame">
      <a className="skip-link" href="#main-content">Skip to content</a>
      <aside className={`sidebar ${menuOpen ? "sidebar-open" : ""}`} aria-label={`${isTeacher ? "Teacher" : "Student"} navigation`}>
        <div className="brand-lockup">
          <span className="brand-mark" aria-hidden="true">E</span>
          <span><strong>EduDrishti</strong><small>LEARNER INTELLIGENCE</small></span>
          <button className="icon-button sidebar-close" aria-label="Close navigation" onClick={() => setMenuOpen(false)}><X size={18} /></button>
        </div>
        <div className="workspace-label">{isTeacher ? "TEACHER WORKSPACE" : "STUDENT WORKSPACE"}</div>
        <nav className="primary-nav">
          {nav.map(({ to, label, icon: Icon }) => (
            <NavLink key={to} to={to} end={to === "/" || to === "/teacher" || to === "/learning-hub"} onClick={() => setMenuOpen(false)} className={({ isActive }) => `nav-link${isActive ? " nav-link-active" : ""}${to.startsWith("/learning-hub/") ? " nav-link-sub" : ""}`}>
              <Icon size={18} strokeWidth={1.8} aria-hidden="true" />
              <span>{label}</span>
            </NavLink>
          ))}
        </nav>
        <div className="sidebar-footnote">
          <div className="sidebar-note-icon"><GraduationCap size={17} /></div>
          <div><strong>Learn with clarity</strong><span>One step at a time.</span></div>
        </div>
      </aside>

      {menuOpen && <button className="mobile-scrim" aria-label="Close navigation" onClick={() => setMenuOpen(false)} />}

      <div className="workspace">
        <header className="topbar">
          <button className="icon-button mobile-menu" aria-label="Open navigation" aria-expanded={menuOpen} onClick={() => setMenuOpen(true)}><Menu size={20} /></button>
          <div className="topbar-context"><span className="context-mark"><PanelLeftClose size={16} /></span><span>{isTeacher ? "Teaching workspace" : "Learning workspace"}</span></div>
          <div className="topbar-right">
            <span className="role-chip"><Settings2 size={14} />{isTeacher ? "Teacher" : "Student"}</span>
            <button className="account-button" onClick={signOut} title="Sign out">
              <span className="avatar">{initials(profile?.display_name || session?.user.email || "E")}</span>
              <span className="account-copy"><strong>{name}</strong><small>Sign out</small></span>
            </button>
          </div>
        </header>
        <main id="main-content" className="main-content" tabIndex={-1}><Suspense fallback={<div className="surface loading-placeholder" role="status"><LoaderCircle className="spin" size={18} /> Opening this workspace…</div>}><Outlet /></Suspense></main>
        <footer className="app-footer"><Sparkles size={14} /> EduDrishti <span aria-hidden="true">·</span> Understand the learner. Transform the learning.</footer>
      </div>
    </div>
  );
}
