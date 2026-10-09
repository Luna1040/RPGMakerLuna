export type Direction = "right" | "left" | "back" | "front";
export type JobStatus =
  | "queued"
  | "preparing"
  | "generating"
  | "extracting"
  | "removing_backgrounds"
  | "packaging"
  | "ready"
  | "stop_requested"
  | "stopped"
  | "failed"
  | "recovery_required";
export interface CatalogAction {
  id: string;
  label: string;
  description: string;
  stage: string;
  selection: { method: string; frames: number; include_last: boolean };
  frame_count: {
    value: number;
    editable: boolean;
    minimum?: number;
    maximum?: number;
  };
  conceptual_loop: boolean;
  animated_file: boolean;
  duration_seconds?: number;
  fps?: number;
}
export interface Catalog {
  revision: string;
  actions: CatalogAction[];
  poses: { id: string; label: string; stage: string; frame: string }[];
  capabilities: {
    directions: Direction[];
    prompt_styles: string[];
    split_methods: string[];
    animation_authoring: boolean;
  };
}
export interface Upload {
  id: string;
  filename: string;
  media_type: string;
  width: number;
  height: number;
  bytes: number;
  sha256: string;
  thumbnail_url: string;
}
export interface Workspace {
  id: string;
  name: string;
  upload_id?: string;
  source: Upload;
  created_at: string;
  storage_bytes: number;
  jobs?: Job[];
}
export interface RenderDraft {
  workspace_id: string;
  actions: string[];
  frame_counts: Record<string, number>;
  style: string;
  seed: { mode: "random" } | { mode: "fixed"; value: string };
  sprite_size: number;
  generation: { width: number; height: number; pad_top_percent: number };
  split_method: string;
  animation_overrides: Record<
    string,
    { duration_seconds?: number; fps?: number }
  >;
}
export interface PlanStage {
  id: string;
  label: string;
  reason: "selected" | "dependency";
  cache:
    | "hit"
    | "miss"
    | "awaiting_dependency"
    | "awaiting_submission"
    | "unavailable";
  dependencies: string[];
}
export interface RenderPlan {
  request: RenderDraft;
  resolved_seed: string | null;
  summary: {
    animation_count: number;
    frames_per_direction: number;
    directions: number;
  };
  stages: PlanStage[];
  definition_snapshot: string;
  config_snapshot: string;
}
export interface Job {
  id: string;
  workspace_id: string;
  status: JobStatus;
  phase: string;
  current_stage: string | null;
  completed_stages: number;
  total_stages: number;
  cached_stages: number;
  resolved_seed: string;
  created_at: string;
  started_at: string | null;
  finished_at: string | null;
  elapsed_seconds: number;
  stop_requested: boolean;
  resume_allowed: boolean;
  message: string;
  package_id: string | null;
  thumbnail_url?: string;
  request: RenderDraft;
  links: { self: string; events: string };
  kind?: "render" | "cycle_analysis" | "cycle_revision";
  parent_job_id?: string | null;
  base_package_id?: string | null;
}
export interface CycleFrame {
  id: string;
  frame_id: string;
  pts: number;
  time_seconds: number;
  url: string;
}
export interface CycleCandidate {
  id: string;
  start_time_seconds: number;
  end_time_seconds: number;
  period_seconds: number;
  frames: CycleFrame[];
  frame_durations_ms: number[];
  system_selected: boolean;
}
export interface CycleGroup {
  action: string;
  label: string;
  stage_id: string;
  status: "unavailable" | "pending" | "analyzing" | "ready" | "failed";
  message: string | null;
  can_analyze?: boolean;
  analysis_id: string | null;
  system_candidate_id: string | null;
  selected_candidate_id: string | null;
  selection_origin: "automatic" | "user" | null;
  frame_count: number;
  candidates: CycleCandidate[];
}
export interface CycleReview {
  job_id: string;
  groups: CycleGroup[];
  can_revise: boolean;
  can_analyze: boolean;
}
export interface PackageFile {
  artifact_id: string;
  filename: string;
  media_type: string;
  bytes: number;
  url: string;
}
export interface AnimationFile extends PackageFile {
  action: string;
  direction: Direction;
}
export interface Package {
  id: string;
  job_id: string;
  created_at: string;
  sheet: PackageFile;
  metadata: PackageFile;
  manifest: PackageFile;
  animations: AnimationFile[];
  still_actions: string[];
  download_url: string;
  action_downloads: Record<string, string>;
  preview?: {
    layout?: {
      rows: number;
      columns: number;
      cell_size: number;
      directions?: Direction[];
      animation_ranges: Record<string, [number, number]>;
    };
    frame_durations_ms?: Record<string, number[]>;
  };
}
export interface ConfigField {
  path: string[];
  label: string;
  kind: "integer" | "number" | "string" | "seed" | "model";
  value: string | number;
  default: string | number;
  overridden: boolean;
  required: boolean;
  minimum: number | null;
  maximum: number | null;
  unit?: string;
  help?: string;
  advanced?: Record<string, unknown>;
}
export interface ConfigDocument {
  revision: string;
  path: string;
  fields: ConfigField[];
}
export interface ConnectionStatus {
  ok: boolean;
  url: string;
  message: string;
  models: unknown[];
}
export interface RawPreviewAsset {
  id: string;
  kind: "video" | "pose" | "image";
  pose_id: string | null;
  filename: string;
  media_type: string;
  bytes: number;
  sha256: string;
  url: string;
}
export interface RawPreviewStage {
  stage_id: string;
  label: string;
  reason: "selected" | "dependency";
  action_id: string | null;
  owner_action_id?: string;
  dependency_for: string[];
  assets: RawPreviewAsset[];
}
export interface RawPreviews {
  job_id: string;
  stage_owners?: Record<string, string>;
  stages: RawPreviewStage[];
}
export type ActivityState =
  | "submitting"
  | "queued"
  | "waiting"
  | "running"
  | "completed"
  | "failed"
  | "idle"
  | "disconnected"
  | "unknown"
  | (string & {});
export type ActivityOperation =
  "generation" | "sdpose" | "background_removal" | "comfy" | (string & {});
export interface Activity {
  sequence: number;
  timestamp: string;
  state: ActivityState;
  operation: ActivityOperation;
  stage_id: string | null;
  prompt_id: string | null;
  message: string | null;
  error: null | {
    code: string;
    message: string;
    retryable: boolean;
    recovery_required: boolean;
  };
}
export interface ActivityResponse {
  job: Job;
  current: Activity | null;
  activities: Activity[];
  next_cursor: number;
}
export interface ApiErrorEnvelope {
  error?: {
    message?: string;
    code?: string;
    fields?: { path: (string | number)[]; message: string }[];
  };
  detail?: string | { msg?: string; loc?: Array<string | number> }[];
}
