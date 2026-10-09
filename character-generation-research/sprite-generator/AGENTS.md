# Sprite Extractor agent instructions

Before changing this project, read [`docs/agent-overview.md`](docs/agent-overview.md).
It is the compact orientation guide for the execution paths, hard-coded ComfyUI
contracts, resume rules, output invariants, and the safest places to make common
changes. Follow its links into the more detailed documents when the task touches
configuration, output metadata, or pipeline internals.

Keep these local rules in mind:

- `config.yaml` is an ignored, machine-local override. Never commit it or expose
  its contents. Change portable defaults in `config.default.yaml`.
- Treat workflow node IDs, node titles, and connected model inputs as versioned
  interfaces. Update the workflow validation and contract tests together.
- Do not infer image quality from a successful run. The tool records
  `quality_evaluated: false` and verifies execution, not visual correctness.
- Preserve atomic state/output writes and resumability when changing generation
  or packaging.
- Run the contract tests using the repository's required transient
  systemd memory scope. The exact command is in
  [`docs/development.md`](docs/development.md).
