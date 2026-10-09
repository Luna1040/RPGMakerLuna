import { useEffect, useState } from "react";
import { Activity, CircleStop, RotateCcw } from "lucide-react";
import { api } from "../api/client";
import type { Job } from "../api/types";
import { Button, Panel, Status } from "../ui/Controls";
const labels: Record<string, string> = {
  queued: "Queued",
  preparing: "Preparing",
  generating: "Generating",
  extracting: "Extracting frames",
  removing_backgrounds: "Removing backgrounds",
  packaging: "Packaging",
  ready: "Ready",
  stop_requested: "Stopping after current step",
  stopped: "Stopped",
  failed: "Failed",
  recovery_required: "Recovery required",
};
export function JobProgress({
  job,
  onJob,
  onOpenActivity,
}: {
  job: Job;
  onJob: (job: Job) => void;
  onOpenActivity?: () => void;
}) {
  const [connected, setConnected] = useState(true),
    [busy, setBusy] = useState(false);
  useEffect(() => {
    if (
      ["ready", "stopped", "failed", "recovery_required"].includes(job.status)
    )
      return;
    let active = true;
    const poll = async () => {
      try {
        const fresh = await api.job(job.id);
        if (active) {
          setConnected(true);
          onJob(fresh);
        }
      } catch {
        if (active) setConnected(false);
      }
    };
    const timer = setInterval(() => void poll(), 2000);
    void poll();
    return () => {
      active = false;
      clearInterval(timer);
    };
  }, [job.id, job.status, onJob]);
  const act = async (kind: "stop" | "resume") => {
    setBusy(true);
    try {
      onJob(await api[kind](job.id));
    } finally {
      setBusy(false);
    }
  };
  const determinate =
    job.total_stages > 0 && job.completed_stages <= job.total_stages;
  return (
    <Panel
      title={
        job.kind === "cycle_analysis" && job.status === "ready"
          ? "Cycles ready"
          : (labels[job.status] ?? job.phase)
      }
      kicker="Generation progress"
      className="progress-panel"
      actions={<a href={`?job=${encodeURIComponent(job.id)}`}>Saved render</a>}
    >
      <div className="progress-top">
        <div>
          <strong>{job.current_stage ?? job.message}</strong>
          <p className="editor-text editor-text--secondary">
            {job.completed_stages} of {job.total_stages} stages ·{" "}
            {job.cached_stages} cached · {Math.floor(job.elapsed_seconds / 60)}m{" "}
            {job.elapsed_seconds % 60}s
          </p>
        </div>
        {onOpenActivity && (
          <Button onClick={onOpenActivity}>
            <Activity size={15} />
            View activity
          </Button>
        )}
        {!["ready", "stopped", "failed", "recovery_required"].includes(
          job.status,
        ) && (
          <Button
            variant="warning"
            disabled={busy}
            onClick={() => void act("stop")}
          >
            <CircleStop size={15} />
            {job.status === "queued"
              ? "Cancel queued job"
              : "Stop after current step"}
          </Button>
        )}
        {job.resume_allowed && (
          <Button disabled={busy} onClick={() => void act("resume")}>
            <RotateCcw size={15} />
            Resume
          </Button>
        )}
      </div>
      {determinate ? (
        <progress
          aria-label="Generation progress"
          max={job.total_stages}
          value={job.completed_stages}
        />
      ) : (
        <progress aria-label="Generation in progress" />
      )}
      {!connected && (
        <Status tone="warning">
          Connection lost. Generation continues on the server; this page will
          reconnect automatically.
        </Status>
      )}
      {job.status === "stop_requested" && (
        <Status>
          The current server operation will finish. Completed artifacts will be
          retained.
        </Status>
      )}
      {job.status === "recovery_required" && (
        <Status tone="warning" alert>
          {job.message} The server will not submit replacement work while the
          previous outcome is unknown.
        </Status>
      )}
      {job.status === "failed" && (
        <Status tone="danger" alert>
          {job.message}
        </Status>
      )}
      <details>
        <summary>Technical details</summary>
        <dl className="technical">
          <dt>Job ID</dt>
          <dd>{job.id}</dd>
          <dt>Resolved seed</dt>
          <dd>{job.resolved_seed}</dd>
          <dt>Phase</dt>
          <dd>{job.phase}</dd>
        </dl>
      </details>
    </Panel>
  );
}
