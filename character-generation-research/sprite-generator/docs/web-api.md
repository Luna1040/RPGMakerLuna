# Web API contract

The web API is served below the configured base path. Examples below assume the
default `/`. JSON responses use UTF-8. IDs are opaque lowercase strings.

## Access boundary

`POST /api/session` accepts `{"username":"…","password":"…"}` and sets an
HttpOnly, SameSite=Strict session cookie. It returns:

```json
{"authenticated":true,"operator":"operator","csrf_token":"…","auth_required":true}
```

`GET /api/session` returns the same public session description (without a
password). `DELETE /api/session` signs out. Every state-changing request other
than sign-in requires the cookie and an `X-CSRF-Token` header. Requests with an
`Origin` header must match the request origin. Deployments without configured
credentials only permit loopback clients and return an anonymous local session.
With explicit `--no-auth`, network clients receive an authenticated operator
session with `operator: "network"` and `auth_required: false`. CSRF tokens and
same-origin mutation checks remain required.

Errors consistently use:

```json
{"error":{"code":"validation_error","message":"Invalid request","fields":[{"path":["body","seed"],"message":"…"}]}}
```

## Uploads and workspaces

`POST /api/uploads` accepts one streamed multipart field named `file`. Success
is `201` with:

```json
{"id":"up_…","filename":"hero.png","media_type":"image/png","width":512,"height":512,"bytes":12345,"sha256":"…","thumbnail_url":"/api/artifacts/ar_…"}
```

The deployment defaults are 20 MiB encoded and 40 million decoded pixels.
`POST /api/workspaces` accepts `{"upload_id":"up_…","name":"Hero"}` and
returns `201` with `{"id":"ws_…","name":"Hero","source":{upload fields},
"created_at":"…","storage_bytes":12345}`. Replacing an image means creating
a new workspace. `GET /api/workspaces/{id}` returns that record plus its jobs.
`DELETE /api/workspaces/{id}` requires
`{"confirmation":"<workspace id>"}` and succeeds only when no queued or active
job refers to it.

## Catalog, configuration, and connection

`GET /api/catalog` returns:

```json
{"revision":"sha256","actions":[{"id":"idle","label":"Idle","description":"","stage":"idle","selection":{"method":"uniform","frames":4,"include_last":false},"frame_count":{"value":4,"editable":true,"minimum":2},"conceptual_loop":true,"animated_file":true}],"poses":[{"id":"standing","label":"Standing","stage":"stop","frame":"last"}],"capabilities":{"directions":["right","left","back","front"],"prompt_styles":["neutral","feminine"],"split_methods":["blobs","quarters"],"animation_authoring":false}}
```

`GET /api/config` returns `{"revision":"sha256","path":"display-safe path",
"fields":[…]}`. Each field is `{"path":["postprocess","sdpose_batch_size"],
"label":"…","kind":"integer|number|string|seed|model","value":…,"default":…,
"overridden":false,"required":true,"minimum":1,"maximum":null,"unit":"…",
"help":"…"}`. Seed values are decimal strings. Model mappings include
`node_id` and `input` only in their advanced metadata.

`PATCH /api/config` accepts `{"revision":"…","changes":[{"path":[…],
"value":…},{"path":[…],"reset":true}]}`. It validates the complete merged
candidate and returns the new configuration document. A stale revision is
`409 config_conflict`. Unrelated YAML keys are preserved and the previous bytes
are saved beside the file as `.bak`.

`POST /api/connection-check` accepts no fields and returns
`{"ok":true,"url":"http://…","message":"…","models":[]}`. It performs
read-only ComfyUI object/model discovery and never submits or interrupts work.

## Plans and immutable jobs

A render draft has this shape:

```json
{"workspace_id":"ws_…","actions":["idle","run"],"frame_counts":{"idle":4,"run":6},"style":"neutral","seed":{"mode":"random"},"sprite_size":256,"generation":{"width":400,"height":512,"pad_top_percent":0},"split_method":"blobs","animation_overrides":{"run":{"duration_seconds":2.0,"fps":24.0}}}
```

For a fixed seed, `seed` is `{"mode":"fixed","value":"9223372036854775807"}`.
All seed values in requests and responses are decimal strings.

Each catalog action also includes `generation` with `duration_seconds`, `fps`,
`frame_length`, and `effective_duration_seconds` for animation details.

