import { useEffect, useState } from "react";
import { ArrowRight, RefreshCw, Sparkles, Trash2 } from "lucide-react";
import { api } from "../api/client";
import type { Job, RenderDraft, Workspace } from "../api/types";
import { Button, Panel, Status, TextField } from "../ui/Controls";
import { JobProgress } from "./JobProgress";
import { Results } from "./Results";
import { DialogShell } from "../ui/DialogShell";
import { ActivityModal } from "./ActivityModal";

export function RecentPage({
  onAdjust,
  onWorkspaceDeleted,
}: {
  onAdjust: (draft: Partial<RenderDraft>) => void;
  onWorkspaceDeleted: (workspaceId: string) => void;
}) {
  const [jobs, setJobs] = useState<Job[] | null>(null);
  const [selected, setSelected] = useState<Job | null>(null);
  const [error, setError] = useState("");
  const [workspaces, setWorkspaces] = useState<Record<string, Workspace>>({});
  const [deleteTarget, setDeleteTarget] = useState<Workspace | null>(null);
  const [confirmation, setConfirmation] = useState("");
  const [deleting, setDeleting] = useState(false);
  const [activityOpen, setActivityOpen] = useState(false);
  const load = () =>
    api
      .jobs()
      .then((items) => {
        setJobs(items);
        setError("");
        void Promise.all(
          [...new Set(items.map((item) => item.workspace_id))].map((id) =>
            api.workspace(id).then((workspace) => [id, workspace] as const),
          ),
        ).then((entries) => setWorkspaces(Object.fromEntries(entries)));
      })
      .catch((reason) => setError(reason.message));
  useEffect(() => {
    void load();
  }, []);
  return (
    <>
      <div className="page-title">
        <div>
          <p className="editor-kicker">Saved work</p>
          <h1 className="editor-heading editor-heading--page">
            Recent renders
          </h1>
          <p className="editor-text editor-text--secondary">
            Generation continues on the server when this browser is closed.
          </p>
        </div>
        <Button onClick={() => void load()}>
          <RefreshCw size={15} />
          Refresh
        </Button>
      </div>
      {error && (
        <Status tone="danger" alert>
          {error}
        </Status>
      )}
      <Panel title="Renders" kicker={`${jobs?.length ?? 0} retained`}>
        <div className="recent-list">
          {jobs === null ? (
            <Status>Loading recent renders…</Status>
          ) : jobs.length === 0 ? (
            <p className="editor-text editor-text--empty">No renders yet.</p>
          ) : (
            jobs.map((job) => (
              <article key={job.id} className="recent-row">
                {job.thumbnail_url && (
                  <img
                    className="recent-thumbnail"
                    src={job.thumbnail_url}
                    alt=""
                  />
                )}
                <div className={`status-dot ${job.status}`} />
                <div>
                  <strong>{job.message || job.id}</strong>
                  <span>
                    {new Date(job.created_at).toLocaleString()} ·{" "}
                    {job.request.actions.join(", ")}
                  </span>
                  <span>
                    {job.status.replaceAll("_", " ")} · seed {job.resolved_seed}
                  </span>
                  {workspaces[job.workspace_id] && (
                    <span>
                      Workspace {workspaces[job.workspace_id].name} ·{" "}
                      {formatBytes(workspaces[job.workspace_id].storage_bytes)}{" "}
                      stored
                    </span>
                  )}
                </div>
                <div className="recent-actions">
                  <Button compact onClick={() => setSelected(job)}>
                    Open render <ArrowRight size={14} />
                  </Button>
                  <Button compact onClick={() => onAdjust(job.request)}>
                    Adjust and generate
                  </Button>
                  <Button
                    compact
                    onClick={() =>
                      onAdjust({ ...job.request, seed: { mode: "random" } })
                    }
                  >
                    <Sparkles size={14} />
                    New variation
                  </Button>
                  <Button
                    compact
                    variant="danger"
                    disabled={workspaceHasActiveWork(
                      workspaces[job.workspace_id],
                    )}
                    title={
                      workspaceHasActiveWork(workspaces[job.workspace_id])
                        ? "Stop or resolve active work before deleting this workspace."
                        : "Delete workspace"
                    }
                    onClick={() => {
                      const workspace = workspaces[job.workspace_id];
                      if (workspace) {
                        setDeleteTarget(workspace);
                        setConfirmation("");
                      }
                    }}
                  >
                    <Trash2 size={14} />
                    Delete workspace
                  </Button>
                </div>
              </article>
            ))
          )}
        </div>
      </Panel>
      {selected && selected.status !== "ready" && (
        <JobProgress
          job={selected}
          onOpenActivity={() => setActivityOpen(true)}
          onJob={(fresh) => {
            setSelected(fresh);
            setJobs(
              (current) =>
                current?.map((job) => (job.id === fresh.id ? fresh : job)) ??
                null,
            );
          }}
        />
      )}{" "}
      {selected?.status === "ready" && selected.package_id && (
        <Results packageId={selected.package_id} job={selected} />
      )}
      {deleteTarget && (
        <DialogShell
          alert
          title={`Delete ${deleteTarget.name}?`}
          description="This permanently removes the server workspace."
          onClose={() => setDeleteTarget(null)}
        >
          <div className="dialog-content">
            <p className="editor-text">
              This removes the uploaded source, intermediate and resumable
              generation artifacts, and every retained render in this workspace
              ({formatBytes(deleteTarget.storage_bytes)}). Files you already
              downloaded to your computer are unchanged.
            </p>
            <TextField
              label={`Type ${deleteTarget.id} to confirm`}
              value={confirmation}
              autoComplete="off"
              onChange={(event) => setConfirmation(event.target.value)}
            />
            {error && (
              <Status tone="danger" alert>
                {error}
              </Status>
            )}
          </div>
          <footer className="dialog-actions">
            <Button onClick={() => setDeleteTarget(null)}>Cancel</Button>
            <Button
              variant="danger"
              disabled={deleting || confirmation !== deleteTarget.id}
              onClick={async () => {
                setDeleting(true);
                try {
                  await api.deleteWorkspace(deleteTarget.id);
                  const deletedId = deleteTarget.id;
                  setJobs(
                    (current) =>
                      current?.filter(
                        (item) => item.workspace_id !== deletedId,
                      ) ?? null,
                  );
                  if (selected?.workspace_id === deletedId) setSelected(null);
                  setDeleteTarget(null);
                  setConfirmation("");
                  setError("");
                  onWorkspaceDeleted(deletedId);
                } catch (reason) {
                  setError(
                    reason instanceof Error
                      ? reason.message
                      : "Workspace could not be deleted.",
                  );
                } finally {
                  setDeleting(false);
                }
              }}
            >
              <Trash2 size={15} />
              Delete workspace
            </Button>
          </footer>
        </DialogShell>
      )}
      {activityOpen && selected && (
        <ActivityModal
          job={selected}
          onJob={(fresh) => {
            setSelected(fresh);
            setJobs(
              (current) =>
                current?.map((item) => (item.id === fresh.id ? fresh : item)) ??
                null,
            );
          }}
          onClose={() => setActivityOpen(false)}
        />
      )}
    </>
  );
}

function workspaceHasActiveWork(workspace?: Workspace) {
  return (
    workspace?.jobs?.some((job) =>
      [
        "queued",
        "preparing",
        "generating",
        "extracting",
        "removing_backgrounds",
        "packaging",
        "stop_requested",
        "recovery_required",
      ].includes(job.status),
    ) ?? true
  );
}

function formatBytes(bytes: number) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KiB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MiB`;
}
