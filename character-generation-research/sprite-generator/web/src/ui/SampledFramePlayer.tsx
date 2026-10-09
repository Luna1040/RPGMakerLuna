import { useEffect, useRef, useState } from "react";
import { ChevronLeft, ChevronRight, Pause, Play } from "lucide-react";
import { Button } from "./Controls";

export interface SampledFrame {
  url: string;
  label: string;
  duration_ms: number;
}

export function SampledFrameImage({
  frames,
  frame,
  lazy = false,
}: {
  frames: SampledFrame[];
  frame: number;
  lazy?: boolean;
}) {
  const current = frames[frame % frames.length];
  if (!current) return null;
  return (
    <img
      src={current.url}
      alt={current.label}
      loading={lazy ? "lazy" : "eager"}
    />
  );
}

export function SampledFramePlayer({
  frames,
  label,
}: {
  frames: SampledFrame[];
  label: string;
}) {
  const [frame, setFrame] = useState(0);
  const [playing, setPlaying] = useState(
    () => !window.matchMedia?.("(prefers-reduced-motion: reduce)").matches,
  );
  const clockTimer = useRef<number | undefined>(undefined);
  useEffect(() => {
    if (!playing || frames.length <= 1) return;
    const timer = window.setTimeout(
      () => setFrame((value) => (value + 1) % frames.length),
      frames[frame]?.duration_ms ?? 125,
    );
    clockTimer.current = timer;
    return () => clearTimeout(timer);
  }, [playing, frame, frames]);
  return (
    <div className="sampled-frame-player" aria-label={label}>
      <div className="sampled-frame-player__image">
        <SampledFrameImage frames={frames} frame={frame} />
      </div>
      <div
        className="sampled-frame-player__controls"
        role="group"
        aria-label={`${label} playback`}
      >
        <Button
          compact
          onClick={() => {
            if (clockTimer.current) clearTimeout(clockTimer.current);
            setPlaying((value) => !value);
          }}
          disabled={frames.length <= 1}
        >
          {playing ? <Pause size={15} /> : <Play size={15} />}{" "}
          {playing ? "Pause" : "Play"}
        </Button>
        <Button
          compact
          icon
          title="Previous frame"
          aria-label="Previous enlarged frame"
          onClick={() => {
            if (clockTimer.current) clearTimeout(clockTimer.current);
            setPlaying(false);
            setFrame((value) => (value - 1 + frames.length) % frames.length);
          }}
        >
          <ChevronLeft size={15} />
        </Button>
        <span>
          Frame {frame + 1} / {frames.length}
        </span>
        <Button
          compact
          icon
          title="Next frame"
          aria-label="Next enlarged frame"
          onClick={() => {
            if (clockTimer.current) clearTimeout(clockTimer.current);
            setPlaying(false);
            setFrame((value) => (value + 1) % frames.length);
          }}
        >
          <ChevronRight size={15} />
        </Button>
      </div>
    </div>
  );
}