`POST /api/plans` validates a draft without writing files or contacting ComfyUI.
It returns `{"request":<normalized draft>,"resolved_seed":null,"summary":
{"animation_count":2,"frames_per_direction":10,"directions":4},"stages":[
{"id":"run","label":"Run","reason":"selected|dependency","cache":"hit|miss|awaiting_dependency|awaiting_submission|unavailable"}],"definition_snapshot":"sha256","config_snapshot":"sha256"}`.

`POST /api/jobs` accepts `{"request":<render draft>}` and requires an
`Idempotency-Key` header (8–200 printable ASCII characters). It atomically
persists snapshots before enqueueing and returns `202` (or the original response
for a repeated key) with the job resource. A random seed is resolved once here.
An adjusted draft retains reusable generation by sending the earlier job's
`resolved_seed` as a fixed seed. A new variation sends random mode and receives
a new generation-set seed.

A job resource is:

```json
{"id":"job_…","workspace_id":"ws_…","status":"queued|preparing|generating|extracting|removing_backgrounds|packaging|ready|stop_requested|stopped|failed|recovery_required","phase":"queued","current_stage":null,"completed_stages":0,"total_stages":2,"cached_stages":0,"resolved_seed":"123","created_at":"…","started_at":null,"finished_at":null,"elapsed_seconds":0,"stop_requested":false,"resume_allowed":false,"message":"Queued","package_id":null,"request":{…},"links":{"self":"/api/jobs/job_…","events":"/api/jobs/job_…/events"}}
```

Jobs also include `kind` (`render`, `cycle_analysis`, or `cycle_revision`),
`parent_job_id`, and `base_package_id`. Child jobs retain their source job's
config, definition, resolved seed, and pinned generation evidence. An
analysis-only job reaches `ready` with no new `package_id`; its base package
remains available.

### Cycle review

`GET /api/jobs/{id}/cycles` returns `job_id`, `groups`, `can_revise`, and
`can_analyze`. Only captured definitions with `selection.method: cycle` appear.
Each group contains `action`, `label`, `stage_id`, `status`, `message`,
`can_analyze`, `analysis_id`, `sample_set_id`, `system_candidate_id`,
`selected_candidate_id`, `selection_origin`, `frame_count`, and `candidates`.
Status is `unavailable`, `pending`, `analyzing`, `ready`, or `failed`.

Candidates contain `id`, the interval's `start_time_seconds`, `end_time_seconds`
and `period_seconds`, `system_selected`, `frame_durations_ms`, and ordered
`frames`. Each frame has an opaque asset `id`, source `frame_id`, `pts`,
`time_seconds`, and `url`. `GET /api/cycle-assets/{id}` serves registered frames
inline after managed-path and digest validation. These GETs never start
decoding, inference, or a job.

`POST /api/jobs/{id}/cycle-analysis` accepts `{}` for eligible missing analyses,
or `{"actions":["run"]}`. It explicitly queues analysis of retained videos and
reuses compatible saved pose evidence. `POST /api/jobs/{id}/cycle-revisions`
accepts a complete cycle-selection map:

```json
{"selections":{"run":{"analysis_id":"…","candidate_id":"…"}},"base_package_id":"pkg_…"}
```

Both require `Idempotency-Key`, return `202` with a durable child job, and use
the existing progress/activity/stop/resume routes. The base package is optional
when none has been published. Invalid or stale choices, missing source
evidence, active parents, and recovery barriers cannot start revisions.
Revisions never submit video generation or pose extraction; new selected frames
may require background removal. Failure does not publish a previous package as
the result of the child job.

`GET /api/jobs?limit=50` returns the newest jobs as `{"jobs":[…],"next":null}`.
`GET /api/jobs/{id}` returns one job. `GET /api/jobs/{id}/events?cursor=0`
is an SSE stream. Each event has `id`, event `state|progress|activity|log|snapshot`, and
JSON data `{"sequence":1,"timestamp":"…","job":<job resource>,"message":"…"}`.
History is bounded; an old cursor first receives a current `snapshot`. Clients
may poll the job resource if streaming is unavailable.

`GET /api/jobs/{id}/activity?after=0&limit=100` restores the durable, sanitized
ComfyUI activity log for a progress modal:

```json
{"job":{},"current":{"sequence":4,"timestamp":"…","state":"running","operation":"generation","stage_id":"run","prompt_id":"…","message":"ComfyUI is running the work","error":null},"activities":[],"next_cursor":4}
```

