import { useEffect, useMemo, useRef, useState } from "react";
import {
  ChevronDown,
  ImagePlus,
  LoaderCircle,
  RefreshCw,
  Server,
  Sparkles,
  UploadCloud,
} from "lucide-react";
import { api } from "../api/client";
import type {
  Catalog,
  CycleReview,
  Job,
  RenderDraft,
  RenderPlan,
  RawPreviewAsset,
  RawPreviews,
  Workspace,
} from "../api/types";
import {
  BusySpinner,
  Button,
  Choice,
  NumberField,
  Panel,
  SelectField,
  Status,
  TextField,
} from "../ui/Controls";
import { JobProgress } from "./JobProgress";
import { Results } from "./Results";
import { MediaLightbox } from "../ui/MediaLightbox";
import { ActivityModal } from "./ActivityModal";
import { CycleReviewDialog } from "./CycleReviewDialog";

function createIdempotencyKey() {
  const bytes = new Uint8Array(16);
  if (globalThis.crypto?.getRandomValues) {
    globalThis.crypto.getRandomValues(bytes);
    return `web-${Array.from(bytes, (value) => value.toString(16).padStart(2, "0")).join("")}`;
  }
  return `web-${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}-${Math.random().toString(36).slice(2)}`;
}
export function CreatePage({
  catalog,
  initialDraft,
  defaultsVersion,
  deletedWorkspaceId,
  onOpenSettings,
}: {
  catalog: Catalog | null;
  initialDraft: Partial<RenderDraft> | null;
  defaultsVersion: number;
  deletedWorkspaceId?: string;
  onOpenSettings: () => void;
}) {
  const [workspace, setWorkspace] = useState<Workspace | null>(() => {
      try {
        return JSON.parse(
          sessionStorage.getItem("sprite-extractor.workspace") ?? "null",
        );
      } catch {
        return null;
      }
    }),
    [uploading, setUploading] = useState(0),
    [uploadError, setUploadError] = useState(""),
    [drag, setDrag] = useState(false),
    [selected, setSelected] = useState<string[]>([]),
    [frames, setFrames] = useState<Record<string, number>>({}),
    [style, setStyle] = useState("neutral"),
    [seedMode, setSeedMode] = useState<"random" | "fixed">("random"),
    [seed, setSeed] = useState("0"),
    [spriteSize, setSpriteSize] = useState(256),
    [width, setWidth] = useState(400),
    [height, setHeight] = useState(512),
    [pad, setPad] = useState(0),
    [split, setSplit] = useState("blobs"),
    [overrides, setOverrides] = useState<
      Record<string, { duration_seconds?: number; fps?: number }>
    >({}),
    [plan, setPlan] = useState<RenderPlan | null>(null),
    [planError, setPlanError] = useState(""),
    [job, setJob] = useState<Job | null>(null),
    [resultJob, setResultJob] = useState<Job | null>(null),
    [cycleReview, setCycleReview] = useState<CycleReview | null>(null),
    [cycleAction, setCycleAction] = useState<string>(),
    [cycleOpen, setCycleOpen] = useState(false),
    [activityOpen, setActivityOpen] = useState(false),
    [submitError, setSubmitError] = useState<string>(),
    [rawPreviews, setRawPreviews] = useState<RawPreviews | null>(null),
    [lightbox, setLightbox] = useState<{
      asset: RawPreviewAsset;
      label: string;
      posterUrl?: string;
    } | null>(null),
    [submitting, setSubmitting] = useState(false),
    [connection, setConnection] = useState<{
      ok: boolean;
      message: string;
    } | null>(null),
    [initializing, setInitializing] = useState(true);
  const fileRef = useRef<HTMLInputElement>(null);
  const savedJobId = useRef(new URLSearchParams(location.search).get("job"));
  const defaultsSeen = useRef(defaultsVersion);
  const initialDefaultsApplied = useRef(false);
  const [updatedDefaults, setUpdatedDefaults] = useState(false);
  const idempotencyRef = useRef<{ fingerprint: string; key: string } | null>(
    null,
  );
  const appliedInitialDraft = useRef<Partial<RenderDraft> | null>(null);
  const openedError = useRef<string | undefined>(undefined);
  const applyDraft = (value: Partial<RenderDraft>) => {
    if (value.actions) setSelected(value.actions);
    if (value.frame_counts) setFrames(value.frame_counts);
    if (value.style) setStyle(value.style);
    if (value.sprite_size) setSpriteSize(value.sprite_size);
    if (value.generation) {
      setWidth(value.generation.width);
      setHeight(value.generation.height);
      setPad(value.generation.pad_top_percent);
    }
    if (value.split_method) setSplit(value.split_method);
    if (value.animation_overrides) setOverrides(value.animation_overrides);
    if (value.seed) {
      setSeedMode(value.seed.mode);
      if (value.seed.mode === "fixed") setSeed(value.seed.value);
    }
  };
  useEffect(() => {
    if (workspace)
      sessionStorage.setItem(
        "sprite-extractor.workspace",
        JSON.stringify(workspace),
      );
    else sessionStorage.removeItem("sprite-extractor.workspace");
  }, [workspace]);
  useEffect(() => {
    if (deletedWorkspaceId && workspace?.id === deletedWorkspaceId) {
      setWorkspace(null);
      setJob(null);
      setResultJob(null);
      history.replaceState({}, "", location.pathname);
    }
  }, [deletedWorkspaceId, workspace?.id]);
  useEffect(() => {
    const jobId = savedJobId.current;
    if (jobId)
      api
        .job(jobId)
        .then(async (fresh) => {
          setJob(fresh);
          if (
            !["ready", "stopped", "failed", "recovery_required"].includes(
              fresh.status,
            )
          )
            setActivityOpen(true);
          applyDraft(fresh.request);
          setSeedMode("fixed");
          setSeed(fresh.resolved_seed);
          try {
            setWorkspace(await api.workspace(fresh.workspace_id));
          } catch {
            /* Job detail remains usable if its workspace record is unavailable. */
          }
        })
        .catch((e) => setPlanError(e.message))
        .finally(() => setInitializing(false));
  }, []);
  useEffect(() => {
    if (
      savedJobId.current ||
      !initialDraft ||
      appliedInitialDraft.current === initialDraft
    )
      return;
    appliedInitialDraft.current = initialDraft;
    applyDraft(initialDraft);
    if (
      initialDraft.workspace_id &&
      initialDraft.workspace_id !== workspace?.id
    )
      api
        .workspace(initialDraft.workspace_id)
        .then(setWorkspace)
        .catch((e) => setPlanError(e.message));
    setInitializing(false);
  }, [initialDraft]);
  const applyServerDefaults = async () => {
    const config = await api.config();
    const value = (path: string, fallback: string | number) =>
      config.fields.find((field) => field.path.join(".") === path)?.value ??
      fallback;
    setSpriteSize(Number(value("sprite_box_height", 256)));
    setWidth(Number(value("sprite_render_width", 400)));
    setHeight(Number(value("sprite_render_height", 512)));
    setPad(Number(value("pad_top_percent", 0)));
    const configuredSeed = String(value("seed", "-1"));
    setSeedMode(configuredSeed === "-1" ? "random" : "fixed");
    if (configuredSeed !== "-1") setSeed(configuredSeed);
    if (catalog) setSelected(catalog.actions.map((item) => item.id));
    if (catalog)
      setFrames(
        Object.fromEntries(
          catalog.actions.map((item) => [
            item.id,
            Number(
              value(
                `animation_frames.${item.id.replaceAll("-", "_")}`,
                item.frame_count.value,
              ),
            ),
          ]),
        ),
      );
    setUpdatedDefaults(false);
  };
  useEffect(() => {
    if (
      savedJobId.current ||
      !catalog ||
      initialDraft ||
      initialDefaultsApplied.current
    )
      return;
    initialDefaultsApplied.current = true;
    void applyServerDefaults()
      .catch((reason) => {
        setPlanError(
          reason instanceof Error
            ? `Could not load server defaults: ${reason.message}`
            : "Could not load server defaults.",
        );
        setSelected(catalog.actions.map((item) => item.id));
        setFrames(
          Object.fromEntries(
            catalog.actions.map((item) => [item.id, item.frame_count.value]),
          ),
        );
      })
      .finally(() => setInitializing(false));
  }, [catalog, initialDraft]);
  useEffect(() => {
    if (defaultsSeen.current !== defaultsVersion) {
      defaultsSeen.current = defaultsVersion;
      setUpdatedDefaults(true);
    }
  }, [defaultsVersion]);
  useEffect(() => {
    setLightbox(null);
    setRawPreviews(null);
    setCycleReview(null);
  }, [job?.id]);
  useEffect(() => {
    if (!job) return;
    if (job.status === "ready" && job.package_id) {
      setResultJob(job);
      return;
    }
    if (job.base_package_id) {
      let current = true;
      api
        .package(job.base_package_id)
        .then((basePackage) => api.job(basePackage.job_id))
        .then((baseJob) => {
          if (current) setResultJob(baseJob);
        })
        .catch(() => {
          if (current) setResultJob(null);
        });
      return () => {
        current = false;
      };
    }
    if (!job.kind || job.kind === "render") setResultJob(null);
  }, [job?.id, job?.status, job?.package_id, job?.base_package_id]);
  useEffect(() => {
    if (!job) return;
    let current = true;
    let timer: number | undefined;
    const refresh = async () => {
      try {
        const value = await api.cycles(job.id);
        if (current && value.job_id === job.id) setCycleReview(value);
      } catch {
        if (current) setCycleReview(null);
      } finally {
        if (
          current &&
          !["ready", "stopped", "failed", "recovery_required"].includes(
            job.status,
          )
        )
          timer = window.setTimeout(() => void refresh(), 2000);
      }
    };
    void refresh();
    return () => {
      current = false;
      if (timer) clearTimeout(timer);
    };
  }, [job?.id, job?.status]);
  useEffect(() => {
    if (!job) {
      return;
    }
    let current = true;
    let timer: number | undefined;
    const polling = ![
      "ready",
      "stopped",
      "failed",
      "recovery_required",
    ].includes(job.status);
    const refresh = async () => {
      try {
        const value = await api.previews(job.id);
        if (current) setRawPreviews(value);
      } catch {
        // Raw previews are supplementary; job progress remains authoritative.
      } finally {
        if (current && polling)
          timer = window.setTimeout(() => void refresh(), 2000);
      }
    };
    void refresh();
    return () => {
      current = false;
      if (timer) clearTimeout(timer);
    };
  }, [job?.id, job?.status]);
  useEffect(() => {
    if (!job || !["failed", "recovery_required"].includes(job.status)) return;
    const signature = `${job.id}:${job.status}:${job.message}`;
    if (openedError.current !== signature) {
      openedError.current = signature;
      setActivityOpen(true);
    }
  }, [job?.id, job?.status, job?.message]);
  const draft = useMemo<RenderDraft | null>(
    () =>
      workspace
        ? {
            workspace_id: workspace.id,
            actions: selected,
            frame_counts: Object.fromEntries(
              selected.map((id) => [id, frames[id]]),
            ),
            style,
            seed:
              seedMode === "fixed"
                ? { mode: "fixed", value: seed }
                : { mode: "random" },
            sprite_size: spriteSize,
            generation: { width, height, pad_top_percent: pad },
            split_method: split,
            animation_overrides: Object.fromEntries(
              Object.entries(overrides).filter(([id]) => selected.includes(id)),
            ),
          }
        : null,
    [
      workspace,
      selected,
      frames,
      style,
      seedMode,
      seed,
      spriteSize,
      width,
      height,
      pad,
      split,
      overrides,
    ],
  );
  useEffect(() => {
    if (!draft || !selected.length) {
      setPlan(null);
      return;
    }
    const ctl = new AbortController(),
      timer = setTimeout(
        () =>
          api
            .plan(draft, ctl.signal)
            .then((x) => {
              setPlan(x);
              setPlanError("");
            })
            .catch((e) => {
              if (e.name !== "AbortError") {
                setPlan(null);
                setPlanError(e.message);
              }
            }),
        350,
      );
    return () => {
      clearTimeout(timer);
      ctl.abort();
    };
  }, [draft, selected.length]);
  useEffect(() => {
    api
      .connection()
      .then(setConnection)
      .catch((e) => setConnection({ ok: false, message: e.message }));
  }, []);
  const accept = async (file?: File) => {
    if (!file) return;
    if (!file.type.startsWith("image/")) {
      setUploadError("Choose a PNG, JPEG, or WebP image.");
      return;
    }
    if (file.size > 20 * 1024 * 1024) {
      setUploadError("Image is larger than the 20 MiB upload limit.");
      return;
    }
    setUploadError("");
    setUploading(1);
    try {
      const upload = await api.upload(file, setUploading);
      const name = file.name.replace(/\.[^.]+$/, "") || "Character";
      setWorkspace(await api.createWorkspace(upload.id, name));
      setJob(null);
      setResultJob(null);
    } catch (e) {
      setUploadError(e instanceof Error ? e.message : "Upload failed.");
    } finally {
      setUploading(0);
    }
  };
  const generate = async () => {
    if (!draft || submitting) return;
    setSubmitting(true);
    setSubmitError(undefined);
    setActivityOpen(true);
    try {
      const fingerprint = JSON.stringify(draft);
      const retained =
        idempotencyRef.current?.fingerprint === fingerprint
          ? idempotencyRef.current.key
          : createIdempotencyKey();
      idempotencyRef.current = { fingerprint, key: retained };
      const created = await api.createJob(draft, retained);
      setResultJob(null);
      setJob(created);
      setSeedMode("fixed");
      setSeed(created.resolved_seed);
      history.replaceState({}, "", `?job=${encodeURIComponent(created.id)}`);
      setPlanError("");
      idempotencyRef.current = null;
    } catch (e) {
      const message =
        e instanceof Error
          ? `${e.message} Retry safely with the same request.`
          : "Could not create the job.";
      setPlanError(message);
      setSubmitError(message);
      setActivityOpen(true);
    } finally {
      setSubmitting(false);
    }
  };
  if (initializing) return <Status>Loading render setup…</Status>;
  return (
    <>
      <div className="page-title">
        <div>
          <p className="editor-kicker">New generation</p>
          <h1 className="editor-heading editor-heading--page">
            Create sprites
          </h1>
          <p className="editor-text editor-text--secondary">
            Turn one character image into a reusable four-direction sprite
            package.
          </p>
        </div>
        {updatedDefaults && (
          <div className="updated-defaults" role="status">
            <span>Saved server defaults changed.</span>
            <Button compact onClick={() => void applyServerDefaults()}>
              Apply updated defaults
            </Button>
          </div>
        )}
      </div>
      <div className="setup-grid">
        <div className="setup-main">
          <Panel title="1. Character image" kicker="Source">
            <div
              className={`drop-zone ${drag ? "is-dragging" : ""} ${workspace ? "has-image" : ""}`}
              onDragEnter={(e) => {
                e.preventDefault();
                setDrag(true);
              }}
              onDragOver={(e) => e.preventDefault()}
              onDragLeave={() => setDrag(false)}
              onDrop={(e) => {
                e.preventDefault();
                setDrag(false);
                void accept(e.dataTransfer.files[0]);
              }}
            >
              {workspace ? (
                <>
                  <img
                    src={workspace.source.thumbnail_url}
                    alt="Uploaded character preview"
                  />
                  <div>
                    <strong>{workspace.source.filename}</strong>
                    <span>
                      {workspace.source.width} × {workspace.source.height} ·{" "}
                      {(workspace.source.bytes / 1048576).toFixed(1)} MiB
                    </span>
                    <Button
                      compact
                      type="button"
                      onClick={() => fileRef.current?.click()}
                    >
                      <RefreshCw size={14} />
                      Replace image
                    </Button>
                  </div>
                </>
              ) : (
                <>
                  <UploadCloud size={35} />
                  <strong>Drop a character image here</strong>
                  <span>PNG, JPEG, or WebP · up to 20 MiB</span>
                  <Button
                    compact
                    type="button"
                    onClick={() => fileRef.current?.click()}
                  >
                    <ImagePlus size={14} />
                    Choose image
                  </Button>
                </>
              )}
              {uploading > 0 && (
                <progress
                  aria-label="Uploading image"
                  max="100"
                  value={uploading}
                />
              )}
              <input
                ref={fileRef}
                hidden
                type="file"
                accept="image/png,image/jpeg,image/webp"
                onChange={(e) => void accept(e.target.files?.[0])}
              />
            </div>
            {uploadError && (
              <Status tone="danger" alert>
                {uploadError}
              </Status>
            )}
          </Panel>
          <Panel
            title="2. Choose animations"
            kicker="Outputs"
            actions={
              <div className="inline-actions">
                <Button
                  compact
                  onClick={() =>
                    setSelected(catalog?.actions.map((x) => x.id) ?? [])
                  }
                >
                  Select all
                </Button>
                <Button compact onClick={() => setSelected([])}>
                  Clear
                </Button>
              </div>
            }
          >
            <div className="animation-list">
              {catalog?.actions.map((action) => {
                const checked = selected.includes(action.id),
                  o = overrides[action.id] ?? {};
                const isRunningStage =
                  (job?.status === "generating" ||
                    job?.status === "stop_requested") &&
                  job.current_stage !== null &&
                  runningStageOwner(job, rawPreviews, catalog) === action.id;
                return (
                  <article
                    className={`animation-row ${checked ? "selected" : ""}`}
                    key={action.id}
                  >
                    <div className="animation-row__choice">
                      <Choice
                        type="checkbox"
                        checked={checked}
                        onChange={() =>
                          setSelected((s) =>
                            checked
                              ? s.filter((x) => x !== action.id)
                              : [...s, action.id],
                          )
                        }
                        label={action.label}
                        help={action.description}
                      />
                      {action.frame_count.editable ? (
                        <NumberField
                          aria-label={`${action.label} exported frames`}
                          label="Exported frames"
                          min={action.frame_count.minimum ?? 1}
                          max={action.frame_count.maximum}
                          value={frames[action.id] ?? action.frame_count.value}
                          disabled={!checked}
                          onChange={(e) =>
                            setFrames((f) => ({
                              ...f,
                              [action.id]: Number(e.target.value),
                            }))
                          }
                          unit="frames"
                        />
                      ) : (
                        <span className="still-label">
                          1 frame · still pose
                        </span>
                      )}
                      {isRunningStage && (
                        <BusySpinner
                          label={runningStageLabel(
                            job,
                            rawPreviews,
                            catalog,
                            action.id,
                          )}
                        />
                      )}
                    </div>
                    <RawPreviewStrip
                      actionId={action.id}
                      requestActions={job?.request.actions ?? []}
                      previews={
                        rawPreviews?.job_id === job?.id ? rawPreviews : null
                      }
                      onOpen={(asset, label, posterUrl) =>
                        setLightbox({ asset, label, posterUrl })
                      }
                    />
                    {cycleReview?.groups.find(
                      (group) => group.action === action.id,
                    ) && (
                      <CycleReviewButton
                        group={cycleReview.groups.find(
                          (group) => group.action === action.id,
                        )!}
                        onOpen={() => {
                          setCycleAction(action.id);
                          setCycleOpen(true);
                        }}
                      />
                    )}
                    {checked && (
                      <details>
                        <summary>Animation details</summary>
                        <div className="detail-fields">
                          <NumberField
                            label="Video duration"
                            value={o.duration_seconds ?? ""}
                            min={0.1}
                            step={0.1}
                            unit="seconds"
                            placeholder={action.duration_seconds?.toString()}
                            onChange={(e) =>
                              setOverrides((x) => ({
                                ...x,
                                [action.id]: {
                                  ...x[action.id],
                                  duration_seconds:
                                    e.target.value === ""
                                      ? undefined
                                      : Number(e.target.value),
                                },
                              }))
                            }
                          />
                          <NumberField
                            label="FPS"
                            value={o.fps ?? ""}
                            min={1}
                            step={1}
                            unit="fps"
                            placeholder={action.fps?.toString()}
                            onChange={(e) =>
                              setOverrides((x) => ({
                                ...x,
                                [action.id]: {
                                  ...x[action.id],
                                  fps:
                                    e.target.value === ""
                                      ? undefined
                                      : Number(e.target.value),
                                },
                              }))
                            }
                          />
                        </div>
                      </details>
                    )}
                  </article>
                );
              }) ?? <Status>Loading animation catalog…</Status>}
            </div>
            {plan && (
              <details className="dependency-plan" open>
                <summary>Automatic dependencies</summary>
                <p className="editor-text editor-text--help">
                  Only selected animations enter the final package. Required
                  intermediate stages are generated automatically.
                </p>
                <ul>
                  {plan.stages.map((s) => (
                    <li key={s.id}>
                      <span>{s.label}</span>
                      <span>
                        {s.reason === "dependency"
                          ? "Required dependency"
                          : "Selected"}{" "}
                        · {s.cache.replaceAll("_", " ")}
                      </span>
                    </li>
                  ))}
                </ul>
              </details>
            )}
            {planError && (
              <Status tone="danger" alert>
                {planError}
              </Status>
            )}
          </Panel>
        </div>
        <aside>
          <Panel
            title="Render settings"
            kicker="This job"
            className="settings-panel"
          >
            <div className="form-grid">
              <NumberField
                label="Sprite size"
                value={spriteSize}
                min={32}
                max={2048}
                unit="px"
                help="Target sprite height and square animation size; sheet cells may expand to fit wide poses."
                onChange={(e) => setSpriteSize(Number(e.target.value))}
              />
              <SelectField
                label="Prompt style"
                value={style}
                help="Controls the existing neutral or feminine motion prompt variant."
                onChange={(e) => setStyle(e.target.value)}
              >
                {(
                  catalog?.capabilities.prompt_styles ?? ["neutral", "feminine"]
                ).map((x) => (
                  <option key={x} value={x}>
                    {x[0].toUpperCase() + x.slice(1)}
                  </option>
                ))}
              </SelectField>
              <fieldset className="seed-field">
                <legend>Seed</legend>
                <div>
                  <Choice
                    type="radio"
                    name="seed-mode"
                    checked={seedMode === "random"}
                    onChange={() => setSeedMode("random")}
                    label="Random"
                  />
                  <Choice
                    type="radio"
                    name="seed-mode"
                    checked={seedMode === "fixed"}
                    onChange={() => setSeedMode("fixed")}
                    label="Fixed"
                  />
                </div>
                {seedMode === "fixed" && (
                  <TextField
                    label="Fixed seed"
                    value={seed}
                    inputMode="numeric"
                    pattern="[0-9]+"
                    onChange={(e) => setSeed(e.target.value)}
                    help="0–9223372036854775807; sent as decimal text."
                  />
                )}
              </fieldset>
              <details className="advanced">
                <summary>
                  <ChevronDown size={14} />
                  Advanced settings
                </summary>
                <div className="form-grid">
                  <NumberField
                    label="Generation width"
                    value={width}
                    min={64}
                    unit="px per view"
                    onChange={(e) => setWidth(Number(e.target.value))}
                  />
                  <NumberField
                    label="Generation height"
                    value={height}
                    min={64}
                    unit="px per view"
                    onChange={(e) => setHeight(Number(e.target.value))}
                  />
                  <NumberField
                    label="Top padding"
                    value={pad}
                    min={0}
                    max={100}
                    unit="%"
                    onChange={(e) => setPad(Number(e.target.value))}
                  />
                  <SelectField
                    label="Split method"
                    value={split}
                    onChange={(e) => setSplit(e.target.value)}
                  >
                    {(
                      catalog?.capabilities.split_methods ?? [
                        "blobs",
                        "quarters",
                      ]
                    ).map((x) => (
                      <option key={x} value={x}>
                        {x === "blobs" ? "Blobs" : "Quarters"}
                      </option>
                    ))}
                  </SelectField>
                  <p className="editor-text editor-text--help full">
                    Four-view generation image: {width * 4} ×{" "}
                    {Math.round(height * (1 + pad / 100))} px.
                  </p>
                </div>
              </details>
            </div>
            <div className="render-summary">
              <strong>
                {selected.length} animation{selected.length === 1 ? "" : "s"}
              </strong>
              <span>
                {plan?.summary.frames_per_direction ??
                  selected.reduce((n, id) => n + (frames[id] ?? 0), 0)}{" "}
                frames per direction
              </span>
              <span>
                {plan?.stages.filter((x) => x.reason === "dependency").length ??
                  0}{" "}
                dependencies included
              </span>
            </div>
            <div className={`connection ${connection?.ok ? "ok" : "bad"}`}>
              <Server size={16} />
              <span>{connection?.message ?? "Checking ComfyUI…"}</span>
              {connection && !connection.ok && (
                <button onClick={onOpenSettings}>Settings</button>
              )}
            </div>
            <Button
              variant="primary"
              className="generate-button"
              disabled={
                !draft ||
                !selected.length ||
                submitting ||
                (!!job &&
                  !["failed", "stopped", "ready", "recovery_required"].includes(
                    job.status,
                  ))
              }
              onClick={generate}
            >
              {submitting ? <LoaderCircle className="spin" /> : <Sparkles />}
              Generate sprites
            </Button>
          </Panel>
        </aside>
      </div>
      {job && (
        <JobProgress
          job={job}
          onJob={setJob}
          onOpenActivity={() => setActivityOpen(true)}
        />
      )}{" "}
      {resultJob?.package_id && (
        <Results
          packageId={resultJob.package_id}
          job={resultJob}
          cycleReview={cycleReview}
          onReview={(action) => {
            setCycleAction(action);
            setCycleOpen(true);
          }}
        />
      )}
      {lightbox && (
        <MediaLightbox
          asset={lightbox.asset}
          label={lightbox.label}
          posterUrl={lightbox.posterUrl}
          onClose={() => setLightbox(null)}
        />
      )}
      {activityOpen && (
        <ActivityModal
          job={job}
          clientError={submitError}
          onJob={setJob}
          onClose={() => setActivityOpen(false)}
        />
      )}
      {cycleOpen && cycleReview && job && (
        <CycleReviewDialog
          sourceJob={resultJob ?? job}
          activeJob={job}
          review={cycleReview}
          initialAction={cycleAction}
          onClose={() => setCycleOpen(false)}
          onJob={(child) => {
            setJob(child);
            setActivityOpen(true);
            history.replaceState(
              {},
              "",
              `?job=${encodeURIComponent(child.id)}`,
            );
          }}
        />
      )}
    </>
  );
}

