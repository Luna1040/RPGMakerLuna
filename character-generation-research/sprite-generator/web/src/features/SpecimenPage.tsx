import { useState } from "react";
import {
  Panel,
  Button,
  Choice,
  NumberField,
  SelectField,
  Status,
  TextField,
  BusySpinner,
} from "../ui/Controls";
import { DialogShell } from "../ui/DialogShell";
import { MediaLightbox } from "../ui/MediaLightbox";
import { ActivityModal } from "./ActivityModal";
import { CycleReviewDialog } from "./CycleReviewDialog";
import type { CycleReview, Job } from "../api/types";
export function SpecimenPage() {
  const [dialog, setDialog] = useState(false);
  const [media, setMedia] = useState(false);
  const [activity, setActivity] = useState(false);
  const [cycles, setCycles] = useState(false);
  return (
    <>
      <div className="page-title">
        <div>
          <p className="editor-kicker">Local foundation</p>
          <h1 className="editor-heading editor-heading--page">UI specimen</h1>
          <p className="editor-text editor-text--secondary">
            Permanent reference for every shared primitive and state used by
            this web app.
          </p>
        </div>
      </div>
      <div className="specimen-grid">
        <Panel title="Buttons" kicker="Actions">
          <div className="specimen-row">
            <Button>Standard</Button>
            <Button variant="primary">Primary</Button>
            <Button variant="warning">Warning</Button>
            <Button variant="danger">Danger</Button>
            <Button disabled>Disabled</Button>
            <Button onClick={() => setDialog(true)}>Open dialog</Button>
            <Button onClick={() => setMedia(true)}>Open media lightbox</Button>
            <Button onClick={() => setActivity(true)}>Open activity</Button>
            <Button onClick={() => setCycles(true)}>Open cycle chooser</Button>
          </div>
        </Panel>
        <Panel title="Fields" kicker="Controls">
          <div className="form-grid">
            <TextField
              label="Text"
              defaultValue="Character name"
              help="Visible labels sit above form controls."
            />
            <TextField
              label="Invalid"
              defaultValue="Bad value"
              error="A field-level error explains the correction."
            />
            <NumberField label="Number" defaultValue={256} unit="px" />
            <SelectField label="Select" defaultValue="one">
              <option value="one">Option one</option>
              <option value="two">Option two</option>
            </SelectField>
            <Choice
              type="checkbox"
              label="Checkbox"
              help="A selectable option with supporting copy."
            />
            <Choice type="radio" label="Radio" name="specimen" />
          </div>
        </Panel>
        <Panel title="Feedback" kicker="Semantic status">
          <div className="status-stack">
            <Status>Neutral operation status</Status>
            <Status tone="success">Operation completed</Status>
            <Status tone="warning">Attention may be needed</Status>
            <Status tone="danger" alert>
              Validation requires attention
            </Status>
            <progress aria-label="Example progress" max="10" value="6" />
            <BusySpinner label="Generating run workflow" />
          </div>
        </Panel>
      </div>
      {dialog && (
        <DialogShell
          title="Shared dialog"
          description="Escape closes this dialog and focus returns to its opener."
          onClose={() => setDialog(false)}
        >
          <p className="editor-text">
            Dialog content uses the same controls and surface tokens as the
            application.
          </p>
          <footer className="dialog-actions">
            <Button onClick={() => setDialog(false)}>Close</Button>
          </footer>
        </DialogShell>
      )}
      {media && (
        <MediaLightbox
          label="Raw pose specimen"
          onClose={() => setMedia(false)}
          asset={{
            id: "specimen",
            kind: "pose",
            pose_id: "standing",
            filename: "standing.png",
            media_type: "image/svg+xml",
            bytes: 0,
            sha256: "specimen",
            url: "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='320' height='180'%3E%3Crect width='320' height='180' fill='%2300252e'/%3E%3Ccircle cx='160' cy='72' r='30' fill='%2362ade2'/%3E%3Cpath d='M120 165 Q160 95 200 165' fill='%23268bd2'/%3E%3C/svg%3E",
          }}
        />
      )}
      {activity && (
        <ActivityModal
          job={null}
          onJob={() => undefined}
          onClose={() => setActivity(false)}
        />
      )}
      {cycles && (
        <CycleReviewDialog
          sourceJob={specimenJob}
          activeJob={specimenJob}
          review={specimenCycles}
          onJob={() => undefined}
          onClose={() => setCycles(false)}
        />
      )}
    </>
  );
}

const specimenFrame =
  "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='640' height='160'%3E%3Crect width='640' height='160' fill='%2300252e'/%3E%3Ccircle cx='80' cy='80' r='34' fill='%2362ade2'/%3E%3Ccircle cx='240' cy='80' r='34' fill='%23859900'/%3E%3Ccircle cx='400' cy='80' r='34' fill='%23b58900'/%3E%3Ccircle cx='560' cy='80' r='34' fill='%23dc322f'/%3E%3C/svg%3E";
const specimenJob = {
  id: "specimen-job",
  status: "ready",
  package_id: "specimen-package",
  request: { actions: ["run"] },
} as Job;
const specimenCycles: CycleReview = {
  job_id: "specimen-job",
  can_revise: true,
  can_analyze: false,
  groups: [
    {
      action: "run",
      label: "Run",
      stage_id: "run",
      status: "ready",
      message: null,
      analysis_id: "analysis-specimen",
      system_candidate_id: "cycle-2",
      selected_candidate_id: "cycle-2",
      selection_origin: "automatic",
      frame_count: 1,
      candidates: [1, 2].map((ordinal) => ({
        id: `cycle-${ordinal}`,
        start_time_seconds: ordinal - 1,
        end_time_seconds: ordinal,
        period_seconds: 1,
        system_selected: ordinal === 2,
        frame_durations_ms: [125],
        frames: [
          {
            id: `frame-${ordinal}`,
            frame_id: `frame-${ordinal}`,
            pts: ordinal,
            time_seconds: ordinal - 1,
            url: specimenFrame,
          },
        ],
      })),
    },
  ],
};
