import type { ReactNode } from "react";
import { AlertCircle, CheckCircle2, LoaderCircle, Sparkles } from "lucide-react";

export function PageHeading({ eyebrow, title, description, action }: {
  eyebrow?: string;
  title: string;
  description?: string;
  action?: ReactNode;
}) {
  return (
    <div className="page-heading">
      <div>
        {eyebrow && <p className="eyebrow">{eyebrow}</p>}
        <h1>{title}</h1>
        {description && <p className="page-description">{description}</p>}
      </div>
      {action && <div className="page-heading-action">{action}</div>}
    </div>
  );
}

export function Surface({ children, className = "", ...props }: {
  children: ReactNode;
  className?: string;
  "aria-label"?: string;
}) {
  return <section className={`surface ${className}`} {...props}>{children}</section>;
}

export function LoadingState({ label = "Loading your workspace…" }: { label?: string }) {
  return <div className="loading-state" role="status"><LoaderCircle className="spin" size={20} /> <span>{label}</span></div>;
}

export function Notice({ tone = "info", title, children }: {
  tone?: "info" | "error" | "success";
  title?: string;
  children: ReactNode;
}) {
  const Icon = tone === "error" ? AlertCircle : tone === "success" ? CheckCircle2 : Sparkles;
  return (
    <div className={`notice notice-${tone}`} role={tone === "error" ? "alert" : "status"}>
      <Icon size={18} aria-hidden="true" />
      <div>{title && <strong>{title}</strong>}<div>{children}</div></div>
    </div>
  );
}

export function EmptyState({ title, children, action }: {
  title: string;
  children: ReactNode;
  action?: ReactNode;
}) {
  return (
    <div className="empty-state">
      <div className="empty-state-mark" aria-hidden="true"><Sparkles size={20} /></div>
      <h3>{title}</h3>
      <p>{children}</p>
      {action}
    </div>
  );
}

export function StatusBadge({ children, tone = "neutral" }: {
  children: ReactNode;
  tone?: "neutral" | "teal" | "amber" | "red";
}) {
  return <span className={`status-badge badge-${tone}`}>{children}</span>;
}
