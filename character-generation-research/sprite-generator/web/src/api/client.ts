import type {
  ApiErrorEnvelope,
  ActivityResponse,
  Catalog,
  ConfigDocument,
  ConnectionStatus,
  Job,
  Package,
  RenderDraft,
  RenderPlan,
  RawPreviews,
  Upload,
  Workspace,
  CycleReview,
} from "./types";
export class ApiError extends Error {
  constructor(
    message: string,
    public status: number,
    public fields: Record<string, string> = {},
  ) {
    super(message);
  }
}
let csrf = "";
function sameOriginUrl(path: string) {
  return new URL(path.replace(/^\//, ""), document.baseURI).toString();
}
function parseError(body: ApiErrorEnvelope, status: number) {
  const fields = Object.fromEntries(
    (body.error?.fields ?? []).map((x) => [x.path.join("."), x.message]),
  );
  return new ApiError(
    body.error?.message ??
      (typeof body.detail === "string" ? body.detail : body.detail?.[0]?.msg) ??
      `Request failed (${status})`,
    status,
    fields,
  );
}
async function request<T>(path: string, init: RequestInit = {}) {
  const method = init.method ?? "GET";
  const response = await fetch(sameOriginUrl(path), {
    credentials: "same-origin",
    ...init,
    headers: {
      Accept: "application/json",
      ...(init.body instanceof FormData
        ? {}
        : { "Content-Type": "application/json" }),
      ...(!["GET", "HEAD"].includes(method) && csrf
        ? { "X-CSRF-Token": csrf }
        : {}),
      ...init.headers,
    },
  });
  if (!response.ok) {
    let body: ApiErrorEnvelope = {};
    try {
      body = await response.json();
    } catch {}
    throw parseError(body, response.status);
  }
  return response.status === 204
    ? (undefined as T)
    : (response.json() as Promise<T>);
}
export type Session = {
  authenticated: boolean;
  operator?: string;
  csrf_token?: string;
  auth_required?: boolean;
  auth_enabled?: boolean;
};
const keepSession = (s: Session) => {
  csrf = s.csrf_token ?? csrf;
  return s;
};
export const api = {
  session: async () => keepSession(await request<Session>("/api/session")),
  login: async (username: string, password: string) =>
    keepSession(
      await request<Session>("/api/session", {
        method: "POST",
        body: JSON.stringify({ username, password }),
      }),
    ),
  logout: () => request<void>("/api/session", { method: "DELETE" }),
  catalog: () => request<Catalog>("/api/catalog"),
  upload: (file: File, onProgress?: (n: number) => void) =>
    new Promise<Upload>((resolve, reject) => {
      const xhr = new XMLHttpRequest(),
        data = new FormData();
      data.append("file", file);
      xhr.open("POST", sameOriginUrl("/api/uploads"));
      xhr.withCredentials = true;
      xhr.setRequestHeader("Accept", "application/json");
      if (csrf) xhr.setRequestHeader("X-CSRF-Token", csrf);
      xhr.upload.onprogress = (e) =>
        e.lengthComputable &&
        onProgress?.(Math.round((e.loaded / e.total) * 100));
      xhr.onerror = () => reject(new ApiError("Upload connection failed.", 0));
      xhr.onload = () => {
        if (xhr.status >= 200 && xhr.status < 300)
          resolve(JSON.parse(xhr.responseText));
        else {
          try {
            reject(parseError(JSON.parse(xhr.responseText), xhr.status));
          } catch {
            reject(new ApiError("Upload failed.", xhr.status));
          }
        }
      };
      xhr.send(data);
    }),
  createWorkspace: (upload_id: string, name: string) =>
    request<Workspace>("/api/workspaces", {
      method: "POST",
      body: JSON.stringify({ upload_id, name }),
    }),
  workspace: (id: string) =>
    request<Workspace>(`/api/workspaces/${encodeURIComponent(id)}`),
  deleteWorkspace: (id: string) =>
    request<void>(`/api/workspaces/${encodeURIComponent(id)}`, {
      method: "DELETE",
      body: JSON.stringify({ confirmation: id }),
    }),
  plan: (draft: RenderDraft, signal?: AbortSignal) =>
    request<RenderPlan>("/api/plans", {
      method: "POST",
      body: JSON.stringify(draft),
      signal,
    }),
  createJob: (draft: RenderDraft, key: string) =>
    request<Job>("/api/jobs", {
      method: "POST",
      headers: { "Idempotency-Key": key },
      body: JSON.stringify({ request: draft }),
    }),
  jobs: async () => (await request<{ jobs: Job[] }>("/api/jobs?limit=50")).jobs,
  job: (id: string) => request<Job>(`/api/jobs/${encodeURIComponent(id)}`),
  previews: (id: string) =>
    request<RawPreviews>(`/api/jobs/${encodeURIComponent(id)}/previews`),
  cycles: (id: string) =>
    request<CycleReview>(`/api/jobs/${encodeURIComponent(id)}/cycles`),
  analyzeCycles: (id: string, actions: string[] | undefined, key: string) =>
    request<Job>(`/api/jobs/${encodeURIComponent(id)}/cycle-analysis`, {
      method: "POST",
      headers: { "Idempotency-Key": key },
      body: JSON.stringify(actions ? { actions } : {}),
    }),
  reviseCycles: (
    id: string,
    selections: Record<string, { analysis_id: string; candidate_id: string }>,
    basePackageId: string | undefined,
    key: string,
  ) =>
    request<Job>(`/api/jobs/${encodeURIComponent(id)}/cycle-revisions`, {
      method: "POST",
      headers: { "Idempotency-Key": key },
      body: JSON.stringify({
        selections,
        ...(basePackageId ? { base_package_id: basePackageId } : {}),
      }),
    }),
  activity: (id: string) =>
    request<ActivityResponse>(
      `/api/jobs/${encodeURIComponent(id)}/activity?after=0&limit=100`,
    ),
  stop: (id: string) =>
    request<Job>(`/api/jobs/${encodeURIComponent(id)}/stop`, {
      method: "POST",
      body: "{}",
    }),
  resume: (id: string) =>
    request<Job>(`/api/jobs/${encodeURIComponent(id)}/resume`, {
      method: "POST",
      body: "{}",
    }),
  package: (id: string) =>
    request<Package>(`/api/packages/${encodeURIComponent(id)}`),
  config: () => request<ConfigDocument>("/api/config"),
  saveConfig: (
    revision: string,
    changes: { path: string[]; value?: unknown; reset?: boolean }[],
  ) =>
    request<ConfigDocument>("/api/config", {
      method: "PATCH",
      body: JSON.stringify({ revision, changes }),
    }),
  connection: () =>
    request<ConnectionStatus>("/api/connection-check", {
      method: "POST",
      body: "{}",
    }),
};
