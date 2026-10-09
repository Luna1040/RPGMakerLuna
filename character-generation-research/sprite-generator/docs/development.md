# Development and verification

## Local setup

From the Sprite Extractor repository root:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python -m pip install -e '.[test]'
```

FFmpeg and FFprobe are external executables. Integration runs also need an
already-running ComfyUI server with the configured nodes and models. Contract
tests mock model inference and do not judge generated art.
An autouse fixture blocks unmocked `urllib.request.urlopen` calls; HTTP contract
tests replace that boundary with explicit fakes. Keep this guard when adding
CLI tests so an outdated orchestration mock cannot reach a live ComfyUI server.

## Tests in this checkout

This repository requires every test command to run in a transient
systemd scope capped at 16 GB of host memory with swap disabled. From the
Sprite Extractor root, preserve that policy with:

```bash
systemd-run --wait --collect --pipe \
  -p MemoryMax=16G -p MemorySwapMax=0 \
  -p WorkingDirectory="$(pwd)" \
  env PYTHONPATH=src .venv/bin/python -m pytest -q
```

Run a focused test file first when possible, using the same wrapper. Commands
that only inspect files, run `git diff --check`, or compile without executing
tests do not need the scope.

The suite is split by contract:

- `test_generate_character_contract.py`: graph leaf restrictions, model
  coverage, dummy assets/rendering, postprocess graph construction, config
  layering, API submission shape, durable generation/resume, defaults, CLI
  forwarding, and workflow aliases.
- `test_character_animations_contract.py`: full/original package layouts,
  action counts, 20 full-workflow WebPs and infinite loops, shared cuts,
  per-animation centering, invalid alpha, and staged orchestration.
- `test_sprite_sheet_contract.py`: premultiplied-alpha behavior, noise cleanup,
  blob errors/cuts, centering/origins, WebP timing, nearest-frame sampling,
  lower-median cycle selection, and CLI validation.
- `test_staged_workflow_contract.py`: split graph integrity, dependency closure,
  stage-wave submission, durable resume and ambiguity recovery, staged CLI
  planning, selection-only packaging, pose output, and source/package parity.
- `test_animation_definitions_contract.py`: strict catalogs, overlays, prompt
  variants, dependency ordering, shared-template parity, and packaged resources.
- `test_definition_runtime_contract.py`: YAML-only actions, revision reuse,
  cached pose extraction/recovery, package-count revisions, and read-only cache
  planning.
- `test_definition_migration_contract.py`: legacy state conversion, verified
  artifact imports, unknown submissions, and recovery-timeout barriers.

## Updating a ComfyUI workflow

1. Export API-format JSON, not the browser/editor workflow format.
2. Replace the source asset and packaged copy consistently.
3. Identify recognized output nodes and every reachable upstream
   `.safetensors` leaf. Do not include disconnected branches.
4. Update node IDs, required classes/titles, output names, and model mappings in
   code/default config only when the graph contract actually changed.
5. Confirm renderer mutations remain limited to the approved leaf set.
6. Update prompt-synchronization assertions if the original workflow must share
   prompt text with the full graph.
7. Run the focused workflow/config contract tests, then the full suite.

For ordinary animation changes, edit `animation-definitions.yaml` and `prompts/`;
see [Animation authoring](animation-authoring.md). Graph changes belong in the
two `workflows/templates/` resources and their contracts in
`workflow_templates.py`. Synchronize portable resources from the tool root:

```bash
python scripts/sync_definition_resources.py
python scripts/sync_definition_resources.py --check
```

The nine `workflows/staged/<stage>.json` files and packaged copies are retained
legacy parity/migration fixtures. Preserve those baselines when changing the
new catalog or templates. Each active template must retain exact connected
model coverage, valid links, and its declared semantic bindings.

The test suite intentionally makes silent graph drift fail. Avoid weakening
exact-coverage checks to make a new graph pass; revise the documented contract
and mappings deliberately.

## Safe change checklist

Install web development dependencies with
`python -m pip install -e '.[web,test]'`. Web API and worker tests must use
mocked ComfyUI behavior. `create_app` accepts a runner callable for scheduler
tests, while `scheduler=False` leaves jobs queued for route-only tests. Never
point automated tests at live inference.

- Preserve the ignored `config.yaml`; never replace or inspect it for docs.
- Keep portable paths based on repository location or `$HOME`, never a named
  user's home directory.
- Keep deterministic ordering for directories, directions, actions, frames, and
  canonical JSON.
- Use `atomic_write_json`/`atomic_write_bytes` for durable state and manifests.
- Keep temporary downloads and packages off their final names until complete.
- Update docs and contract tests when changing CLI semantics, output JSON, node
  contracts, split/centering behavior, or resume identity.
- End with `git diff --check` and inspect `git status --short` for generated or
  private files.
