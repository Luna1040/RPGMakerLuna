import { useEffect, useRef, useState } from "react";
import {
  ChevronLeft,
  ChevronRight,
  Pause,
  Play,
  RotateCcw,
} from "lucide-react";
import type {
  CycleCandidate,
  CycleReview,
  Job,
  RawPreviewAsset,
} from "../api/types";
import { api } from "../api/client";
import { Button, Choice, SelectField, Status } from "../ui/Controls";
import { DialogShell } from "../ui/DialogShell";
import { MediaLightbox } from "../ui/MediaLightbox";
import { SampledFrameImage, type SampledFrame } from "../ui/SampledFramePlayer";

const PAGE_SIZE = 4;
const activeStatuses = new Set([
  "queued",
  "preparing",
  "generating",
  "extracting",
  "removing_backgrounds",
  "packaging",
  "stop_requested",
]);

function idempotencyKey() {
  const bytes = new Uint8Array(16);
  if (globalThis.crypto?.getRandomValues) {
    globalThis.crypto.getRandomValues(bytes);
    return `cycle-${Array.from(bytes, (value) => value.toString(16).padStart(2, "0")).join("")}`;
  }
  return `cycle-${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
}

function durableKey(fingerprint: string) {
  const key = `sprite-extractor.cycle-submit.v1:${fingerprint}`;
  try {
    const stored = sessionStorage.getItem(key);
    if (stored) return { key: stored, storageKey: key };
    const value = idempotencyKey();
    sessionStorage.setItem(key, value);
    return { key: value, storageKey: key };
  } catch {
    return { key: idempotencyKey(), storageKey: "" };
  }
}

export function CycleReviewDialog({
  sourceJob,
  activeJob,
  review,
  initialAction,
  onClose,
  onJob,
}: {
  sourceJob: Job;
  activeJob: Job;
  review: CycleReview;
  initialAction?: string;
  onClose: () => void;
  onJob: (job: Job) => void;
}) {
  const ready = review.groups.filter((group) => group.status === "ready");
  const signature = review.groups
    .map((group) => `${group.action}:${group.analysis_id ?? "none"}`)
    .join("|");
  const storageKey = `sprite-extractor.cycle-review.v1:${review.job_id}:${signature}`;
  const defaults = Object.fromEntries(
    ready.map((group) => [
      group.action,
      group.selected_candidate_id ?? group.system_candidate_id ?? "",
    ]),
  );
  const [choices, setChoices] = useState<Record<string, string>>(() => {
    try {
      return {
        ...defaults,
        ...JSON.parse(localStorage.getItem(storageKey) ?? "{}"),
      };
    } catch {
      return defaults;
    }
  });
  const [action, setAction] = useState(
    initialAction &&
      review.groups.some((group) => group.action === initialAction)
      ? initialAction
      : (ready[0]?.action ?? review.groups[0]?.action ?? ""),
  );
  const [playing, setPlaying] = useState(
    () => !window.matchMedia?.("(prefers-reduced-motion: reduce)").matches,
  );
  const [frame, setFrame] = useState(0);
  const [speed, setSpeed] = useState("1");
  const [page, setPage] = useState(0);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const clockTimer = useRef<number | undefined>(undefined);
  const [lightbox, setLightbox] = useState<{
    asset: RawPreviewAsset;
    label: string;
    frames: SampledFrame[];
  } | null>(null);
  const group =
    review.groups.find((item) => item.action === action) ?? review.groups[0];
  const candidates = group?.candidates ?? [];
  const pageCount = Math.max(1, Math.ceil(candidates.length / PAGE_SIZE));
  const visible = candidates.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE);
  const maxFrames = Math.max(
    1,
    ...visible.map((candidate) => candidate.frames.length),
  );
  const changed = ready.some(
    (item) => choices[item.action] !== item.selected_candidate_id,
  );
  const complete = ready.every(
    (item) => choices[item.action] && item.analysis_id,
  );
  const parentActive = activeStatuses.has(activeJob.status);
  const canAnalyzeGroup =
    group?.can_analyze ?? (review.groups.length === 1 && review.can_analyze);
  const initialized = useRef("");
  const analysisIds = useRef<Record<string, string | null>>({});
  useEffect(() => {
    if (initialized.current === storageKey) return;
    initialized.current = storageKey;
    let stored: Record<string, string> = {};
    try {
      const parsed = JSON.parse(localStorage.getItem(storageKey) ?? "{}");
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed))
        stored = parsed;
    } catch {}
    setChoices((current) =>
      Object.fromEntries(
        ready.map((item) => {
          const storedValid = item.candidates.some(
            (candidate) => candidate.id === stored[item.action],
          );
          const currentValid =
            analysisIds.current[item.action] === item.analysis_id &&
            item.candidates.some(
              (candidate) => candidate.id === current[item.action],
            );
          return [
            item.action,
            storedValid
              ? stored[item.action]
              : currentValid
                ? current[item.action]
                : defaults[item.action],
          ];
        }),
      ),
    );
    analysisIds.current = Object.fromEntries(
      review.groups.map((item) => [item.action, item.analysis_id]),
    );
    if (!review.groups.some((item) => item.action === action))
      setAction(ready[0]?.action ?? review.groups[0]?.action ?? "");
  }, [storageKey, signature]);
  useEffect(() => {
    try {
      localStorage.setItem(storageKey, JSON.stringify(choices));
    } catch {}
  }, [storageKey, choices]);
  useEffect(() => {
    setPage(0);
    setFrame(0);
  }, [action]);
  useEffect(() => {
    if (!playing || !visible.length) return;
    const duration =
      visible[0]?.frame_durations_ms[frame % visible[0].frames.length] ?? 125;
    const timer = window.setTimeout(
      () => setFrame((value) => (value + 1) % maxFrames),
      duration / Number(speed),
    );
    clockTimer.current = timer;
    return () => clearTimeout(timer);
  }, [playing, frame, maxFrames, speed, visible]);
  const analyze = async () => {
    setBusy(true);
    setError("");
    try {
      const submission = durableKey(
        `analysis:${review.job_id}:${group?.action ?? "all"}`,
      );
      onJob(
        await api.analyzeCycles(
          review.job_id,
          group ? [group.action] : undefined,
          submission.key,
        ),
      );
      if (submission.storageKey)
        sessionStorage.removeItem(submission.storageKey);
      onClose();
    } catch (reason) {
      setError(
        reason instanceof Error
          ? reason.message
          : "Cycle analysis could not be queued.",
      );
    } finally {
      setBusy(false);
    }
  };
  const revise = async () => {
    setBusy(true);
    setError("");
    try {
      const selections = Object.fromEntries(
        ready.map((item) => [
          item.action,
          {
            analysis_id: item.analysis_id!,
            candidate_id: choices[item.action],
          },
        ]),
      );
      const fingerprint = `revision:${review.job_id}:${JSON.stringify(selections)}`;
      const submission = durableKey(fingerprint);
      onJob(
        await api.reviseCycles(
          review.job_id,
          selections,
          sourceJob.package_id ?? sourceJob.base_package_id ?? undefined,
          submission.key,
        ),
      );
      if (submission.storageKey)
        sessionStorage.removeItem(submission.storageKey);
      onClose();
    } catch (reason) {
      setError(
        reason instanceof Error
          ? reason.message
          : "The revised sheet could not be queued.",
      );
    } finally {
      setBusy(false);
    }
  };
  return (
    <>
      <DialogShell
        title={`Review cycles (${ready.reduce((count, item) => count + item.candidates.length, 0)})`}
        description="Compare complete detected cycles before rebuilding the sprite sheet."
        size="media"
        onClose={onClose}
        suspended={!!lightbox}
      >
        <p className="editor-text editor-text--help">
          Unprocessed four-view frames with their original background. One
          choice applies to all directions.
        </p>
        {review.groups.length > 1 && (
          <>
            <div
              className="cycle-action-tabs"
              role="tablist"
              aria-label="Animation cycles"
            >
              {review.groups.map((item) => (
                <Button
                  compact
                  role="tab"
                  aria-selected={item.action === action}
                  key={item.action}
                  onClick={() => setAction(item.action)}
                >
                  {item.label}
                </Button>
              ))}
            </div>
            <div className="cycle-action-select">
              <SelectField
                label="Animation"
                value={action}
                onChange={(event) => setAction(event.target.value)}
              >
                {review.groups.map((item) => (
                  <option key={item.action} value={item.action}>
                    {item.label}
                  </option>
                ))}
              </SelectField>
            </div>
          </>
        )}
        {error && (
          <Status tone="danger" alert>
            {error}
          </Status>
        )}
        {group?.status === "unavailable" && (
          <div className="cycle-empty">
            <Status tone="warning">
              {group.message ?? "Saved cycle evidence is unavailable."}
            </Status>
            {canAnalyzeGroup && (
              <Button
                disabled={busy || parentActive}
                onClick={() => void analyze()}
              >
                Analyze saved video for cycles
              </Button>
            )}
          </div>
        )}
        {group?.status === "analyzing" || group?.status === "pending" ? (
          <Status>
            Finding cycles… The first export continues automatically.
          </Status>
        ) : null}
        {group?.status === "failed" && (
          <div className="cycle-empty">
            <Status tone="danger" alert>
              {group.message ??
                `No complete ${group.label} cycle candidates were published.`}
            </Status>
            {canAnalyzeGroup && (
              <Button
                disabled={busy || parentActive}
                onClick={() => void analyze()}
              >
                Analyze saved video for cycles
              </Button>
            )}
          </div>
        )}
        {group?.status === "ready" && candidates.length === 1 && (
          <Status>Only one complete cycle found.</Status>
        )}
        {group?.status === "ready" && candidates.length > 0 && (
          <>
            <div
              className="cycle-player-controls"
              role="group"
              aria-label="Cycle preview playback"
            >
              <Button
                compact
                onClick={() => {
                  if (clockTimer.current) clearTimeout(clockTimer.current);
                  setPlaying((value) => !value);
                }}
              >
                {playing ? <Pause size={15} /> : <Play size={15} />}{" "}
                {playing ? "Pause all" : "Play all"}
              </Button>
              <Button
                compact
                icon
                title="Previous frame"
                aria-label="Previous frame"
                onClick={() => {
                  if (clockTimer.current) clearTimeout(clockTimer.current);
                  setPlaying(false);
                  setFrame((value) => (value - 1 + maxFrames) % maxFrames);
                }}
              >
                <ChevronLeft size={15} />
              </Button>
              <span>
                Frame {(frame % maxFrames) + 1} / {maxFrames}
              </span>
              <Button
                compact
                icon
                title="Next frame"
                aria-label="Next frame"
                onClick={() => {
                  if (clockTimer.current) clearTimeout(clockTimer.current);
                  setPlaying(false);
                  setFrame((value) => (value + 1) % maxFrames);
                }}
              >
                <ChevronRight size={15} />
              </Button>
              <SelectField
                label="Speed"
                value={speed}
                onChange={(event) => setSpeed(event.target.value)}
              >
                <option value="0.5">0.5×</option>
                <option value="1">1×</option>
                <option value="1.5">1.5×</option>
                <option value="2">2×</option>
              </SelectField>
            </div>
            <div className="cycle-candidate-grid">
              {visible.map((candidate, index) => (
                <CandidateCard
                  key={candidate.id}
                  candidate={candidate}
                  ordinal={page * PAGE_SIZE + index + 1}
                  frame={frame}
                  selected={choices[group.action] === candidate.id}
                  onSelect={() =>
                    setChoices((value) => ({
                      ...value,
                      [group.action]: candidate.id,
                    }))
                  }
                  onEnlarge={() => {
                    const image =
                      candidate.frames[frame % candidate.frames.length];
                    setLightbox({
                      label: `${group.label} cycle ${page * PAGE_SIZE + index + 1} four-view frame`,
                      asset: {
                        id: image.id,
                        kind: "image",
                        pose_id: null,
                        filename: image.frame_id,
                        media_type: "image/png",
                        bytes: 0,
                        sha256: image.id,
                        url: image.url,
                      },
                      frames: candidate.frames.map((item, frameIndex) => ({
                        url: item.url,
                        label: `${group.label} cycle ${page * PAGE_SIZE + index + 1}, four-view frame ${frameIndex + 1}`,
                        duration_ms:
                          candidate.frame_durations_ms[frameIndex] ?? 125,
                      })),
                    });
                  }}
                />
              ))}
            </div>
            {pageCount > 1 && (
              <div className="cycle-pages">
                <Button
                  compact
                  disabled={page === 0}
                  onClick={() => setPage((value) => value - 1)}
                >
                  Previous candidates
                </Button>
                <span>
                  Page {page + 1} of {pageCount}
                </span>
                <Button
                  compact
                  disabled={page + 1 === pageCount}
                  onClick={() => setPage((value) => value + 1)}
                >
                  Next candidates
                </Button>
              </div>
            )}
            {group.system_candidate_id &&
              choices[group.action] !== group.system_candidate_id && (
                <Button
                  compact
                  onClick={() =>
                    setChoices((value) => ({
                      ...value,
                      [group.action]: group.system_candidate_id!,
                    }))
                  }
                >
                  <RotateCcw size={14} />
                  Use system pick
                </Button>
              )}
          </>
        )}
        <div className="cycle-change-summary">
          <strong>
            {changed
              ? `${ready.filter((item) => choices[item.action] !== item.selected_candidate_id).length} animation choice changed`
              : "No cycle changes"}
          </strong>
          <span className="editor-text editor-text--help">
            Updating rebuilds the complete package and keeps this render
            available.
          </span>
        </div>
        {parentActive && (
          <Status>
            The current job must finish before cycle choices can be applied.
          </Status>
        )}
        <footer className="dialog-actions">
          <Button onClick={onClose}>Close</Button>
          <Button
            variant="primary"
            disabled={
              busy ||
              parentActive ||
              !review.can_revise ||
              !changed ||
              !complete
            }
            onClick={() => void revise()}
          >
            Update sprite sheet
          </Button>
        </footer>
      </DialogShell>
      {lightbox && (
        <MediaLightbox {...lightbox} onClose={() => setLightbox(null)} />
      )}
    </>
  );
}

function CandidateCard({
  candidate,
  ordinal,
  frame,
  selected,
  onSelect,
  onEnlarge,
}: {
  candidate: CycleCandidate;
  ordinal: number;
  frame: number;
  selected: boolean;
  onSelect: () => void;
  onEnlarge: () => void;
}) {
  const sampledFrames = candidate.frames.map((item, frameIndex) => ({
    url: item.url,
    label: `Cycle ${ordinal}, four-view frame ${frameIndex + 1}`,
    duration_ms: candidate.frame_durations_ms[frameIndex] ?? 125,
  }));
  return (
    <article className={`cycle-candidate ${selected ? "selected" : ""}`}>
      <SampledFrameImage frames={sampledFrames} frame={frame} lazy />
      <Choice
        type="radio"
        name="cycle-candidate"
        checked={selected}
        onChange={onSelect}
        label={`Cycle ${ordinal}`}
        help={`${candidate.start_time_seconds.toFixed(2)}–${candidate.end_time_seconds.toFixed(2)} s · ${candidate.period_seconds.toFixed(2)} s · ${candidate.frames.length} frames`}
      />
      {candidate.system_selected && (
        <span className="cycle-system-pick">
          System pick · Middle complete cycle
        </span>
      )}
      <Button compact onClick={onEnlarge}>
        Enlarge
      </Button>
    </article>
  );
}
