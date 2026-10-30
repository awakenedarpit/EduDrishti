export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

type Relationship = [];

type Table<Row, Insert = Partial<Row>, Update = Partial<Row>> = {
  Row: Row;
  Insert: Insert;
  Update: Update;
  Relationships: Relationship;
};

export type ProfileRow = {
  user_id: string;
  app_role: "student" | "teacher";
  display_name: string | null;
  created_at: string;
  updated_at: string;
};

export type ClassRow = {
  id: string;
  teacher_id: string;
  name: string;
  grade_level: number;
  subject: string;
  description: string | null;
  created_at: string;
  updated_at: string;
};

export type Database = {
  public: {
    Tables: {
      profiles: Table<ProfileRow, Pick<ProfileRow, "user_id"> & Partial<ProfileRow>>;
      classes: Table<ClassRow, Pick<ClassRow, "teacher_id" | "name" | "grade_level" | "subject"> & Partial<ClassRow>>;
      assessments: Table<{
        id: string;
        class_id: string | null;
        created_by_teacher_id: string | null;
        title: string;
        description: string | null;
        assessment_type: "diagnostic" | "practice" | "summative";
        status: "draft" | "published" | "archived";
        is_template: boolean;
        created_at: string;
      }>;
      assessment_attempts: Table<{
        id: string;
        assessment_id: string;
        student_id: string;
        attempt_number: number;
        status: "in_progress" | "submitted" | "graded" | "abandoned";
        started_at: string;
        submitted_at: string | null;
        score_percent: number | null;
      }>;
      responses: Table<{
        id: string;
        attempt_id: string;
        assessment_id: string;
        question_id: string;
        answer: Json;
        is_answered: boolean;
        answered_at: string | null;
      }>;
      enrollments: Table<{
        class_id: string;
        student_id: string;
        status: "active" | "withdrawn";
        enrolled_at: string;
      }>;
    };
    Views: Record<string, never>;
    Functions: {
      list_available_assessments: { Args: Record<string, never>; Returns: Json };
      get_assessment: { Args: { p_assessment_id: string }; Returns: Json };
      start_assessment: { Args: { p_assessment_id: string }; Returns: string };
      save_response: {
        Args: { p_attempt_id: string; p_question_id: string; p_answer: Json };
        Returns: string;
      };
      complete_assessment: { Args: { p_attempt_id: string }; Returns: Json };
      get_student_results: { Args: { p_attempt_id: string }; Returns: Json };
      get_student_diagnoses: { Args: { p_attempt_id: string }; Returns: Json };
      get_my_recent_diagnoses: { Args: { p_limit?: number }; Returns: Json };
      get_class_misconception_summary: { Args: { p_class_id: string; p_assessment_id?: string | null }; Returns: Json };
      get_student_progress_overview: { Args: Record<string, never>; Returns: Json };
      get_student_topic_mastery: { Args: { p_topic_id: string }; Returns: Json };
      get_student_assessment_history: { Args: { p_limit?: number }; Returns: Json };
      get_student_recent_learning_activity: { Args: { p_limit?: number }; Returns: Json };
      get_student_mastery_history: { Args: { p_topic_id: string; p_learning_objective?: string | null; p_limit?: number }; Returns: Json };
      get_student_progress_comparison: { Args: { p_period_days?: number; p_topic_id?: string | null }; Returns: Json };
      get_class_learning_progress: { Args: { p_class_id: string; p_topic_id?: string | null }; Returns: Json };
      create_class: {
        Args: { p_name: string; p_grade_level: number; p_subject: string; p_description?: string | null };
        Returns: string;
      };
    };
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
};
