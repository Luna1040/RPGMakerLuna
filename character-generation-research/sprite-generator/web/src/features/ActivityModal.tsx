import { useEffect, useState } from "react";
import {
  AlertTriangle,
  Check,
  Clock3,
  Cpu,
  LoaderCircle,
  ServerOff,
} from "lucide-react";
import { api } from "../api/client";
import type { Activity, ActivityResponse, Job } from "../api/types";
import { Button, Status } from "../ui/Controls";
import { DialogShell } from "../ui/DialogShell";

const stateLabels: Record<string, string> = {
  submitting: "Submitting to ComfyUI",
  queued: "Queued in ComfyUI",
  waiting: "Waiting",
  running: "Running in ComfyUI",
  completed: "Completed",
  failed: "Failed",
  idle: "ComfyUI idle",
  disconnected: "ComfyUI disconnected",
  unknown: "Status unknown",
};
const readable = (value: string) =>
  value.replaceAll("_", " ").replace(/^./, (letter) => letter.toUpperCase());
const stateLabel = (value: string) => stateLabels[value] ?? readable(value);
const operationLabel = (value: string) =>
  operationLabels[value] ?? readable(value);
const operationLabels: Record<string, string> = {
  generation: "Generation",
  sdpose: "Pose extraction",
  background_removal: "Background removal",
  comfy: "ComfyUI",
};

export function ActivityModal({
  job,
  clientError,
  onJob,
  onClose,
}: {
  job: Job | null;
  clientError?: string;
  onJob: (job: Job) => void;
  onClose: () => void;
}) {
  const [activity, setActivity] = useState<ActivityResponse | null>(null);
  const [connected, setConnected] = useState(true);
  useEffect(() => {
    setActivity(null);
    if (!job) {
      return;
    }
    let active = true;
    let timer: number | undefined;
    const refresh = async () => {
      try {
        const value = await api.activity(job.id);
        if (active) {
          setActivity(value);
          setConnected(true);
          onJob(value.job);
        }
      } catch {
        if (active) setConnected(false);
      } finally {
        if (
          active &&
          !["ready", "stopped", "failed", "recovery_required"].includes(
            job.status,
          )
        )
          timer = window.setTimeout(() => void refresh(), 1500);
      }
    };
    void refresh();
    return () => {
      active = false;
      if (timer) clearTimeout(timer);
    };
  }, [job?.id, job?.status]);
  const visibleActivity = activity?.job.id === job?.id ? activity : null;
  const current = visibleActivity?.current ?? null;
  const title =
    clientError ||
    current?.error ||
    job?.status === "failed" ||
    job?.status === "recovery_required"
      ? "Generation needs attention"
      : job?.status === "ready"
        ? job.kind === "cycle_analysis"
          ? "Cycles ready"
          : "Generation complete"
        : "Generation activity";
  return (
    <DialogShell
      title={title}
      description="Live server and ComfyUI operations for this render."
      onClose={onClose}
      alert={
        !!clientError ||
        !!current?.error ||
        job?.status === "failed" ||
        job?.status === "recovery_required"
      }
    >
      {clientError ? (
        <Status tone="danger" alert>
          {clientError}
        </Status>
      ) : (
        <CurrentActivity current={current} job={job} connected={connected} />
      )}
      {current?.error && (
        <Status tone="danger" alert>
          {current.error.message}
          {current.error.recovery_required
            ? " Resume only after the server confirms the recorded submission can be recovered."
            : current.error.retryable
              ? " Check the connection, then use Resume when the server offers it."
              : ""}
        </Status>
      )}
      {visibleActivity?.activities.length ? (
        <ol className="activity-list">
          {visibleActivity.activities.map((item) => (
            <li
              key={item.sequence}
              className={`activity-item activity-item--${item.state}`}
            >
              <ActivityIcon item={item} />
              <div>
                <strong>
                  {operationLabel(item.operation)} · {stateLabel(item.state)}
                </strong>
                <span>
                  {item.message ||
                    item.stage_id?.replaceAll("_", " ") ||
                    "Server activity"}
                </span>
                <small>{new Date(item.timestamp).toLocaleTimeString()}</small>
                {item.prompt_id && (
                  <details>
                    <summary>Technical details</summary>
                    <code>Prompt ID: {item.prompt_id}</code>
                  </details>
                )}
                {item.error && (
                  <p className="editor-text editor-text--danger">
                    {item.error.message}
                    {item.error.recovery_required
                      ? " Recovery is required before resubmission."
                      : item.error.retryable
                        ? " Check the connection and resume recorded work when available."
                        : ""}
                  </p>
                )}
              </div>
            </li>
          ))}
        </ol>
      ) : (
        !clientError && (
          <p className="editor-text editor-text--help">
            Recorded operations will appear here as the worker reaches them.
          </p>
        )
      )}
      <footer className="dialog-actions">
        <Button onClick={onClose}>Dismiss</Button>
      </footer>
    </DialogShell>
  );
}

function CurrentActivity({
  current,
  job,
  connected,
}: {
  current: Activity | null | undefined;
  job: Job | null;
  connected: boolean;
}) {
  if (!connected)
    return (
      <Status tone="warning">
        Activity updates are temporarily unavailable. The server job continues
        independently.
      </Status>
    );
  if (job?.status === "failed")
    return (
      <Status tone="danger" alert>
        {job.message || "The server job failed."}
      </Status>
    );
  if (job?.status === "recovery_required")
    return (
      <Status tone="warning" alert>
        {job.message ||
          "The server must recover the recorded submission before continuing."}
      </Status>
    );
  if (!current)
    return (
      <Status>
        {job
          ? job.status === "queued"
            ? "Job queued; waiting for the worker."
            : "Waiting for recorded server activity."
          : "Preparing the job request."}
      </Status>
    );
  return (
    <div className="activity-current">
      <ActivityIcon item={current} />
      <div>
        <strong>{stateLabel(current.state)}</strong>
        <p className="editor-text editor-text--secondary">
          {operationLabel(current.operation)}
          {current.stage_id
            ? ` · ${current.stage_id.replaceAll("_", " ")}`
            : ""}
        </p>
        {current.message && <p className="editor-text">{current.message}</p>}
      </div>
    </div>
  );
}

function ActivityIcon({ item }: { item: Activity }) {
  if (item.state === "failed") return <AlertTriangle aria-hidden="true" />;
  if (item.state === "completed") return <Check aria-hidden="true" />;
  if (item.state === "disconnected") return <ServerOff aria-hidden="true" />;
  if (
    item.state === "queued" ||
    item.state === "idle" ||
    item.state === "unknown"
  )
    return <Clock3 aria-hidden="true" />;
  if (item.state === "running") return <Cpu aria-hidden="true" />;
  return <LoaderCircle className="spin" aria-hidden="true" />;
}