`state` is `submitting`, `queued`, `running`, `waiting`, `completed`, `failed`,
`idle`, `disconnected`, or `unknown`. `operation` is `generation`, `sdpose`,
`background_removal`, `packaging`, or `comfy`. Errors have `code`, `message`, `retryable`,
and `recovery_required`. `waiting` means an accepted prompt is absent from the
queue and its terminal history is not available yet. `unknown` preserves the
no-duplicate recovery barrier after an ambiguous submission. The endpoint also
returns the current job resource so clients can distinguish ComfyUI activity
from CPU postprocessing and terminal job failure. An empty activity log means
the job has not contacted ComfyUI; the API does not infer activity from a
workflow phase. Activity data excludes graphs, prompt text, model configuration,
input values, filesystem paths, and tracebacks. Activity is observational: a
failure to record it never changes submission or recovery behavior.
With `after=0`, `activities` contains the latest bounded window in ascending
order. Pass `next_cursor` as `after` on later polls to receive newer transitions.

`POST /api/jobs/{id}/stop` returns `202`. Queued work becomes `stopped`; active
work becomes `stop_requested` and stops at the next safe core boundary.
`POST /api/jobs/{id}/resume` returns `202` for stopped/failed recoverable work,
retaining the original request, resolved seed, snapshots, generation set, and
submission IDs. An unresolved ambiguous submission returns `409
recovery_required` and is never resubmitted.

`GET /api/jobs/{id}/previews` is a read-only view of raw generation outputs as
stages complete:

```json
{"job_id":"job_…","stage_owners":{"run":"idle","stop":"idle","idle":"idle"},"stages":[{"character":"hero","stage_id":"stop","label":"Stop","reason":"dependency","action_id":null,"owner_action_id":"idle","dependency_for":["idle"],"assets":[{"id":"pv_…","kind":"video","pose_id":null,"filename":"video.mp4","media_type":"video/mp4","bytes":123,"sha256":"…","url":"/api/previews/pv_…"}]}]}
```

Only revisions captured for that immutable job at a completed stage boundary
appear. `kind` is `video`, `pose`, or a single representative raw `image` when
the stage has no pose image. Pending, partial, corrupt, hash-mismatched, and
historical revisions are omitted. `GET /api/previews/{id}` streams the validated
recorded image or video inline and supports ordinary HTTP range requests. These
routes never submit inference, run postprocessing, or publish package files.
For work started by a pre-upgrade scheduler, a live, uniquely owning worker may
use its persisted completed-stage count and active revision as a read-only
compatibility fallback. A ready legacy job recovers selected action revision IDs
from its published engine manifest; ambiguous dependency revisions remain hidden.
`stage_owners` is present even while `stages` is empty, so clients can place one
spinner for every planned stage before its artifact exists. Each stage is owned
by the selected consuming action whose root stage occurs first in the immutable
job dependency-plan order. Thus an idle-only job assigns `run`, `stop`, and
`idle` to `idle`; when `run` is itself selected it owns its root stage. Each
emitted stage repeats its owner as `owner_action_id`. Ownership does not change
`action_id`, `reason`, or `dependency_for` and does not mutate the job.

## Packages and artifacts

`GET /api/packages/{id}` is available only after atomic publication:

```json
{"id":"pkg_…","job_id":"job_…","created_at":"…","sheet":{"artifact_id":"ar_…","filename":"character-sheet-256h.png","media_type":"image/png","bytes":1,"url":"/api/artifacts/ar_…"},"metadata":{…},"manifest":{…},"animations":[{"action":"run","direction":"right","artifact_id":"ar_…","filename":"run-right-256h.webp","url":"/api/artifacts/ar_…"}],"still_actions":["crouch"],"download_url":"/api/packages/pkg_…/download","action_downloads":{"run":"/api/packages/pkg_…/download?action=run"},"preview":{"layout":{},"frame_durations_ms":{}}}
```

`GET /api/artifacts/{id}` streams an authorized managed file and supports the
usual conditional/range behavior supplied by the ASGI server. `GET
/api/packages/{id}/download` streams a server-built ZIP. `?action=<id>` returns
only that action's animated directions. ZIPs contain the final sheet, metadata,
package manifest, and selected WebPs; they exclude source images, configuration,
prompts, logs, intermediate frames, and generation videos. Downloads never
enqueue work.
