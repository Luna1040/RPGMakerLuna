"""Generate character animations or extract synchronized-view frames."""

from __future__ import annotations
import argparse, json, math, shutil, subprocess, sys
from pathlib import Path
from types import SimpleNamespace
from .diagnose_cycle import extract_sdpose, analyze
from .io_utils import atomic_write_json, sha256_file
from .media import probe_media

VIDEO_SUFFIXES = {".mp4", ".mov", ".mkv", ".webm", ".avi", ".m4v"}


def _worker(args):
    source = Path(args.input).resolve()
    target = Path(args.output).resolve()
    manifest = probe_media(source)
    if target.exists():
        raise FileExistsError(f"output already exists: {target}")
    if args.crop:
        crop = tuple(args.crop)
    else:
        edges = [round(manifest.width * i / args.views) for i in range(args.views + 1)]
        crop = (edges[args.view_index], edges[args.view_index + 1], 0, manifest.height)
    if not (
        0 <= crop[0] < crop[1] <= manifest.width
        and 0 <= crop[2] < crop[3] <= manifest.height
    ):
        raise ValueError(f"crop {crop} is outside {manifest.width}x{manifest.height}")
    raw_dir = target / "_raw"
    analysis_dir = target / "_analysis"
    cached_pose = getattr(args, "raw_pose", None)
    if cached_pose:
        raw_dir.mkdir(parents=True)
        shutil.copy2(cached_pose, raw_dir / "raw_pose.json")
    else:
        extract_sdpose(
            SimpleNamespace(
                source=str(source),
                output=str(raw_dir),
                crop=crop,
                server=args.server,
                config=args.config,
                timeout=args.timeout,
                poll_interval=args.poll_interval,
            )
        )
    analyze(
        SimpleNamespace(
            raw_pose=str(raw_dir / "raw_pose.json"),
            output=str(analysis_dir),
            frame_count=args.frame_count,
            min_period=args.min_period,
            max_period=args.max_period,
            sign_confidence=0.35,
            overlap_tolerance=0.12,
        )
    )
    target.mkdir(parents=True, exist_ok=True)
    shutil.move(str(raw_dir / "raw_pose.json"), target / "raw_pose.json")
    summary = json.loads((analysis_dir / "summary.json").read_text())
    candidates = analysis_dir / "original_frames/complete_cycles"
    if candidates.is_dir():
        shutil.move(str(candidates), target / "candidates")
    else:
        shutil.move(
            str(analysis_dir / "original_frames/six_frame_complete_cycle"),
            target / "frames",
        )
    shutil.move(
        str(analysis_dir / "original_frames/predicted_cycle_starts"),
        target / "cycle_starts",
    )
    for name in (
        "summary.json",
        "period_candidates.json",
        "ankle-y-waveforms.svg",
        "six_frame_complete_cycle-contact-sheet.png",
        "predicted_cycle_starts-contact-sheet.png",
        "predicted_cycle_starts-crop-contact-sheet.png",
    ):
        if (analysis_dir / name).is_file():
            shutil.move(str(analysis_dir / name), target / name)
    summary = json.loads((target / "summary.json").read_text())
    summary["raw_pose"] = "raw_pose.json"
    summary["execution_status"] = "exported"
    for record in summary["cycle_starts"]:
        record["path"] = "cycle_starts/" + Path(record["path"]).name
    for candidate in summary.get("cycle_candidates", []):
        for record in candidate["frames"]:
            record["path"] = (
                "candidates/" + candidate["id"] + "/" + Path(record["path"]).name
            )
    if summary.get("cycle_candidates"):
        selected = next(
            item
            for item in summary["cycle_candidates"]
            if item["id"] == summary["system_candidate_id"]
        )
        frames_dir = target / "frames"
        frames_dir.mkdir()
        legacy_frames = []
        for record in selected["frames"]:
            source_frame = target / record["path"]
            legacy = frames_dir / Path(record["path"]).name
            try:
                legacy.hardlink_to(source_frame)
            except OSError:
                shutil.copy2(source_frame, legacy)
            legacy_frames.append({**record, "path": "frames/" + legacy.name})
        summary["six_frame_cycle"]["frames"] = legacy_frames
        candidate_sheet = (
            analysis_dir / "complete_cycles" / (selected["id"] + "-contact-sheet.png")
        )
        if candidate_sheet.is_file():
            shutil.copy2(
                candidate_sheet, target / "six_frame_complete_cycle-contact-sheet.png"
            )
    else:
        for record in summary["six_frame_cycle"]["frames"]:
            record["path"] = "frames/" + Path(record["path"]).name
    atomic_write_json(target / "summary.json", summary)
    atomic_write_json(
        target / "manifest.json",
        {
            "version": "1.1",
            "execution_status": "exported",
            "quality_evaluated": False,
            "source": {"path": str(source), "sha256": sha256_file(source)},
            "analysis_crop": {
                "x0": crop[0],
                "x1": crop[1],
                "y0": crop[2],
                "y1": crop[3],
            },
            "frames": [
                record["path"] for record in summary["six_frame_cycle"]["frames"]
            ],
            "candidate_count": len(summary.get("cycle_candidates", [])),
            "system_candidate_id": summary.get("system_candidate_id"),
            "cycle_starts": [
                p.name for p in sorted((target / "cycle_starts").glob("*.png"))
            ],
            "summary": "summary.json",
            "raw_pose": "raw_pose.json",
        },
    )
    shutil.rmtree(raw_dir, ignore_errors=True)
    shutil.rmtree(analysis_dir, ignore_errors=True)
    if not args.frames_only:
        from .sprite_sheet import Remover, build

        sheet = build(
            target,
            args.sprite_height,
            [x.strip() for x in args.directions.split(",")],
            Remover(args.server, args.config, args.timeout, args.poll_interval),
            args.split_algorithm,
        )
        exported = json.loads((target / "manifest.json").read_text())
        exported["sprite_sheet"] = {
            "png": sheet["sheet"],
            "json": f"sprite-sheet-{args.sprite_height}h.json",
        }
        atomic_write_json(target / "manifest.json", exported)