function CycleReviewButton({
  group,
  onOpen,
}: {
  group: CycleReview["groups"][number];
  onOpen: () => void;
}) {
  if (group.status === "analyzing")
    return <BusySpinner label={`Finding cycles for ${group.label}…`} />;
  if (group.status === "pending")
    return (
      <span className="editor-text editor-text--help">
        Cycle analysis pending
      </span>
    );
  const count = group.candidates.length;
  return (
    <Button compact onClick={onOpen}>
      {count ? `Review cycles (${count})` : "Review cycles"}
    </Button>
  );
}

function RawPreviewStrip({
  actionId,
  requestActions,
  previews,
  onOpen,
}: {
  actionId: string;
  requestActions: string[];
  previews: RawPreviews | null;
  onOpen: (asset: RawPreviewAsset, label: string, posterUrl?: string) => void;
}) {
  const stages =
    previews?.stages.filter(
      (stage) => stageOwner(previews, stage, requestActions) === actionId,
    ) ?? [];
  const assets = stages.flatMap((stage) =>
    stage.assets.map((asset) => ({ stage, asset })),
  );
  return (
    <section
      className="raw-previews"
      aria-label={`Raw previews for ${actionId.replaceAll("_", " ")}`}
    >
      <strong>Raw unprocessed output</strong>
      {!assets.length ? (
        <span className="editor-text editor-text--help">
          Raw output pending
        </span>
      ) : (
        <div className="raw-preview-list">
          {assets.map(({ stage, asset }) => {
            const purpose = asset.kind === "video" ? "video" : "image";
            const label = `${stage.label} ${purpose}${stage.reason === "dependency" ? ` dependency for ${actionId.replaceAll("_", " ")}` : ""}${asset.pose_id ? ` · ${asset.pose_id.replaceAll("_", " ")}` : ""}`;
            const posterUrl = stage.assets.find(
              (candidate) => candidate.kind !== "video",
            )?.url;
            return (
              <button
                key={`${stage.stage_id}-${asset.id}`}
                type="button"
                className="raw-preview"
                aria-label={`Open ${label}`}
                onClick={() => onOpen(asset, label, posterUrl)}
              >
                {asset.kind === "video" ? (
                  <video
                    src={asset.url}
                    preload="metadata"
                    muted
                    playsInline
                    aria-hidden="true"
                    poster={posterUrl}
                  />
                ) : (
                  <img src={asset.url} alt="" loading="lazy" />
                )}
                <span>{label}</span>
              </button>
            );
          })}
        </div>
      )}
    </section>
  );
}

