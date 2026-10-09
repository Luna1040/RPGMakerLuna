import {
  useId,
  type ButtonHTMLAttributes,
  type InputHTMLAttributes,
  type ReactNode,
  type SelectHTMLAttributes,
} from "react";
import { LoaderCircle } from "lucide-react";

export function Button({
  variant = "standard",
  compact = false,
  icon = false,
  className = "",
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: "standard" | "primary" | "danger" | "warning";
  compact?: boolean;
  icon?: boolean;
}) {
  return (
    <button
      className={`editor-button editor-button--${variant} ${compact ? "editor-button--compact" : ""} ${icon ? "editor-button--icon" : ""} ${className}`}
      {...props}
    />
  );
}

function Field({
  id,
  label,
  help,
  error,
  children,
}: {
  id: string;
  label: string;
  help?: string;
  error?: string;
  children: ReactNode;
}) {
  const description =
    [help && `${id}-help`, error && `${id}-error`].filter(Boolean).join(" ") ||
    undefined;
  return (
    <div className="editor-field editor-field-label">
      <label htmlFor={id}>{label}</label>
      {typeof children === "function" ? null : children}
      {help && (
        <small id={`${id}-help`} className="editor-field-description">
          {help}
        </small>
      )}
      {error && (
        <small id={`${id}-error`} role="alert" className="editor-field-message">
          {error}
        </small>
      )}
      <span hidden data-description={description} />
    </div>
  );
}

export function TextField({
  label,
  help,
  error,
  id: suppliedId,
  ...props
}: InputHTMLAttributes<HTMLInputElement> & {
  label: string;
  help?: string;
  error?: string;
}) {
  const generated = useId();
  const id = suppliedId ?? generated;
  const describedBy =
    [help && `${id}-help`, error && `${id}-error`].filter(Boolean).join(" ") ||
    undefined;
  return (
    <Field id={id} label={label} help={help} error={error}>
      <input
        id={id}
        className="editor-control editor-control--text"
        aria-describedby={describedBy}
        aria-invalid={!!error}
        {...props}
      />
    </Field>
  );
}

export function NumberField({
  label,
  help,
  error,
  unit,
  id: suppliedId,
  ...props
}: InputHTMLAttributes<HTMLInputElement> & {
  label: string;
  help?: string;
  error?: string;
  unit?: string;
}) {
  const generated = useId();
  const id = suppliedId ?? generated;
  const describedBy =
    [help && `${id}-help`, error && `${id}-error`].filter(Boolean).join(" ") ||
    undefined;
  return (
    <Field id={id} label={label} help={help} error={error}>
      <span className="input-with-suffix">
        <input
          id={id}
          className="editor-control editor-control--text"
          type="number"
          aria-describedby={describedBy}
          aria-invalid={!!error}
          {...props}
        />
        {unit && <span className="editor-field-affix">{unit}</span>}
      </span>
    </Field>
  );
}

export function SelectField({
  label,
  help,
  children,
  id: suppliedId,
  ...props
}: SelectHTMLAttributes<HTMLSelectElement> & {
  label: string;
  help?: string;
  children: ReactNode;
}) {
  const generated = useId();
  const id = suppliedId ?? generated;
  return (
    <Field id={id} label={label} help={help}>
      <select
        id={id}
        className="editor-control editor-control--select"
        aria-describedby={help ? `${id}-help` : undefined}
        {...props}
      >
        {children}
      </select>
    </Field>
  );
}

export function Choice({
  label,
  help,
  ...props
}: InputHTMLAttributes<HTMLInputElement> & { label: string; help?: string }) {
  return (
    <label className="editor-choice">
      <input className="editor-control editor-control--choice" {...props} />
      <span>
        <strong>{label}</strong>
        {help && (
          <small className="editor-text editor-text--help">{help}</small>
        )}
      </span>
    </label>
  );
}

export function Panel({
  title,
  kicker,
  actions,
  children,
  className = "",
}: {
  title: string;
  kicker?: string;
  actions?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section className={`editor-panel ${className}`}>
      <header className="editor-panel__header">
        <div>
          {kicker && <p className="editor-kicker">{kicker}</p>}
          <h2 className="editor-heading editor-heading--panel">{title}</h2>
        </div>
        {actions}
      </header>
      <div className="editor-panel__body">{children}</div>
    </section>
  );
}

export function Status({
  children,
  tone = "normal",
  alert = false,
}: {
  children: ReactNode;
  tone?: "normal" | "success" | "warning" | "danger";
  alert?: boolean;
}) {
  return (
    <p
      role={alert ? "alert" : "status"}
      className={`editor-text editor-text--${tone === "normal" ? "status" : tone}`}
    >
      {children}
    </p>
  );
}

export function BusySpinner({ label }: { label: string }) {
  return (
    <span className="editor-busy-spinner" role="status">
      <LoaderCircle aria-hidden="true" />
      <span>{label}</span>
    </span>
  );
}
