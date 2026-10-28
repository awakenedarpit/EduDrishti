import { ArrowLeft, ArrowUpRight, LockKeyhole, Sparkles } from "lucide-react";
import { Link } from "react-router-dom";
import { PageHeading, Surface, StatusBadge } from "../../components/ui";

export type PlaceholderCopy = {
  title: string;
  description: string;
  group: "Student workspace" | "Teacher workspace";
  backendNote?: string;
};

export function PlaceholderPage({ copy }: { copy: PlaceholderCopy }) {
  return (
    <div className="page-stack">
      <PageHeading eyebrow={copy.group} title={copy.title} description={copy.description} />
      <Surface className="placeholder-panel">
        <div className="placeholder-topline">
          <div className="placeholder-emblem"><Sparkles size={24} /></div>
          <StatusBadge tone="amber">{copy.backendNote ? "Not connected" : "Coming soon"}</StatusBadge>
        </div>
        <h2>{copy.backendNote ? "This capability is not connected yet" : "A thoughtful learning space is on its way"}</h2>
        <p>{copy.backendNote ?? "This destination is included to reflect the supplied Stitch design. It will become interactive when its learning service is available."}</p>
        {copy.backendNote && <div className="placeholder-note"><LockKeyhole size={17} /><span>{copy.backendNote}</span></div>}
        <div className="placeholder-actions">
          <Link className="button button-secondary" to={copy.group === "Teacher workspace" ? "/teacher" : "/"}><ArrowLeft size={16} /> Back to dashboard</Link>
          <Link className="text-link" to={copy.group === "Teacher workspace" ? "/teacher/classes" : "/assessments"}>Explore connected features <ArrowUpRight size={15} /></Link>
        </div>
      </Surface>
      <p className="honesty-note">No sample learner records or generated performance values are shown on this screen.</p>
    </div>
  );
}
