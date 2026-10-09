# LAN submission and ComfyUI activity

The first reported web render stayed busy while ComfyUI was idle. The server
had recorded the image upload and dependency plan, but no job creation request;
the durable queue contained no render job.

The Generate handler called `crypto.randomUUID()` before its `try/finally`
block. That API is unavailable in an ordinary HTTP browser session on a LAN
address. An exception therefore left the submitting state set and never
reached the server. Request-key creation now supports this browser context,
and preparation errors pass through the same error display and cleanup as
submission errors.

A browser regression disables `crypto.randomUUID`, uploads a synthetic image,
and verifies one job submission plus the generation-activity modal. This is
separate from ComfyUI inference and does not evaluate image quality.

The activity modal reports server and ComfyUI operations for the saved job,
including failures. It can be dismissed without stopping work and reopened
from the render's progress panel. The API retains activity across browser
disconnects. See [Web API](web-api.md) and [Web verification](web-verification.md)
for the activity contract and verification evidence.

The follow-up live acceptance is limited to one Samus Run animation request,
using the web interface on the LAN HTTP address. No visual art review is part
of that acceptance.

Offline verification passed 128 Python tests and 11 browser tests. The live
browser submitted job `job_1a0aa096ef884feab39baad2e645672a` exactly once and
opened the activity modal. Its request selects Run, eight frames per direction,
256 px sprite height, and neutral style. The resolved seed is
`4673571923068067156`. The initial generation prompt was observed progressing
through submitting, queued, and running. The same job reached Ready after
approximately 315 seconds, with successful generation, SDPose, and
background-removal operations recorded in the activity feed.

Package `pkg_2199c7ca820643ca99795dcb99bbdd90` contains an 8-column by 4-row
sheet with 256 px cells and four Run WebPs (right, left, back, front). Raw
preview metadata exposed the original video and a representative generated
frame before final packaging. There was one job-creation POST, no retries, and
no visual inspection. The live audit log is `/tmp/sprite-live-samus-run.log`.
Additional verification evidence is in [Web verification](web-verification.md).