def _inputs(path):
    if path.is_file():
        return [path]
    if not path.is_dir():
        raise FileNotFoundError(path)
    return sorted(
        (
            p
            for p in path.iterdir()
            if p.is_file() and p.suffix.lower() in VIDEO_SUFFIXES
        ),
        key=lambda p: p.name.lower(),
    )


def _main(argv=None):
    raw_argv = list(sys.argv[1:] if argv is None else argv)
    p = argparse.ArgumentParser(
        description="Generate packed animations from character images, or extract synchronized-view frames from videos. No quality score is produced."
    )
    p.add_argument(
        "input", nargs="?", help="one image/video, or a directory of images/videos"
    )
    p.add_argument("--output")
    p.add_argument(
        "--workflow",
        help="ComfyUI API workflow path; use 'staged' for selective dependency-aware generation, 'bundled'/'full' for all animations, or 'original' for run/idle only",
    )
    p.add_argument(
        "--definitions",
        action="append",
        metavar="PATH",
        help="animation-definition overlay; repeat for later whole-stage replacements",
    )
    p.add_argument(
        "--set-frames",
        action="append",
        metavar="ACTION=COUNT",
        help="override a discovered action's selected frame count; repeatable",
    )
    p.add_argument(
        "--list-animations",
        action="store_true",
        help="list catalog actions, poses, and selection policies without requiring input or output",
    )
    p.add_argument(
        "--actions",
        help="comma-separated catalog animation names; use --list-animations to discover them",
    )
    p.add_argument(
        "--poses",
        help="comma-separated catalog pose names; use --list-animations to discover them",
    )
    p.add_argument(
        "--poses-only",
        action="store_true",
        help="with --workflow staged, export poses but no animation actions; selects all poses when --poses is omitted",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="print the staged dependency plan without contacting ComfyUI or writing output",
    )
    p.add_argument(
        "--config",
        action="append",
        metavar="PATH",
        help="additional YAML override; repeat for multiple layers (later files win)",
    )
    p.add_argument(
        "--sprite-render-width",
        type=int,
        help="per-view ComfyUI render width (default: merged setting)",
    )
    p.add_argument(
        "--sprite-render-height",
        type=int,
        help="per-view ComfyUI render height (default: merged setting)",
    )
    p.add_argument(
        "--pad-top-percent",
        type=float,
        help="add this percentage of the dummy render height above the dummy only (default: merged setting)",
    )
    p.add_argument(
        "--dummy-image-folder",
        type=Path,
        help="folder containing 1-right.png, 2-left.png, 3-back.png, and 4-front.png",
    )
    p.add_argument("--idle-style", choices=("neutral", "feminine"), default="neutral")
    p.add_argument(
        "--seed",
        type=int,
        help="generation seed; -1 chooses a random seed for each fresh run (default: merged seed setting)",
    )
    p.add_argument(
        "--idle-frames",
        type=int,
        help="idle frames per direction (default: merged animation_frames.idle setting)",
    )
    p.add_argument(
        "--walk-frames",
        type=int,
        help="walking frames per direction (default: merged animation_frames.walk setting)",
    )
    p.add_argument(
        "--jump-frames",
        type=int,
        help="jump frames per direction (default: merged animation_frames.jump setting)",
    )
    p.add_argument(
        "--crouch-walk-frames",
        type=int,
        help="crouch-walk frames per direction (default: merged animation_frames.crouch_walk setting)",
    )
    p.add_argument("--server", help="override the merged comfyui_url setting")
    p.add_argument(
        "--generation-timeout",
        type=float,
        help="ComfyUI timeout in seconds (default: merged generation_timeout setting, 7200)",
    )
    p.add_argument("--poll-interval", type=float, default=2.0)
    p.add_argument("--generation-only", action="store_true", help=argparse.SUPPRESS)
    p.add_argument(
        "--crop",
        nargs=4,
        type=int,
        metavar=("X0", "X1", "Y0", "Y1"),
        help="analysis crop in canonical full-image pixels",
    )
    p.add_argument("--views", type=int, default=4)
    p.add_argument(
        "--view-index",
        type=int,
        default=3,
        help="zero-based analysis view used when --crop is omitted",
    )
    p.add_argument("--min-period", type=float, default=0.35)
    p.add_argument("--max-period", type=float, default=3.0)
    p.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    p.add_argument(
        "--run-frames",
        "--frame-count",
        dest="run_frames",
        type=int,
        help="running frames per direction (default: merged animation_frames.run setting; --frame-count is an alias)",
    )
    p.add_argument(
        "--sprite-box-height",
        "--sprite-height",
        dest="sprite_height",
        type=int,
        help="square sprite box height in pixels (default: merged sprite_box_height setting)",
    )
    p.add_argument(
        "--split-algorithm",
        choices=("blobs", "quarters"),
        default="blobs",
        help="four-blob gap detection (default) or legacy equal quarters",
    )
    p.add_argument("--frames-only", action="store_true")
    p.add_argument("--directions", default="right,left,back,front")
    args = p.parse_args(argv)
    args.definitions = (
        [Path(path).resolve() for path in args.definitions] if args.definitions else []
    )
    if args.list_animations:
        if args.workflow not in (None, "staged"):
            p.error("--list-animations supports only --workflow staged")
        list_conflicts = {
            "--actions",
            "--poses",
            "--poses-only",
            "--set-frames",
            "--dry-run",
            "--generation-only",
            "--dummy-image-folder",
        } & {token.split("=", 1)[0] for token in raw_argv if token.startswith("--")}
        if list_conflicts:
            p.error(
                f"{', '.join(sorted(list_conflicts))} cannot be combined with --list-animations"
            )
        from .animation_definitions import load_animation_registry

        try:
            registry = load_animation_registry(args.definitions, style=args.idle_style)
        except ValueError as exc:
            p.error(str(exc))
        listing = registry.list_document()
        print(json.dumps(listing, indent=2))
        return 0
    if args.input is None or args.output is None:
        p.error("input and --output are required unless --list-animations is used")
    source = Path(args.input).resolve()
    output = Path(args.output).resolve()
    args.config = (
        [Path(path).resolve() for path in args.config] if args.config else None
    )
    if args.dummy_image_folder is not None:
        args.dummy_image_folder = args.dummy_image_folder.expanduser().resolve()
    from .comfy_workflow import (
        MAX_SEED,
        configured_animation_frame_counts,
        configured_comfyui_url,
        configured_generation_timeout,
        configured_pad_top_percent,
        configured_seed,
        configured_sprite_box_height,
        configured_sprite_render_size,
        dummy_top_padding_pixels,
        dummy_view_paths,
    )

    args.server = args.server or configured_comfyui_url(args.config)
    if args.generation_timeout is None:
        args.generation_timeout = configured_generation_timeout(args.config)
    if args.seed is None:
        args.seed = configured_seed(args.config)
    configured_frames = configured_animation_frame_counts(args.config)
    if args.idle_frames is None:
        args.idle_frames = configured_frames["idle"]
    if args.run_frames is None:
        args.run_frames = configured_frames["run"]
    if args.walk_frames is None:
        args.walk_frames = configured_frames["walk"]
    if args.jump_frames is None:
        args.jump_frames = configured_frames["jump"]
    if args.crouch_walk_frames is None:
        args.crouch_walk_frames = configured_frames["crouch_walk"]
    if args.sprite_height is None:
        args.sprite_height = configured_sprite_box_height(args.config)
    configured_render_width, configured_render_height = configured_sprite_render_size(
        args.config
    )
    if args.sprite_render_width is None:
        args.sprite_render_width = configured_render_width
    if args.sprite_render_height is None:
        args.sprite_render_height = configured_render_height
    if args.pad_top_percent is None:
        args.pad_top_percent = configured_pad_top_percent(args.config)
    args.timeout = args.generation_timeout
    args.frame_count = args.run_frames
    if args.views <= 0 or not 0 <= args.view_index < args.views:
        p.error("--views must be positive and --view-index must be within it")
    if args.workflow != "staged":
        if args.run_frames < 2:
            p.error("--run-frames must be at least 2")
        if args.walk_frames < 2:
            p.error("--walk-frames must be at least 2")
        if args.idle_frames < 2:
            p.error("--idle-frames must be at least 2")
        if args.jump_frames < 2:
            p.error("--jump-frames must be at least 2")
        if args.crouch_walk_frames < 2:
            p.error("--crouch-walk-frames must be at least 2")
    if not -1 <= args.seed <= MAX_SEED:
        p.error(f"--seed must be -1 or an integer from 0 through {MAX_SEED}")
    if not (
        math.isfinite(args.generation_timeout)
        and args.generation_timeout > 0
        and math.isfinite(args.poll_interval)
        and args.poll_interval > 0
    ):
        p.error("generation timeout and poll interval must be finite and positive")
    labels = [x.strip() for x in args.directions.split(",")]
    if (
        args.sprite_height <= 0
        or args.sprite_render_width <= 0
        or args.sprite_render_height <= 0
        or len(labels) != 4
        or any(not x for x in labels)
    ):
        p.error(
            "positive sprite dimensions and exactly four nonempty --directions required"
        )
    try:
        dummy_top_padding_pixels(args.sprite_render_height, args.pad_top_percent)
        if args.dummy_image_folder is not None:
            dummy_view_paths(args.dummy_image_folder)
    except ValueError as exc:
        p.error(str(exc))
    except FileNotFoundError as exc:
        p.error(str(exc))
    if not (
        math.isfinite(args.min_period)
        and math.isfinite(args.max_period)
        and 0 < args.min_period < args.max_period
    ):
        p.error("finite period bounds must satisfy 0 < min < max")
    if args.crop and not (args.crop[0] < args.crop[1] and args.crop[2] < args.crop[3]):
        p.error("--crop requires X0 < X1 and Y0 < Y1")
    if args.worker:
        _worker(args)
        return 0
    if args.workflow:
        if source.is_dir() and (output == source or source in output.parents):
            p.error("--output must not be inside the input image directory")
        direct_only = {
            "--crop",
            "--frames-only",
            "--views",
            "--view-index",
            "--min-period",
            "--max-period",
        }
        supplied = {
            token.split("=", 1)[0] for token in raw_argv if token.startswith("--")
        }
        ignored = sorted(direct_only & supplied)
        if ignored:
            p.error(f"{', '.join(ignored)} apply only to direct video extraction")
        staged_options = {
            "--actions",
            "--poses",
            "--poses-only",
            "--dry-run",
            "--definitions",
            "--set-frames",
        }
        if args.workflow != "staged" and staged_options & supplied:
            p.error(
                f"{', '.join(sorted(staged_options & supplied))} require --workflow staged"
            )
        from .generate_character import generate_videos, process_characters

        if args.workflow == "staged":
            from .animation_definitions import DefinitionError, load_animation_registry
            from .definition_runtime import (
                generate_definitions,
                package_definitions,
                plan_definitions,
            )

            try:
                registry = load_animation_registry(
                    args.definitions, style=args.idle_style
                )
                actions = (
                    registry.resolve_actions(args.actions)
                    if args.actions is not None
                    else (
                        ()
                        if args.poses is not None or args.poses_only
                        else registry.actions
                    )
                )
                poses = (
                    registry.resolve_poses(args.poses)
                    if args.poses is not None
                    else (registry.poses if args.poses_only else ())
                )
            except DefinitionError as exc:
                p.error(str(exc))
            if args.poses_only and args.actions is not None:
                p.error("--poses-only cannot be combined with --actions")
            if args.poses_only:
                actions = ()
            if not actions and not poses:
                p.error("staged workflow requires at least one action or pose")
            frame_counts = {
                name: (
                    registry.stages[
                        registry.action_stages[name]
                    ].animation.selection.frames
                    or 1
                )
                for name in registry.actions
            }
            for name, value in configured_frames.items():
                if (
                    name in frame_counts
                    and registry.stages[
                        registry.action_stages[name]
                    ].animation.selection.method
                    != "single"
                ):
                    frame_counts[name] = value
            legacy_flags = {
                "idle": "--idle-frames",
                "run": "--run-frames",
                "walk": "--walk-frames",
                "jump": "--jump-frames",
                "crouch_walk": "--crouch-walk-frames",
            }
            legacy_values = {
                "idle": args.idle_frames,
                "run": args.run_frames,
                "walk": args.walk_frames,
                "jump": args.jump_frames,
                "crouch_walk": args.crouch_walk_frames,
            }
            explicit_legacy = {
                name
                for name, flag in legacy_flags.items()
                if flag in supplied or name == "run" and "--frame-count" in supplied
            }
            for name in explicit_legacy:
                if name not in frame_counts:
                    p.error(f"{legacy_flags[name]} has no matching catalog action")
                policy = registry.stages[
                    registry.action_stages[name]
                ].animation.selection.method
                if policy == "single" and legacy_values[name] != 1:
                    p.error(
                        f"{legacy_flags[name]} must be 1 for its single-frame policy"
                    )
                if policy != "single" and legacy_values[name] < 2:
                    p.error(f"{legacy_flags[name]} must be at least 2")
                frame_counts[name] = legacy_values[name]
            generic_counts = {}
            for item in args.set_frames or ():
                name, separator, value = item.partition("=")
                name = name.strip().replace("-", "_")
                if not separator or not name or not value.strip():
                    p.error("--set-frames requires ACTION=COUNT")
                if name in generic_counts:
                    p.error(f"duplicate --set-frames override for {name}")
                try:
                    count = int(value)
                except ValueError:
                    p.error(f"--set-frames {name} count must be an integer")
                if name not in frame_counts:
                    p.error(f"--set-frames names unknown catalog action {name}")
                policy = registry.stages[
                    registry.action_stages[name]
                ].animation.selection.method
                if policy == "single" and count != 1:
                    p.error(
                        f"--set-frames {name} must be 1 for its single-frame policy"
                    )
                if policy != "single" and count < 2:
                    p.error(f"--set-frames {name} must be at least 2")
                if name in explicit_legacy:
                    p.error(f"conflicting frame-count overrides for {name}")
                generic_counts[name] = count
            frame_counts.update(generic_counts)
            if args.dry_run:
                from .generate_character import image_inputs

                try:
                    dry_run_sources = image_inputs(source)
                except (OSError, ValueError) as exc:
                    p.error(str(exc))
                if not dry_run_sources:
                    p.error("no recognized image files found")
                print(
                    json.dumps(
                        plan_definitions(
                            registry,
                            actions,
                            poses,
                            frame_counts,
                            output=output,
                            image=source,
                            width=args.sprite_render_width,
                            base_height=args.sprite_render_height,
                            pad_top_percent=args.pad_top_percent,
                            dummy_image_folder=args.dummy_image_folder,
                            seed=args.seed,
                            workflow_config=args.config,
                        ),
                        indent=2,
                    )
                )
                return 0
            state = generate_definitions(
                source,
                output,
                registry,
                actions=actions,
                poses=poses,
                idle_style=args.idle_style,
                server=args.server,
                timeout=args.generation_timeout,
                poll_interval=args.poll_interval,
                sprite_render_width=args.sprite_render_width,
                sprite_render_height=args.sprite_render_height,
                pad_top_percent=args.pad_top_percent,
                dummy_image_folder=args.dummy_image_folder,
                seed=args.seed,
                workflow_config=args.config,
            )
            # Packaging is deliberately separate from inference so completed
            # stages remain reusable when a later invocation requests more.
            if not args.generation_only:
                state = package_definitions(
                    state,
                    output,
                    registry,
                    actions=actions,
                    poses=poses,
                    frame_counts=frame_counts,
                    height=args.sprite_height,
                    directions=tuple(labels),
                    split_algorithm=args.split_algorithm,
                    server=args.server,
                    config=args.config,
                    timeout=args.generation_timeout,
                    poll_interval=args.poll_interval,
                )
            print(output / "staged-generation-state.json")
            succeeded = (
                state.get("generation_complete", False)
                if args.generation_only
                else state.get("complete", False)
            )
            return 0 if succeeded else 1
        if args.workflow in {"bundled", "full"}:
            from .comfy_workflow import bundled_workflow_path

            args.workflow = str(bundled_workflow_path())
        elif args.workflow in {"original", "legacy"}:
            from .comfy_workflow import original_workflow_path

            args.workflow = str(original_workflow_path())
        common = dict(
            idle_style=args.idle_style,
            server=args.server,
            timeout=args.generation_timeout,
            poll_interval=args.poll_interval,
            sprite_render_width=args.sprite_render_width,
            sprite_render_height=args.sprite_render_height,
            pad_top_percent=args.pad_top_percent,
            dummy_image_folder=args.dummy_image_folder,
            seed=args.seed,
            workflow_config=args.config,
        )
        if args.generation_only:
            state = generate_videos(
                source, output, Path(args.workflow).resolve(), **common
            )
        else:
            from .character_animations import build_character_animations

            postprocess_options = {
                "directions": labels,
                "split_algorithm": args.split_algorithm,
                "server": args.server,
                "config": args.config,
                "timeout": args.generation_timeout,
                "poll_interval": args.poll_interval,
            }
            state = process_characters(
                source,
                output,
                Path(args.workflow).resolve(),
                run_frames=args.run_frames,
                walk_frames=args.walk_frames,
                idle_frames=args.idle_frames,
                jump_frames=args.jump_frames,
                crouch_walk_frames=args.crouch_walk_frames,
                sprite_height=args.sprite_height,
                postprocess=build_character_animations,
                postprocess_options=postprocess_options,
                **common,
            )
        print(output / "generation-state.json")
        return (
            0 if state.get("complete", state.get("generation_complete", False)) else 1
        )
    workflow_only = {
        "--idle-style",
        "--seed",
        "--idle-frames",
        "--walk-frames",
        "--jump-frames",
        "--crouch-walk-frames",
        "--generation-only",
        "--sprite-render-width",
        "--sprite-render-height",
        "--pad-top-percent",
        "--dummy-image-folder",
        "--actions",
        "--poses",
        "--poses-only",
        "--dry-run",
        "--definitions",
        "--set-frames",
    }
    supplied = {token.split("=", 1)[0] for token in raw_argv if token.startswith("--")}
    ignored = sorted(workflow_only & supplied)
    if ignored:
        p.error(f"{', '.join(ignored)} require --workflow")
    inputs = _inputs(source)
    if not inputs:
        raise ValueError("no recognized video files found")
    if output.exists():
        raise FileExistsError(f"output already exists: {output}")
    if source.is_dir() and (output == source or source in output.parents):
        raise ValueError("output must not be inside the input directory")
    output.mkdir(parents=True)
    used = set()
    results = []
    for index, item in enumerate(inputs, 1):
        base = item.stem
        name = base
        suffix = 2
        while name.lower() in used:
            name = f"{base}-{suffix}"
            suffix += 1
        used.add(name.lower())
        target = output / name
        print(f"[{index}/{len(inputs)}] {item.name}: running", flush=True)
        command = [
            sys.executable,
            "-m",
            "sprite_extractor.extract_frames",
            str(item),
            "--output",
            str(target),
            "--server",
            args.server,
            "--generation-timeout",
            str(args.generation_timeout),
            "--poll-interval",
            str(args.poll_interval),
            "--min-period",
            str(args.min_period),
            "--max-period",
            str(args.max_period),
            "--views",
            str(args.views),
            "--view-index",
            str(args.view_index),
            "--frame-count",
            str(args.run_frames),
            "--sprite-box-height",
            str(args.sprite_height),
            "--split-algorithm",
            args.split_algorithm,
            "--directions",
            args.directions,
            *[
                item
                for config in (args.config or [])
                for item in ("--config", str(config))
            ],
            *(["--frames-only"] if args.frames_only else []),
            "--worker",
        ]
        if args.crop:
            command[command.index("--worker") : command.index("--worker")] = [
                "--crop",
                *(str(v) for v in args.crop),
            ]
        log = output / f"{name}.log"
        with log.open("w") as handle:
            result = subprocess.run(
                command, stdout=handle, stderr=subprocess.STDOUT, text=True
            )
        status = "exported" if result.returncode == 0 else "failed"
        if status == "failed":
            target.mkdir(exist_ok=True)
            atomic_write_json(
                target / "manifest.json",
                {
                    "version": "1.0",
                    "execution_status": "failed",
                    "quality_evaluated": False,
                    "source": {"path": str(item), "sha256": sha256_file(item)},
                    "failure": {
                        "returncode": result.returncode,
                        "log": "../" + log.name,
                        "log_basis": "relative_to_video_output",
                    },
                },
            )
        results.append(
            {
                "input": str(item),
                "output": str(target),
                "status": status,
                "log": str(log),
            }
        )
        print(f"[{index}/{len(inputs)}] {item.name}: {status} -> {target}", flush=True)
        failed = sum(r["status"] == "failed" for r in results)
        atomic_write_json(
            output / "batch-summary.json",
            {
                "version": "1.0",
                "quality_evaluated": False,
                "inputs": [str(p) for p in inputs],
                "results": results,
                "exported": len(results) - failed,
                "failed": failed,
                "complete": len(results) == len(inputs),
            },
        )
    failed = sum(r["status"] == "failed" for r in results)
    print(output / "batch-summary.json")
    return 1 if failed else 0


def main(argv=None):
    values = list(sys.argv[1:] if argv is None else argv)
    output = None
    for index, value in enumerate(values):
        if value == "--output" and index + 1 < len(values):
            output = values[index + 1]
        elif value.startswith("--output="):
            output = value.split("=", 1)[1]
    if output and "--dry-run" not in values and "--list-animations" not in values:
        from .execution_lock import output_tree_lock

        with output_tree_lock(output):
            return _main(values)
    return _main(values)


if __name__ == "__main__":
    raise SystemExit(main())
