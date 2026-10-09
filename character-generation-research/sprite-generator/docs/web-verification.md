# Web verification

## Raw stage previews

Raw-preview verification builds the frontend only into
`/tmp/sprite-extractor-web-preview-static`; production `web_static` is not
changed. Focused API and worker contracts passed **15 tests**: immutable
per-job revision capture, legacy live-worker fallback guarded by process
identity, incomplete-stage hiding, dependency mapping, path/hash validation,
authenticated range requests, and no-scheduler/static-root CLI and environment
seams. The isolated Playwright suite passed **2 tests**: progressive polling,
pending and unavailable states, video/image labels, keyboard-focused media
lightbox, Escape focus return, and unchanged action selection.

Final post-preview Python suite: **127 passed** in 41.71 seconds, with zero
errors, failures, or skips. JUnit report:
`/tmp/sprite-web-preview-final-pytest.xml`; log:
`/tmp/sprite-web-preview-final-pytest.log`.

The separate read-only preview service on LAN port 8788 returned 200 for its
shell, compiled asset, and anonymous session; an unknown preview job returned
404. The original GUI service remained PID 637748 with its original activation
timestamp. No operational verification requested catalog, configuration,
generation, or inference.

Automated web verification uses mocked HTTP and a child-only mocked engine boundary. It never reads `config.yaml`, contacts a live ComfyUI server, or performs inference.

## Python contracts

Run from the Sprite Extractor root in the required 16 GB/no-swap scope:

```bash
systemd-run --wait --collect --pipe -p MemoryMax=16G -p MemorySwapMax=0 \
  -p WorkingDirectory="$(pwd)" \
  env PYTHONPATH=src PYTHONDONTWRITEBYTECODE=1 \
  "$HOME/.conda/envs/comfyui/bin/python" -m pytest -q
```

The pre-web baseline completed with 97 passing tests. The web-focused API/core suite passed 14 tests during implementation; it covers upload decoding limits, CSRF/origin checks, fixed and random idempotency, immutable snapshots, recovery boundaries, publication/ZIP filtering, base-path assets, scheduler recovery, and a real scheduler-to-subprocess-worker path. The subprocess test replaces only `execute_request` in the child process; it still exercises durable SQLite state, worker ownership, and package publication.

Final frozen-suite result: **118 passed** in 31.19 seconds. Its JUnit report is `/tmp/sprite-web-final-pytest.xml` (118 tests, zero errors, failures, and skips); the complete console log is `/tmp/sprite-web-final-pytest.log`. The final targeted Comfy client protocol run also passed **5 tests**: definitive HTTP 400 node errors become retryable rejected records, an accepted prompt ID wins over accompanying node errors, missing IDs become durable unknown outcomes and do not create another prompt, upload descriptors are scoped by server URL, and cooperative stop only blocks postprocess submissions.

## Browser checks

Run from `web/` in the required user-manager scope:

```bash
systemd-run --user --scope -p MemoryMax=16G -p MemorySwapMax=0 npm run test:e2e
```

The backend integration fixture uses `SPRITE_EXTRACTOR_TEST_PYTHON` when set,
falling back to `python3`. Install this project's `.[web,test]` extras into
that interpreter. Its server owns a `TemporaryDirectory`, including its
configuration file and SQLite data, and removes it when Playwright stops the
server.

The browser harness rejects unexpected API paths. Final `npm run test:e2e` result: **8 passed** (7 mocked-client tests plus 1 real-backend test). The final portable-fixture rerun used `SPRITE_EXTRACTOR_TEST_PYTHON=$HOME/.conda/envs/comfyui/bin/python` in the required user scope and passed 7 mocked tests in 4.8 seconds plus the backend test in 3.4 seconds. Passing checks cover keyboard/mobile selection, delayed saved-job rehydration in both catalog/default arrival orders, natural-pixel sheet zoom, frame direction changes, exact frame-duration playback controls, and still-pose playback disablement.

