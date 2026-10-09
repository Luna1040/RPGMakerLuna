# Sprite Extractor code documentation

These documents describe the maintained Python pipeline, web interface, and external
contracts. Start with the agent overview when returning to the code after a gap.

- [`agent-overview.md`](agent-overview.md) — compact future-session bootstrap,
  invariants, change map, and verification checklist
- [`architecture.md`](architecture.md) — execution flows and module-by-module
  reference
- [`configuration.md`](configuration.md) — merge order, schema, CLI overrides,
  workflow model mapping, and validation
- [`animation-authoring.md`](animation-authoring.md) — add animations with YAML
  definitions, prompt files, dependencies, and frame-selection policies
- [`output-format.md`](output-format.md) — generated directory layout, state
  machine, manifests, timing, origins, and provenance
- [`development.md`](development.md) — setup, tests, fixtures, and safe workflow
  update procedure
- [`web-user-guide.md`](web-user-guide.md) — uploads, render settings, previews,
  downloads, saved work, and server defaults
- [`web-deployment.md`](web-deployment.md) — independent web build, server and
  worker setup, persistence, and reverse-proxy deployment
- [`web-api.md`](web-api.md) — browser/backend requests, authentication, jobs,
  configuration, and deliverables
- [`web-widget-library.md`](web-widget-library.md) — locally owned theme and
  reusable web controls
- [`web-theme-provenance.md`](web-theme-provenance.md) — source hashes and
  licenses for the independent editor-theme adaptation
- [`web-verification.md`](web-verification.md) — automated web, worker,
  packaging, and independent-install acceptance evidence
- [`web-lan-submission-fix.md`](web-lan-submission-fix.md) — LAN submission
  failure diagnosis, activity reporting, and the Samus Run acceptance scope

## Implementation plans

- [`cycle-review-design.md`](cycle-review-design.md)
  — cycle comparison, system-pick defaults, saved analysis, and
  immutable sprite-package revisions; not yet implemented
- [`animation-definitions-implementation-plan.md`](animation-definitions-implementation-plan.md)
  — implemented YAML animation catalog, shared workflow templates, dependency
  resolution, generic frame selection, and cache migration
- [`web-gui-implementation-plan.md`](web-gui-implementation-plan.md)
  — browser UI implementation plan, independent parent-theme reuse, render/configuration
  controls, durable jobs, downloads, and later animation-authoring support

## Documentation scope

The source of truth is the Python package under `src/sprite_extractor`, the
frontend under `web/src`, their package manifests, the command wrapper,
`config.default.yaml`, and the contract/browser tests.
The large ComfyUI API JSON files and PNG dummy assets are data rather than
hand-maintained program logic; these documents cover the runtime contracts that
the code and tests impose on those assets without reproducing their full binary
or graph contents. The ignored local `config.yaml` is intentionally excluded.
