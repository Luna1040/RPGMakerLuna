import { useEffect, useMemo, useState } from "react";
import { RotateCcw, Save, Server } from "lucide-react";
import { api, ApiError } from "../api/client";
import type {
  ConfigDocument,
  ConfigField,
  ConnectionStatus,
} from "../api/types";
import {
  Button,
  NumberField,
  Panel,
  SelectField,
  Status,
  TextField,
} from "../ui/Controls";
import { THEMES, type ThemeId } from "../theme/themes";

const groupName = (field: ConfigField) =>
  field.path[0] === "animation_frames"
    ? "Animation frame defaults"
    : field.path[0] === "postprocess"
      ? "Postprocessing"
      : field.path[0] === "workflow_models"
        ? "Generation models"
        : field.path[0] === "postprocess_workflow_models"
          ? "Postprocess models"
          : ["comfyui_url", "generation_timeout"].includes(field.path[0])
            ? "Connection"
            : "Render defaults";

export function SettingsPage({
  theme,
  onTheme,
  onDefaultsSaved,
}: {
  theme: ThemeId;
  onTheme: (value: ThemeId) => void;
  onDefaultsSaved: () => void;
}) {
  const [document, setDocument] = useState<ConfigDocument | null>(null);
  const [values, setValues] = useState<Record<string, string | number>>({});
  const [resets, setResets] = useState<string[]>([]);
  const [error, setError] = useState("");
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});
  const [saved, setSaved] = useState("");
  const [checking, setChecking] = useState(false);
  const [connection, setConnection] = useState<ConnectionStatus | null>(null);
  const load = () =>
    api
      .config()
      .then((doc) => {
        setDocument(doc);
        setValues(
          Object.fromEntries(
            doc.fields.map((field) => [field.path.join("."), field.value]),
          ),
        );
        setResets([]);
        setError("");
        setFieldErrors({});
      })
      .catch((reason) => setError(reason.message));
  useEffect(() => {
    void load();
  }, []);
  const dirty = useMemo(
    () =>
      !!document &&
      (resets.length > 0 ||
        document.fields.some(
          (field) => values[field.path.join(".")] !== field.value,
        )),
    [document, values, resets],
  );
  const groups = Object.entries(
    (document?.fields ?? []).reduce<Record<string, ConfigField[]>>(
      (all, field) => {
        (all[groupName(field)] ??= []).push(field);
        return all;
      },
      {},
    ),
  );
  const save = async () => {
    if (!document) return;
    const changes = document.fields.reduce<
      { path: string[]; value?: unknown; reset?: boolean }[]
    >((all, field) => {
      const key = field.path.join(".");
      if (resets.includes(key)) all.push({ path: field.path, reset: true });
      else if (values[key] !== field.value)
        all.push({ path: field.path, value: values[key] });
      return all;
    }, []);
    try {
      const doc = await api.saveConfig(document.revision, changes);
      setDocument(doc);
      setValues(
        Object.fromEntries(
          doc.fields.map((field) => [field.path.join("."), field.value]),
        ),
      );
      setResets([]);
      setError("");
      setFieldErrors({});
      setSaved(
        "Defaults saved. Existing queued and running jobs keep their snapshots.",
      );
      onDefaultsSaved();
    } catch (reason) {
      if (reason instanceof ApiError) setFieldErrors(reason.fields);
      setError(
        reason instanceof ApiError && reason.status === 409
          ? "The settings file changed on the server. Reload to review its current values before saving."
          : reason instanceof Error
            ? reason.message
            : "Settings could not be saved.",
      );
    }
  };
  return (
    <>
      <div className="page-title">
        <div>
          <p className="editor-kicker">Server and interface</p>
          <h1 className="editor-heading editor-heading--page">Settings</h1>
          <p className="editor-text editor-text--secondary">
            Saved render defaults apply to future drafts. Running and queued
            jobs retain their snapshots.
          </p>
        </div>
      </div>
      <div className="settings-grid">
        <Panel title="Appearance" kicker="This browser">
          <SelectField
            label="Theme"
            value={theme}
            onChange={(event) => onTheme(event.target.value as ThemeId)}
          >
            {THEMES.map((item) => (
              <option key={item.id} value={item.id}>
                {item.label}
              </option>
            ))}
          </SelectField>
          <p className="editor-text editor-text--help">
            Theme preference is stored only for Sprite Extractor in this
            browser.
          </p>
        </Panel>
        <Panel
          title="ComfyUI connection"
          kicker="Read-only check"
          actions={
            <Button
              compact
              disabled={checking}
              onClick={async () => {
                setChecking(true);
                try {
                  setConnection(await api.connection());
                } catch (reason) {
                  setConnection({
                    ok: false,
                    url: "",
                    message:
                      reason instanceof Error
                        ? reason.message
                        : "Check failed.",
                    models: [],
                  });
                } finally {
                  setChecking(false);
                }
              }}
            >
              <Server size={14} />
              Check connection
            </Button>
          }
        >
          <p className="editor-text">
            The address is resolved from this backend server, which may be a
            different machine from your browser.
          </p>
          {connection && (
            <Status
              tone={connection.ok ? "success" : "danger"}
              alert={!connection.ok}
            >
              {connection.message}
            </Status>
          )}
        </Panel>
      </div>
      <Panel
        title="Saved server defaults"
        kicker={document ? document.path : "Loading"}
        actions={
          <div className="inline-actions">
            <Button
              disabled={!dirty}
              onClick={() => {
                if (document) {
                  setValues(
                    Object.fromEntries(
                      document.fields.map((field) => [
                        field.path.join("."),
                        field.value,
                      ]),
                    ),
                  );
                  setResets([]);
                  setSaved("");
                }
              }}
            >
              Discard
            </Button>
            <Button
              variant="primary"
              disabled={!dirty}
              onClick={() => void save()}
            >
              <Save size={15} />
              Save defaults
            </Button>
          </div>
        }
      >
        {error && (
          <div className="conflict" role="alert">
            <p>{error}</p>
            <Button compact onClick={() => void load()}>
              <RotateCcw size={14} />
              Reload settings
            </Button>
          </div>
        )}
        {saved && <Status tone="success">{saved}</Status>}
        {!document ? (
          <Status>Loading editable settings…</Status>
        ) : (
          <div className="config-groups">
            {groups.map(([name, fields]) => (
              <fieldset className="config-group" key={name}>
                <legend>{name}</legend>
                {fields.map((field) => (
                  <ConfigControl
                    key={field.path.join(".")}
                    field={field}
                    value={values[field.path.join(".")]}
                    reset={resets.includes(field.path.join("."))}
                    error={
                      fieldErrors[field.path.join(".")] ??
                      fieldErrors[`body.${field.path.join(".")}`]
                    }
                    discoveredModels={connection?.models ?? []}
                    onChange={(value) => {
                      setValues((current) => ({
                        ...current,
                        [field.path.join(".")]: value,
                      }));
                      setResets((current) =>
                        current.filter((key) => key !== field.path.join(".")),
                      );
                    }}
                    onReset={() =>
                      setResets((current) =>
                        current.includes(field.path.join("."))
                          ? current.filter(
                              (key) => key !== field.path.join("."),
                            )
                          : [...current, field.path.join(".")],
                      )
                    }
                  />
                ))}
              </fieldset>
            ))}
          </div>
        )}
      </Panel>
    </>
  );
}