The real-backend test starts its own local Python Uvicorn server with `scheduler=False` and a test-only read-only Comfy client seam. It serves the compiled package under `/sprites`, then verifies six catalog actions, a valid PNG upload and thumbnail/workspace path, Settings navigation, exactly one queued job, and query-based refresh/reconnect without a second `POST /sprites/api/jobs`. It does not use Vite, a live ComfyUI server, or inference. The standard `test:e2e` script runs this test after the mocked browser suite.

The saved-defaults acceptance test also passes: after uploading a draft, editing and saving the Sprite size default in Settings leaves that draft at its original size on return to Create sprites; only **Apply updated defaults** changes it.

The workspace-deletion acceptance test passes: Recent renders displays storage use, blocks deletion for recovery-required work, requires the exact workspace ID, returns focus after Escape, sends the confirmed delete request, and removes the deleted workspace row.

The settings conflict/theme acceptance test passes: a 409 save keeps the edited value visible, Discard restores the loaded value, Reset sends the inheritance reset change, and all four local themes apply while the theme selector remains keyboard-focusable.

## Standalone package acceptance

A temporary copy of this subproject was created without `.git`, `config.yaml`, `node_modules`, caches, or output media. In that copy, `web/npm ci` and `web/npm run build` succeeded under the memory scope. A wheel was built and installed with its `web` extra into an isolated temporary virtual environment. The installed wheel, launched outside the copied source tree under `/sprites`, served the compiled shell, packaged Inter font, and catalog endpoint successfully.

## Activity-modal regression

After the durable Comfy activity feed was added, the frozen Python suite passed
**128 tests** in 40.12 seconds (72 warnings; no errors, failures, or skips).
The JUnit report is `/tmp/sprite-web-activity-final-pytest.xml`; the log is
`/tmp/sprite-web-activity-final-pytest.log`.

The final browser command, run from `web/` in the required user 16 GB/no-swap
scope with `SPRITE_EXTRACTOR_TEST_PYTHON` set to the CUDA environment, passed
**11 tests**: 10 fail-closed mocked UI cases in 5.6 seconds and one compiled
frontend against an isolated Python server in 3.5 seconds. Its log is
`/tmp/sprite-web-activity-playwright-final.log`. The activity cases cover the
insecure-HTTP `crypto.randomUUID` fallback, automatic activity-dialog opening,
and dismissing it without changing job state. Raw-preview polling uses an
explicit fixture publication switch, avoiding timing-dependent assertions. No
live server, ComfyUI inference, or private configuration was used.

## Authorized live Samus run

One LAN browser run was authorized and executed against `http://192.168.50.8:8787`.
It uploaded `samus.jpg`, cleared the action list, selected only Run, and made one
`POST /api/jobs`: `job_1a0aa096ef884feab39baad2e645672a`. The job reached Ready
in about 315 seconds with resolved seed `4673571923068067156`, 256px cells,
and eight Run frames for each of right, left, back, and front.

The browser activity modal opened at submission and the durable feed showed
completed generation, SDPose, and background-removal prompts. Raw-preview
metadata appeared after generation with one video and one image asset. The
published package `pkg_2199c7ca820643ca99795dcb99bbdd90` reports an 8-column,
4-row sheet and exactly four Run WebP exports. The full run record is
`/tmp/sprite-live-samus-run.log`. Verification inspected metadata and response
state only; it did not perform visual artwork review or create a retry job.

## Stage ownership regressions

Focused offline preview ownership contracts passed **6 tests** in 4.84 seconds.
They verify that `stage_owners` is returned before any state/artifact exists,
that a reversed `[walk, idle]` request assigns their shared Stop dependency to
Idle using immutable snapshot execution order, and that a selected Run root
remains owned by Run.

Focused Playwright raw-preview checks passed **3 tests** in 9.9 seconds. They
verify exactly one shared-dependency spinner and raw-media card, accessible
lightbox opening/Escape return, continuing Stop-requested spinner ownership,
and spinner removal once stopped. These tests use fail-closed mocked APIs and
no live service or inference.

