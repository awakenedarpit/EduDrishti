import type { PlaceholderCopy } from "./PlaceholderPage";

export const placeholderCatalog: Record<string, PlaceholderCopy> = {
  "/diagnosis": {
    title: "Diagnosis & misconceptions",
    group: "Student workspace",
    description: "A space for careful, evidence-linked explanations of mathematical errors—not assumptions based only on a wrong answer.",
    backendNote: "Diagnosis records are not available in the connected project yet. The Stage 3 diagnosis migration must be deployed before this screen can show learner-specific signals.",
  },
  "/learning-hub": {
    title: "Learning hub",
    group: "Student workspace",
    description: "Browse lessons and concept resources in the connected learner experience.",
  },
  "/learning-hub/concepts": {
    title: "Concept learning hub",
    group: "Student workspace",
    description: "Explore concept maps, curriculum-aligned explanations, and worked examples.",
  },
  "/learning-hub/explanations": {
    title: "Personalized AI explanations",
    group: "Student workspace",
    description: "A future space for tailored explanations grounded in a learner's questions and submitted work.",
  },
  "/tutor": {
    title: "Context-aware AI tutor",
    group: "Student workspace",
    description: "Ask for guided help that supports understanding without revealing assessment answers prematurely.",
  },
  "/practice": {
    title: "Intelligent practice",
    group: "Student workspace",
    description: "A future practice area for targeted drills and adaptive difficulty.",
  },
  "/study-plan": {
    title: "Personalized study plan",
    group: "Student workspace",
    description: "A future place to organize topics, review activities, and study milestones.",
  },
  "/progress": {
    title: "Progress & mastery",
    group: "Student workspace",
    description: "A future view of dated topic progress and mastery trends based on real learning records.",
  },
  "/teacher/students": {
    title: "Student insights",
    group: "Teacher workspace",
    description: "A teacher-only destination for authorized learner profiles and support signals.",
  },
  "/teacher/assessments": {
    title: "Assessment management",
    group: "Teacher workspace",
    description: "Manage assessment content, publish windows, and class assignments.",
  },
  "/teacher/analytics": {
    title: "Analytics & mastery",
    group: "Teacher workspace",
    description: "A future class-level view of assessment participation and topic mastery from authorized records.",
  },
  "/teacher/misconceptions": {
    title: "Misconception heatmap",
    group: "Teacher workspace",
    description: "A future class summary that will surface only validated, evidence-linked misconception signals.",
    backendNote: "Class-level diagnosis analytics require the Stage 3 migration and RPCs, which are not installed in the connected project yet.",
  },
  "/teacher/practice-allocator": {
    title: "Practice allocator",
    group: "Teacher workspace",
    description: "A future teacher workflow for assigning targeted practice to authorized classes.",
  },
  "/teacher/teaching-insights": {
    title: "Teaching insights",
    group: "Teacher workspace",
    description: "A future space for evidence-based instructional suggestions from real class learning data.",
  },
  "/teacher/reports": {
    title: "Reports & transcripts",
    group: "Teacher workspace",
    description: "A future report center scoped to classes the signed-in teacher is authorized to manage.",
  },
};
