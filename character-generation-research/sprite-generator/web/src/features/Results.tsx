import { useEffect, useMemo, useRef, useState } from "react";
import { Download, Minus, Pause, Play, Plus, Scan } from "lucide-react";
import { api } from "../api/client";
import type { CycleReview, Direction, Job, Package } from "../api/types";
import { Button, Panel, SelectField, Status } from "../ui/Controls";

export function Results({
  packageId,
  job,
  cycleReview,
  onReview,
}: {
  packageId: string;
  job: Job;
  cycleReview?: CycleReview | null;
  onReview?: (action: string) => void;
}) {
  const [pkg, setPkg] = useState<Package | null>(null);
  const [error, setError] = useState("");
  const [zoom, setZoom] = useState(1);
  const [fit, setFit] = useState(true);
  const [action, setAction] = useState("");
  const [direction, setDirection] = useState<Direction>("right");
  const [playing, setPlaying] = useState(false);
  const [frame, setFrame] = useState(0);
  useEffect(() => {
    setPkg(null);
    setError("");
    setPlaying(false);
    setFrame(0);
    api
      .package(packageId)
      .then((value) => {
        setPkg(value);
        setAction(value.animations[0]?.action ?? value.still_actions[0] ?? "");
      })
      .catch((reason) => setError(reason.message));
  }, [packageId]);
  const actions = useMemo(
    () =>
      pkg
        ? [
            ...new Set(
              pkg.animations
                .map((item) => item.action)
                .concat(pkg.still_actions),
            ),
          ]
        : [],
    [pkg],
  );
  const animation = pkg?.animations.find(
    (item) => item.action === action && item.direction === direction,
  );
  const layout = pkg?.preview?.layout;
  const range = layout?.animation_ranges[action];
  const frameCount = range
    ? range[1] - range[0]
    : (job.request.frame_counts[action] ?? 1);
  const durations =
    pkg?.preview?.frame_durations_ms?.[`${action}:${direction}`] ??
    Array.from({ length: frameCount }, () => 125);
  useEffect(() => {
    setFrame(0);
    setPlaying(frameCount > 1 && !prefersReducedMotion());
  }, [packageId, action, direction, frameCount]);
  useEffect(() => {
    if (!playing || frameCount <= 1) return;
    const timer = window.setTimeout(
      () => setFrame((current) => (current + 1) % frameCount),
      durations[frame] ?? 125,
    );
    return () => clearTimeout(timer);
  }, [playing, frame, frameCount, durations]);
  if (error)
    return (
      <Status tone="danger" alert>
        {error}
      </Status>
    );
  if (!pkg) return <Status>Loading published package…</Status>;
  return (
    <Panel
      title="Your sprite package"
      kicker="Ready"
      className="results-panel"
      actions={
        <div className="download-actions">
          <a
            className="editor-button editor-button--primary"
            href={pkg.download_url}
          >
            <Download size={15} />
            Download all
          </a>
          <a className="editor-button" href={pkg.sheet.url}>
            Sheet PNG
          </a>
          <a className="editor-button" href={pkg.metadata.url}>
            Metadata JSON
          </a>
          {job.parent_job_id && (
            <a
              className="editor-button"
              href={`?job=${encodeURIComponent(job.parent_job_id)}`}
            >
              Previous render
            </a>
          )}
        </div>
      }
    >
      <div className="result-meta">
        <span>{pkg.sheet.filename}</span>
        <span>{actions.length} selected animations</span>
        <span>4 directions · right, left, back, front</span>
        {layout && (
          <span>
            {layout.columns * layout.cell_size} ×{" "}
            {layout.rows * layout.cell_size} px sheet · {layout.cell_size} px
            cells
          </span>
        )}
        <span>Seed {job.resolved_seed}</span>
      </div>
      <section className="preview-section" aria-labelledby="sheet-title">
        <div className="preview-heading">
          <div>
            <h3 id="sheet-title" className="editor-heading">
              Sprite sheet
            </h3>
            <p className="editor-text editor-text--help">
              Actual package layout: four direction rows with selected action
              frames across columns.
            </p>
          </div>
          <div role="group" aria-label="Sheet zoom">
            <Button
              compact
              icon
              title="Zoom out"
              aria-label="Zoom out"
              onClick={() => {
                setFit(false);
                setZoom((value) => Math.max(0.25, value - 0.25));
              }}
            >
              <Minus size={15} />
            </Button>
            <Button
              compact
              onClick={() => {
                setFit(false);
                setZoom(1);
              }}
            >
              100%
            </Button>
            <Button
              compact
              icon
              title="Zoom in"
              aria-label="Zoom in"
              onClick={() => {
                setFit(false);
                setZoom((value) => Math.min(4, value + 0.25));
              }}
            >
              <Plus size={15} />
            </Button>
            <Button compact title="Fit sheet" onClick={() => setFit(true)}>
              <Scan size={15} />
              Fit
            </Button>
          </div>
        </div>
        <div className="checkerboard sheet-canvas">
          <img
            src={pkg.sheet.url}
            alt="Four-direction sprite sheet"
            className={fit ? "fit" : ""}
            style={
              !fit && layout
                ? {
                    width: layout.columns * layout.cell_size * zoom,
                    height: layout.rows * layout.cell_size * zoom,
                  }
                : undefined
            }
          />
        </div>
      </section>
      <section
        className="preview-section animation-preview"
        aria-labelledby="animation-title"
      >
        <div className="preview-heading">
          <div>
            <h3 id="animation-title" className="editor-heading">
              Animation preview
            </h3>
            <p className="editor-text editor-text--help">
              Frames are cropped from the published sheet and use its exact
              encoded hold times.
            </p>
          </div>
          <div className="preview-selectors">
            <SelectField
              label="Action"
              value={action}
              onChange={(event) => setAction(event.target.value)}
            >
              {actions.map((item) => (
                <option key={item} value={item}>
                  {item.replaceAll("_", " ")}
                </option>
              ))}
            </SelectField>
            <SelectField
              label="Direction"
              value={direction}
              onChange={(event) =>
                setDirection(event.target.value as Direction)
              }
            >
              {(["right", "left", "back", "front"] as Direction[]).map(
                (item) => (
                  <option key={item}>{item}</option>
                ),
              )}
            </SelectField>
          </div>
        </div>
        <div className="animation-stage checkerboard">
          {layout && range ? (
            <SpriteFrame
              sheetUrl={pkg.sheet.url}
              layout={layout}
              actionStart={range[0]}
              direction={direction}
              frame={frame}
            />
          ) : (
            <Status>Preview layout is unavailable.</Status>
          )}
        </div>
        <div className="playback">
          <Button
            icon
            title={playing ? "Pause" : "Play"}
            aria-label={playing ? "Pause animation" : "Play animation"}
            disabled={frameCount <= 1}
            onClick={() => setPlaying((value) => !value)}
          >
            {playing ? <Pause size={16} /> : <Play size={16} />}
          </Button>
          <span>
            Frame {frame + 1} / {frameCount}
          </span>
          {animation && (
            <a href={animation.url} className="editor-button">
              Download {direction} WebP
            </a>
          )}
          {pkg.action_downloads[action] && (
            <a href={pkg.action_downloads[action]} className="editor-button">
              Download {action.replaceAll("_", " ")} ZIP
            </a>
          )}
          {!animation && (
            <span className="editor-text editor-text--help">
              Still pose · no animated file
            </span>
          )}
          {cycleReview?.groups.some((group) => group.action === action) && (
            <Button onClick={() => onReview?.(action)}>
              Review cycles (
              {cycleReview.groups.find((group) => group.action === action)
                ?.candidates.length ?? 0}
              )
            </Button>
          )}
        </div>
      </section>
    </Panel>
  );
}

