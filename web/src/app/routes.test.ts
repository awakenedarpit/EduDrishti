import { describe, expect, it } from "vitest";
import routeManifest from "../../public/manus-routes.json";
import { placeholderCatalog } from "../features/placeholders/catalog";

const routePaths = routeManifest.routes.map(({ path }) => path);

const stitchDestinations = [
  "/",                         // Learner dashboard
  "/assessments",              // Diagnostic assessment
  "/reports",                  // Learner report
  "/learning-hub/concepts",    // Concept learning hub
  "/tutor",                    // Context-aware AI tutor
  "/practice",                 // Intelligent practice
  "/diagnosis",                // Misconception analysis
  "/learning-hub/explanations",// Personalized AI explanation
  "/study-plan",               // Personalized study plan
  "/progress",                 // Progress and mastery
  "/teacher/analytics",        // Teacher analytics
  "/teacher/misconceptions",   // Teacher misconception heatmap
  "/teacher/assessments",      // Teacher assessment management
  "/teacher/classes",          // Teacher class management
  "/teacher",                  // Teacher dashboard
  "/teacher/reports",         // Teacher reports and transcripts
  "/teacher/students",        // Teacher student insights
  "/teacher/practice-allocator", // Teacher practice allocator
  "/teacher/teaching-insights",  // Teacher teaching insights
];

describe("page route manifest", () => {
  it("includes every supplied Stitch destination", () => {
    expect(routePaths).toEqual(expect.arrayContaining(stitchDestinations));
  });

  it("contains no duplicate paths", () => {
    expect(new Set(routePaths).size).toBe(routePaths.length);
  });

  it("declares every placeholder page as a loadable route", () => {
    expect(routePaths).toEqual(expect.arrayContaining(Object.keys(placeholderCatalog)));
  });

  it("uses only local absolute page paths", () => {
    expect(routePaths.every((path) => path.startsWith("/") && !path.startsWith("//"))).toBe(true);
  });
});