Final Python verification after the stage-owner changes: **129 passed** in 43.06
seconds (76 warnings; zero errors, failures, or skips). JUnit:
`/tmp/sprite-web-stage-owners-final-pytest.xml`; log:
`/tmp/sprite-web-stage-owners-final-pytest.log`.

An exploratory extraction-stage spinner extension was deliberately reverted:
postprocessing activity can retain a stale generation stage ID. Card spinners
therefore remain limited to generating or stop-requested jobs with a current
stage; postprocessing remains visible in the Activity modal. The focused
browser ownership result above remains applicable without a new UI behavior.

## Deployed read-only smoke

After the guarded deployment restart, a scoped read-only HTTP smoke test returned
200 for the deployed shell and for
`/api/jobs/job_8c8145b763b54efda245daaafede3b3f/previews`. The response had
nine populated `stage_owners` entries and nine stage records. It sent only GET
requests; no job, configuration, inference, or service-control request was
made. Final related evidence is **129 Python tests passed** and **3 focused
browser ownership tests passed**.

## Results autoplay regression

The focused Results Playwright scenario passed **1 test** in 5.9 seconds in the
required user 16 GB/no-swap scope. It verifies default automatic frame advance,
Pause holding the current frame, automatic replay after direction and animated
action changes, natural-size sheet scaling, and disabled stopped playback for a
still action. The test uses mocked API data only and did not contact a live
server or run inference.

## Cycle review verification

Focused cycle API and worker contracts passed **2 tests** in 18.39 seconds in a
16 GB/no-swap transient systemd scope (`/tmp/cycle-web-api.log`). They use an
actual FastAPI app and SQLite Store with its scheduler disabled: durable cycle
asset URLs survive a fresh app instance; corrupt, missing, and ancestor-symlink
assets return 404; GET is read-only; a valid revision persists its parent,
request, configuration, and definition snapshots; identical idempotency replay
returns the same child; and stale choices or a reused key on another parent
return 409. The worker regression proves a failed `complete:false` rebuild
cannot publish a stale selected package.

The pinned candidate/mask-cache contract passed **1 test** in 0.62 seconds
(`test_pinned_cycle_candidate_feeds_packer_without_analysis_and_reuses_masks`).
It verifies an immutable selected candidate supplies the packaged frames and
timing evidence, does not invoke extraction or SDPose, and reuses the shared
mask while processing only a newly selected frame.

Final Python verification: **134 passed** in 54.05 seconds with 84 warnings,
zero failures, errors, or skips. It ran in transient unit
`sprite-cycle-pytest-final` with 16 GB memory and swap disabled; log:
`/tmp/sprite-cycle-final.log`, JUnit: `/tmp/sprite-cycle-final.xml`.

The fail-closed browser suite passed **12 tests** in 10.3 seconds. The isolated
compiled-static Python backend check passed **1 test** in 4.5 seconds using
`/tmp/sprite-extractor-cycle-review-static`, scheduler disabled, and the
temporary backend fixture. These tests made no inference request and did not
use a production service.

An additional real-backend cycle browser scenario passed **1 test** in 3.5
seconds: the saved render opens the chooser, displays the system pick, accepts
an alternate, and creates a durable queued revision through the real API while
retaining the parent. Its initial fixture omitted required public package
descriptors and crashed the results component; completing the fixture resolved
that failure without production changes. Browser coverage totals **14 passing
tests** across the UI suite and the two backend scenarios.

The default Playwright build and preview now use
`/tmp/sprite-extractor-playwright-static`, so verification does not replace the
served production assets. The backend fixture requires an explicit static root.

After deployment, a scoped read-only smoke check passed for the live session
(`authenticated: true`, `auth_required: false`), application shell, and cycle
availability of an existing job. The idle user-managed service was restarted;
no active render was interrupted. No generation, inference, configuration
mutation, or visual artwork review was performed for this feature.