function ConfigControl({
  field,
  value,
  reset,
  onChange,
  onReset,
  error,
  discoveredModels,
}: {
  field: ConfigField;
  value: string | number;
  reset: boolean;
  onChange: (value: string | number) => void;
  onReset: () => void;
  error?: string;
  discoveredModels: unknown[];
}) {
  const effective = reset ? field.default : value;
  const choices = Array.isArray(field.advanced?.choices)
    ? (field.advanced.choices as string[])
    : Array.isArray(field.advanced?.filenames)
      ? (field.advanced.filenames as string[])
      : [];
  const modelChoices = [
    ...new Set([
      ...choices,
      ...discoveredModels.flatMap((item) =>
        typeof item === "string"
          ? [item]
          : item && typeof item === "object" && "filename" in item
            ? [String(item.filename)]
            : [],
      ),
    ]),
  ];
  const listId = `models-${field.path.join("-").replace(/[^a-z0-9-]/gi, "-")}`;
  return (
    <div className={`config-field ${reset ? "will-inherit" : ""}`}>
      <div>
        {field.kind === "integer" || field.kind === "number" ? (
          <NumberField
            label={field.label}
            value={effective}
            min={field.minimum ?? undefined}
            max={field.maximum ?? undefined}
            step={field.kind === "integer" ? 1 : "any"}
            unit={field.unit}
            help={field.help}
            error={error}
            onChange={(event) =>
              onChange(
                field.kind === "integer"
                  ? Math.trunc(Number(event.target.value))
                  : Number(event.target.value),
              )
            }
          />
        ) : field.kind === "model" ? (
          <>
            <TextField
              label={field.label}
              value={effective}
              help={field.help}
              error={error}
              list={listId}
              onChange={(event) => onChange(event.target.value)}
            />
            <datalist id={listId}>
              {modelChoices.map((item) => (
                <option key={item} value={item} />
              ))}
            </datalist>
          </>
        ) : (
          <TextField
            label={field.label}
            value={effective}
            required={field.required}
            help={field.help}
            error={error}
            onChange={(event) => onChange(event.target.value)}
          />
        )}
      </div>
      <div className="config-source">
        <span>
          {reset || !field.overridden ? "Inherited default" : "Server override"}{" "}
          · {String(field.default)}
        </span>
        <Button
          compact
          onClick={onReset}
          disabled={!field.overridden && !reset}
        >
          {reset ? "Keep override" : "Reset to inherited"}
        </Button>
      </div>
      {field.advanced && (
        <details>
          <summary>Technical field details</summary>
          <code>{field.path.join(".")}</code>
          {field.advanced.node_id != null && (
            <code>
              {" "}
              · node {String(field.advanced.node_id)} /{" "}
              {String(field.advanced.input ?? "value")}
            </code>
          )}
        </details>
      )}
    </div>
  );
}