function prefersReducedMotion() {
  return (
    typeof window !== "undefined" &&
    window.matchMedia?.("(prefers-reduced-motion: reduce)").matches
  );
}

function SpriteFrame({
  sheetUrl,
  layout,
  actionStart,
  direction,
  frame,
}: {
  sheetUrl: string;
  layout: NonNullable<NonNullable<Package["preview"]>["layout"]>;
  actionStart: number;
  direction: Direction;
  frame: number;
}) {
  const canvas = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const image = new Image();
    image.onload = () => {
      const context = canvas.current?.getContext("2d");
      if (!context || !canvas.current) return;
      context.imageSmoothingEnabled = false;
      const row = (
        layout.directions ?? ["right", "left", "back", "front"]
      ).indexOf(direction);
      context.clearRect(0, 0, layout.cell_size, layout.cell_size);
      context.drawImage(
        image,
        (actionStart + frame) * layout.cell_size,
        row * layout.cell_size,
        layout.cell_size,
        layout.cell_size,
        0,
        0,
        layout.cell_size,
        layout.cell_size,
      );
    };
    image.src = sheetUrl;
  }, [sheetUrl, layout, actionStart, direction, frame]);
  return (
    <canvas
      ref={canvas}
      width={layout.cell_size}
      height={layout.cell_size}
      aria-label={`${direction} frame ${frame + 1}`}
    />
  );
}
