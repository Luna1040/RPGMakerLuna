import { useEffect, useId, useRef, type ReactNode } from "react";
import { createPortal } from "react-dom";

export interface DialogShellProps {
  title: string;
  description?: string;
  onClose: () => void;
  children: ReactNode;
  alert?: boolean;
  size?: "standard" | "media";
  suspended?: boolean;
}

const focusableSelector = [
  "button:not([disabled])",
  "[href]",
  "input:not([disabled])",
  "select:not([disabled])",
  "textarea:not([disabled])",
  '[tabindex]:not([tabindex="-1"])',
  "video[controls]",
  "audio[controls]",
].join(",");

export function DialogShell({
  title,
  description,
  onClose,
  children,
  alert = false,
  size = "standard",
  suspended = false,
}: DialogShellProps) {
  const titleId = useId();
  const descriptionId = useId();
  const surface = useRef<HTMLDivElement>(null);
  const hasFocused = useRef(false);
  const returnFocus = useRef<HTMLElement | null>(null);
  const suspendedRef = useRef(suspended);
  suspendedRef.current = suspended;
  const onCloseRef = useRef(onClose);
  onCloseRef.current = onClose;

  useEffect(() => {
    if (suspended) return;
    if (!returnFocus.current)
      returnFocus.current = document.activeElement as HTMLElement | null;
    const focusable = () =>
      Array.from(
        surface.current?.querySelectorAll<HTMLElement>(focusableSelector) ?? [],
      );
    if (!hasFocused.current) {
      focusable()[0]?.focus();
      hasFocused.current = true;
    }
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        onCloseRef.current();
        return;
      }
      if (event.key !== "Tab") return;
      const items = focusable();
      if (!items.length) return;
      const first = items[0];
      const last = items[items.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };
    document.addEventListener("keydown", handleKeyDown, true);
    return () => {
      document.removeEventListener("keydown", handleKeyDown, true);
      if (!suspendedRef.current) returnFocus.current?.focus();
    };
  }, [suspended]);

  return createPortal(
    <div className="editor-dialog-backdrop" role="presentation">
      <div
        ref={surface}
        className={`editor-dialog editor-dialog--${size}`}
        role={alert ? "alertdialog" : "dialog"}
        aria-modal="true"
        aria-labelledby={titleId}
        aria-describedby={description ? descriptionId : undefined}
        aria-hidden={suspended || undefined}
      >
        <header>
          <h2 id={titleId} className="editor-heading editor-heading--panel">
            {title}
          </h2>
          {description && (
            <p
              id={descriptionId}
              className="editor-text editor-text--secondary"
            >
              {description}
            </p>
          )}
        </header>
        {children}
      </div>
    </div>,
    document.querySelector(".editor-shell") ?? document.body,
  );
}