function stageOwner(
  previews: RawPreviews,
  stage: RawPreviews["stages"][number],
  requestActions: string[],
) {
  const recorded =
    stage.owner_action_id ?? previews.stage_owners?.[stage.stage_id];
  if (recorded) return recorded;

  // Compatibility for saved fixtures and older servers: preserve one owner by
  // choosing the first requested action known to consume this stage.
  return requestActions.find(
    (actionId) =>
      actionId === stage.action_id || stage.dependency_for.includes(actionId),
  );
}

function runningStageOwner(
  job: Job,
  previews: RawPreviews | null,
  catalog: Catalog,
) {
  const stageId = job.current_stage;
  if (!stageId) return undefined;
  if (previews?.job_id === job.id) {
    const recorded = previews.stage_owners?.[stageId];
    if (recorded) return recorded;
    const stage = previews.stages.find((item) => item.stage_id === stageId);
    if (stage) return stageOwner(previews, stage, job.request.actions);
  }

  // Before preview ownership metadata arrives, a selected root stage can still
  // identify its own card. Dependency ownership waits for the server map.
  return job.request.actions.find(
    (actionId) =>
      catalog.actions.find((action) => action.id === actionId)?.stage ===
      stageId,
  );
}

function runningStageLabel(
  job: Job,
  previews: RawPreviews | null,
  catalog: Catalog,
  ownerActionId: string,
) {
  const stageId = job.current_stage ?? "workflow";
  const owner = catalog.actions.find((action) => action.id === ownerActionId);
  if (owner?.stage === stageId) return `Generating ${owner.label} workflow`;

  const recordedLabel =
    previews?.job_id === job.id
      ? previews.stages.find((stage) => stage.stage_id === stageId)?.label
      : undefined;
  const stageLabel = recordedLabel ?? stageId.replaceAll("_", " ");
  return `Generating ${stageLabel} for ${owner?.label ?? ownerActionId.replaceAll("_", " ")}`;
}
