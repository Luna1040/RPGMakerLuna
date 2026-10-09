import type { RawPreviewAsset } from "../api/types";
import { Button } from "./Controls";
import { DialogShell } from "./DialogShell";
import { SampledFramePlayer, type SampledFrame } from "./SampledFramePlayer";

export function MediaLightbox({
  asset,
  label,
  onClose,
  posterUrl,
  frames,
}: {
  asset: RawPreviewAsset;
  label: string;
  onClose: () => void;
  posterUrl?: string;
  frames?: SampledFrame[];
}) {
  return (
    <DialogShell
      title={label}
      description={`Raw unprocessed ${asset.kind === "video" ? "stage video" : "stage image"}.`}
      onClose={onClose}
      size="media"
    >
      <div className="media-lightbox-stage">
        {frames?.length ? (
          <SampledFramePlayer frames={frames} label={label} />
        ) : asset.kind === "video" ? (
          <video
            src={asset.url}
            controls
            preload="metadata"
            poster={posterUrl}
            tabIndex={0}
            aria-label={label}
          />
        ) : (
          <img src={asset.url} alt={label} />
        )}
      </div>
      <p className="editor-text editor-text--caption">{asset.filename}</p>
      <footer className="dialog-actions">
        <Button onClick={onClose}>Close preview</Button>
      </footer>
    </DialogShell>
  );
}
