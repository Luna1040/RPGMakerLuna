from __future__ import annotations

from dataclasses import dataclass, replace
from typing import Optional


def _make_pose(points: dict[int, tuple[int, int, int]]) -> list[int]:
    flat: list[int] = []
    for i in range(18):
        x, y, c = points.get(i, (0, 0, 0))
        flat.extend([x, y, c])
    return flat


@dataclass(frozen=True)
class PosePreset:
    slug: str
    label: str
    pose_description: str
    motion_prompt: str
    keypoints_2d: list[int]
    num_frames: int = 13
    fps: int = 16
    controlnet_strength: float = 1.4
    edit_denoise: float = 1.0
    sprite_frames: Optional[int] = None
    optimize_loop_seam: bool = False
    subtle_idle_motion: bool = False
    facial_expression: Optional[str] = None

    @property
    def output_frames(self) -> int:
        return self.sprite_frames or self.num_frames


POSE_PRESETS: dict[str, PosePreset] = {
    "idle_breathing": PosePreset(
        slug="idle_breathing",
        label="Idle Breathing",
        pose_description="a relaxed neutral idle stance, front-facing, arms resting softly at the sides, feet planted evenly",
        motion_prompt=(
            "Perform exactly one complete breathing cycle. Start from a neutral idle pose. Slowly inhale, reach a "
            "brief soft peak, slowly exhale, and return exactly to the initial pose before the final frame. The motion "
            "is driven only by very subtle expansion and contraction of the upper torso, less than 2% of body height. "
            "The head remains rigidly attached to the torso and translates with it. Hair and cape move only as a tiny "
            "delayed response caused by the torso motion. Keep the pelvis, root, feet, body center, character scale, "
            "screen position, framing, and camera perfectly fixed. Preserve strong temporal consistency. Reuse the "
            "same character model and visual information throughout the sequence. Every frame preserves identical "
            "facial geometry, anatomy, body proportions, clothing geometry, hair design, weapon, colors, and line-art "
            "style. Use smooth continuous easing throughout the inhale and exhale. Return to the exact initial "
            "character geometry and pose before the final frame"
        ),
        keypoints_2d=_make_pose({
            0: (256, 128, 1), 1: (256, 188, 1),
            2: (228, 204, 1), 3: (223, 267, 1), 4: (220, 330, 1),
            5: (284, 204, 1), 6: (289, 267, 1), 7: (292, 330, 1),
            8: (241, 286, 1), 9: (238, 374, 1), 10: (236, 460, 1),
            11: (271, 286, 1), 12: (274, 374, 1), 13: (277, 460, 1),
        }),
        num_frames=49,
        fps=12,
        sprite_frames=48,
        subtle_idle_motion=True,
    ),
    "idle_smile": PosePreset(
        slug="idle_smile",
        label="Idle Smile",
        pose_description="a relaxed idle stance, front-facing, elbows slightly open, hands soft and open",
        motion_prompt="start with the clearly visible smile already present in key pose A; preserve that smile throughout the entire clip; add one natural blink, a very small head motion, one slow chest breath, and one small smooth body rise and fall; never return to a neutral mouth; return exactly to the smiling key pose A",
        keypoints_2d=_make_pose({
            0: (256, 126, 1), 1: (256, 188, 1),
            2: (226, 204, 1), 3: (212, 254, 1), 4: (208, 309, 1),
            5: (286, 204, 1), 6: (300, 254, 1), 7: (304, 309, 1),
            8: (241, 286, 1), 9: (238, 374, 1), 10: (236, 460, 1),
            11: (271, 286, 1), 12: (274, 374, 1), 13: (277, 460, 1),
        }),
        num_frames=49,
        fps=12,
        sprite_frames=48,
        optimize_loop_seam=True,
        facial_expression="a clearly visible warm smile with both corners of the mouth raised; the mouth must not be neutral, flat, hidden, or expressionless",
    ),
    "smile": PosePreset(
        slug="smile",
        label="Smile",
        pose_description="a sweet friendly standing pose, front-facing, shoulders relaxed, hands open in a welcoming way",
        motion_prompt="start at the key pose; form a clearly visible smile; animate the eyes naturally; make one small head motion, one shoulder lift, one chest breath, and one small body bounce; recover and return exactly to the key pose",
        keypoints_2d=_make_pose({
            0: (256, 126, 1), 1: (256, 188, 1),
            2: (228, 204, 1), 3: (216, 252, 1), 4: (212, 304, 1),
            5: (284, 204, 1), 6: (296, 252, 1), 7: (300, 304, 1),
            8: (241, 286, 1), 9: (238, 374, 1), 10: (236, 460, 1),
            11: (271, 286, 1), 12: (274, 374, 1), 13: (277, 460, 1),
        }),
    ),
    "wave": PosePreset(
        slug="wave",
        label="Wave",
        pose_description="a friendly waving pose, front-facing, one hand raised near the head, the other arm relaxed",
        motion_prompt="start at the key pose; raise the waving hand; move the hand side to side for one complete wave; keep the elbow and shoulder connected; lower the hand; return exactly to the key pose",
        keypoints_2d=_make_pose({
            0: (256, 126, 1), 1: (256, 188, 1),
            2: (228, 204, 1), 3: (223, 267, 1), 4: (220, 330, 1),
            5: (284, 204, 1), 6: (310, 164, 1), 7: (320, 110, 1),
            8: (241, 286, 1), 9: (238, 374, 1), 10: (236, 460, 1),
            11: (271, 286, 1), 12: (274, 374, 1), 13: (277, 460, 1),
        }),
    ),
    "walk_cycle": PosePreset(
        slug="walk_cycle",
        label="Walk Cycle",
        pose_description="a walk-cycle starting pose, front-facing, one arm and the opposite leg forward, the other side back",
        motion_prompt="perform one complete two-step walk cycle in place: left foot contact, passing pose, right foot contact, passing pose, then return exactly to the starting pose; feet remain on the same ground line; root motion is disabled; no world translation; the body oscillates naturally while the root position remains fixed",
        keypoints_2d=_make_pose({
            0: (256, 128, 1), 1: (256, 188, 1),
            2: (234, 204, 1), 3: (240, 250, 1), 4: (244, 302, 1),
            5: (278, 204, 1), 6: (272, 252, 1), 7: (266, 306, 1),
            8: (246, 286, 1), 9: (250, 366, 1), 10: (252, 446, 1),
            11: (266, 286, 1), 12: (262, 382, 1), 13: (258, 458, 1),
        }),
        num_frames=25,
        fps=12,
        sprite_frames=24,
        optimize_loop_seam=True,
    ),
    "run_cycle": PosePreset(
        slug="run_cycle",
        label="Run Cycle",
        pose_description="a running starting pose, front-facing, stronger arm pump, one knee lifted while the opposite leg trails back",
        motion_prompt="perform one complete running cycle in place: left stride, passing pose, right stride, passing pose, then return exactly to the starting pose; coordinate opposite arm pumps; feet remain on the same ground line; root motion is disabled; no world translation; the root position remains fixed",
        keypoints_2d=_make_pose({
            0: (256, 122, 1), 1: (256, 182, 1),
            2: (232, 198, 1), 3: (244, 240, 1), 4: (254, 282, 1),
            5: (280, 198, 1), 6: (268, 242, 1), 7: (258, 286, 1),
            8: (246, 280, 1), 9: (258, 334, 1), 10: (272, 392, 1),
            11: (266, 280, 1), 12: (256, 378, 1), 13: (244, 452, 1),
        }),
        num_frames=25,
        fps=14,
        sprite_frames=24,
        optimize_loop_seam=True,
    ),
    "dance": PosePreset(
        slug="dance",
        label="Dance (8 sec)",
        pose_description="an energetic dance starting pose, front-facing, one arm raised and the other opened to the side, knees softly bent, balanced full-body stance",
        motion_prompt="perform the complete choreography in place: step left, return to center, step right, return to center, raise the left arm, lower it, raise the right arm, lower it, make one small hip sway, make one small body bounce, perform one final flourish, then return exactly to the starting pose; no improvisation, random poses, or additional gestures; maintain rhythmic body motion during the entire clip",
        keypoints_2d=_make_pose({
            0: (256, 120, 1), 1: (256, 182, 1),
            2: (228, 198, 1), 3: (206, 166, 1), 4: (194, 126, 1),
            5: (284, 198, 1), 6: (310, 216, 1), 7: (334, 238, 1),
            8: (242, 282, 1), 9: (226, 354, 1), 10: (210, 430, 1),
            11: (270, 282, 1), 12: (286, 350, 1), 13: (304, 420, 1),
        }),
        num_frames=81,
        fps=10,
        controlnet_strength=1.0,
        edit_denoise=0.65,
        sprite_frames=80,
        optimize_loop_seam=True,
    ),
    "jump": PosePreset(
        slug="jump",
        label="Jump",
        pose_description="a jump pose, front-facing, arms lifted slightly, knees bent upward, feet tucked under the body",
        motion_prompt="perform one complete vertical jump only: anticipation, takeoff straight upward, airborne apex, landing on the same ground line, recovery, then return to the identical standing position; no movement toward or away from the camera and no perspective scaling",
        keypoints_2d=_make_pose({
            0: (256, 112, 1), 1: (256, 170, 1),
            2: (228, 186, 1), 3: (214, 230, 1), 4: (206, 270, 1),
            5: (284, 186, 1), 6: (298, 230, 1), 7: (306, 270, 1),
            8: (244, 258, 1), 9: (232, 318, 1), 10: (226, 370, 1),
            11: (268, 258, 1), 12: (280, 318, 1), 13: (286, 370, 1),
        }),
    ),
    "jump_start": PosePreset(
        slug="jump_start",
        label="Jump Start",
        pose_description=(
            "an unmistakable deep grounded crouch before a vertical character jump, front three-quarter view, pelvis "
            "lowered close to the heels, both knees sharply bent, torso compressed forward, both feet planted"
        ),
        motion_prompt=(
            "animate one physically readable jump takeoff from the supplied deep crouch. Frames 1-10 hold the feet "
            "on one baseline while BOTH knees and hips begin extending. Frames 11-30 show a forceful leg-driven push: "
            "the knees visibly straighten, the pelvis rises relative to the feet, and the torso uncompresses. Only "
            "after both legs are nearly straight may both feet leave the baseline. Frames 31-49 show a small upward "
            "airborne displacement with the knees beginning to tuck. Every body joint must articulate; NEVER move "
            "the unchanged crouched silhouette upward as one rigid cutout. No apex, fall, landing or return loop"
        ),
        keypoints_2d=_make_pose({
            0: (256, 174, 1), 1: (256, 236, 1),
            2: (226, 246, 1), 3: (214, 282, 1), 4: (226, 316, 1),
            5: (286, 246, 1), 6: (298, 282, 1), 7: (286, 316, 1),
            8: (240, 322, 1), 9: (218, 354, 1), 10: (244, 402, 1),
            11: (272, 322, 1), 12: (294, 354, 1), 13: (268, 402, 1),
        }),
        num_frames=49,
        fps=12,
        sprite_frames=48,
        optimize_loop_seam=False,
    ),
    "jump_up": PosePreset(
        slug="jump_up",
        label="Jump Up",
        pose_description=(
            "a readable shallow anticipation crouch before a vertical character jump, front three-quarter view, "
            "hips slightly lowered, both knees bent and both feet planted on one baseline"
        ),
        motion_prompt=(
            "animate one readable upward-jump sequence. Begin in the supplied shallow crouch with both feet planted. "
            "First compress slightly deeper for anticipation. Then push through both feet: visibly extend both hips, "
            "knees and ankles until the legs are nearly straight. Only after that extension may both feet leave the "
            "baseline. Continue upward and progressively bend both knees into a compact airborne tuck, with hair, "
            "clothing and existing appendages trailing downward naturally. Finish near the apex as upward speed eases "
            "toward zero. Preserve horizontal center and scale. Never lift an unchanged crouched silhouette as a rigid "
            "cutout. No falling, landing or return loop"
        ),
        keypoints_2d=_make_pose({
            0: (256, 152, 1), 1: (256, 214, 1),
            2: (228, 226, 1), 3: (216, 266, 1), 4: (222, 304, 1),
            5: (284, 226, 1), 6: (296, 266, 1), 7: (290, 304, 1),
            8: (242, 306, 1), 9: (224, 354, 1), 10: (242, 410, 1),
            11: (270, 306, 1), 12: (288, 354, 1), 13: (270, 410, 1),
        }),
        num_frames=81,
        fps=12,
        sprite_frames=80,
        optimize_loop_seam=False,
    ),
    "attack": PosePreset(
        slug="attack",
        label="Attack",
        pose_description="an attack anticipation pose, front-facing, one arm extended forward, the other pulled back, one leg braced",
        motion_prompt="perform one complete attack cycle: wind-up, one strike, recovery, then return exactly to idle; no extra attacks and no repeated swings",
        keypoints_2d=_make_pose({
            0: (256, 126, 1), 1: (256, 186, 1),
            2: (228, 202, 1), 3: (214, 236, 1), 4: (198, 256, 1),
            5: (284, 202, 1), 6: (302, 248, 1), 7: (316, 300, 1),
            8: (242, 284, 1), 9: (236, 370, 1), 10: (232, 456, 1),
            11: (270, 284, 1), 12: (278, 356, 1), 13: (292, 434, 1),
        }),
    ),
    "cast_spell": PosePreset(
        slug="cast_spell",
        label="Cast Spell",
        pose_description="a spell-casting pose, front-facing, both arms open and raised as if channeling magic, balanced stance",
        motion_prompt="perform one complete casting animation: prepare, cast, hold, recover, then return exactly to idle; keep the hand and body motion continuous; generate no particles unless explicitly requested",
        keypoints_2d=_make_pose({
            0: (256, 122, 1), 1: (256, 182, 1),
            2: (228, 198, 1), 3: (206, 224, 1), 4: (190, 248, 1),
            5: (284, 198, 1), 6: (306, 224, 1), 7: (322, 248, 1),
            8: (242, 284, 1), 9: (238, 372, 1), 10: (236, 458, 1),
            11: (270, 284, 1), 12: (274, 372, 1), 13: (276, 458, 1),
        }),
    ),
    "hurt": PosePreset(
        slug="hurt",
        label="Hurt",
        pose_description="a hurt recoil pose, front-facing, shoulders tucked in, arms pulled inward, knees slightly bent",
        motion_prompt="start at the key pose; perform one impact recoil; reach the recoil extreme; recover; return exactly to the key pose; no second impact",
        keypoints_2d=_make_pose({
            0: (256, 132, 1), 1: (256, 194, 1),
            2: (232, 208, 1), 3: (230, 248, 1), 4: (242, 292, 1),
            5: (280, 208, 1), 6: (282, 248, 1), 7: (270, 292, 1),
            8: (244, 290, 1), 9: (242, 378, 1), 10: (238, 462, 1),
            11: (268, 290, 1), 12: (270, 378, 1), 13: (274, 462, 1),
        }),
    ),
    "victory": PosePreset(
        slug="victory",
        label="Victory",
        pose_description="a victory pose, front-facing, both arms raised in a wide V shape, chest open, proud stance",
        motion_prompt="start at the key pose; raise both arms into the victory pose; perform one body bounce; hold briefly with continuous breathing; lower and return exactly to the key pose",
        keypoints_2d=_make_pose({
            0: (256, 116, 1), 1: (256, 178, 1),
            2: (230, 196, 1), 3: (208, 152, 1), 4: (188, 104, 1),
            5: (282, 196, 1), 6: (304, 152, 1), 7: (324, 104, 1),
            8: (242, 286, 1), 9: (238, 374, 1), 10: (236, 460, 1),
            11: (270, 286, 1), 12: (274, 374, 1), 13: (276, 460, 1),
        }),
    ),
    "flash_entrance": PosePreset(
        slug="flash_entrance",
        label="Flash Entrance",
        pose_description="a magical arrival pose, front-facing, arms opened slightly as if emerging from a bright flash, balanced stance",
        motion_prompt="start from the key pose; perform one brief reveal from a bright flash; open both arms; settle the torso and arms; maintain continuous body motion; return exactly to the key pose; generate no additional effects or particles",
        keypoints_2d=_make_pose({
            0: (256, 118, 1), 1: (256, 180, 1),
            2: (228, 198, 1), 3: (210, 236, 1), 4: (196, 276, 1),
            5: (284, 198, 1), 6: (302, 236, 1), 7: (316, 276, 1),
            8: (242, 284, 1), 9: (238, 372, 1), 10: (236, 458, 1),
            11: (270, 284, 1), 12: (274, 372, 1), 13: (276, 458, 1),
        }),
    ),
    "air_kiss": PosePreset(
        slug="air_kiss",
        label="Air Kiss",
        pose_description="a playful air-kiss pose, front-facing, one hand lifted near the mouth, the other arm soft and relaxed",
        motion_prompt="start at the key pose; bring one hand to the mouth; tilt the head slightly; extend the hand outward for one air kiss; lower the hand; straighten the head; return exactly to the key pose",
        keypoints_2d=_make_pose({
            0: (256, 124, 1), 1: (256, 186, 1),
            2: (228, 202, 1), 3: (224, 252, 1), 4: (228, 298, 1),
            5: (284, 202, 1), 6: (300, 186, 1), 7: (290, 156, 1),
            8: (242, 286, 1), 9: (238, 374, 1), 10: (236, 460, 1),
            11: (270, 286, 1), 12: (274, 374, 1), 13: (276, 460, 1),
        }),
    ),
    "battle_stance": PosePreset(
        slug="battle_stance",
        label="Battle Stance",
        pose_description="a ready battle stance, front-facing, knees bent slightly, one arm forward guarding, the other ready to strike",
        motion_prompt="start at the battle-ready key pose; tighten the guard; make one small controlled weight shift without moving the root; raise and lower the front guarding arm slightly; return exactly to the key pose",
        keypoints_2d=_make_pose({
            0: (256, 128, 1), 1: (256, 190, 1),
            2: (230, 206, 1), 3: (214, 246, 1), 4: (202, 278, 1),
            5: (282, 206, 1), 6: (296, 248, 1), 7: (308, 290, 1),
            8: (244, 290, 1), 9: (234, 372, 1), 10: (226, 450, 1),
            11: (268, 290, 1), 12: (278, 372, 1), 13: (286, 450, 1),
        }),
        num_frames=17,
    ),
    "frown": PosePreset(
        slug="frown",
        label="Frown",
        pose_description="a slightly closed-off standing pose, front-facing, shoulders tucked a little, arms resting inward",
        motion_prompt="start at the key pose; form a clearly visible frown; lower the brows; make one small head motion and one chest breath; hold continuous facial and shoulder motion; return exactly to the key pose",
        keypoints_2d=_make_pose({
            0: (256, 130, 1), 1: (256, 192, 1),
            2: (232, 208, 1), 3: (228, 252, 1), 4: (234, 300, 1),
            5: (280, 208, 1), 6: (284, 252, 1), 7: (278, 300, 1),
            8: (244, 290, 1), 9: (242, 378, 1), 10: (238, 462, 1),
            11: (268, 290, 1), 12: (270, 378, 1), 13: (274, 462, 1),
        }),
    ),
    "laugh": PosePreset(
        slug="laugh",
        label="Laugh",
        pose_description="a joyful laughing pose, front-facing, chest open, one hand lifted slightly as if reacting mid-laugh",
        motion_prompt="start at the key pose; create clearly visible laughing facial animation and natural eye motion; add head motion, two small shoulder bounces, chest breathing, and one small body bounce; recover and return exactly to the key pose",
        keypoints_2d=_make_pose({
            0: (256, 122, 1), 1: (256, 184, 1),
            2: (228, 200, 1), 3: (214, 244, 1), 4: (208, 294, 1),
            5: (284, 200, 1), 6: (300, 236, 1), 7: (312, 274, 1),
            8: (242, 286, 1), 9: (238, 374, 1), 10: (236, 460, 1),
            11: (270, 286, 1), 12: (274, 374, 1), 13: (276, 460, 1),
        }),
    ),
    "walk_left": PosePreset(
        slug="walk_left",
        label="Walk Left",
        pose_description=(
            "a readable left-facing three-quarter side view, rotated about 60 to 70 degrees from the camera; the "
            "face, chest, knees, feet, and toes clearly point toward the LEFT EDGE while enough of the face and "
            "costume remain visible; never front-facing; preserve every existing held object in its original hand"
        ),
        motion_prompt=(
            "perform exactly TWO distinct walking steps forming one complete gait cycle while facing screen-left "
            "in a stable left-facing three-quarter side view: STEP 1 moves the left leg forward through contact and passing pose; "
            "STEP 2 moves the right leg forward through contact and passing pose; after both steps return exactly "
            "to the starting contact pose for a seamless loop; preserve every existing held object in the same hand in "
            "every frame; never swap hands and never mirror the character; move only toward screen-left, never "
            "toward the camera; feet remain on the same ground line; root position and camera remain fixed"
        ),
        keypoints_2d=_make_pose({
            0: (226, 132, 1), 1: (252, 188, 1),
            2: (254, 204, 1), 3: (226, 244, 1), 4: (200, 286, 1),
            5: (250, 204, 1), 6: (274, 248, 1), 7: (294, 294, 1),
            8: (254, 286, 1), 9: (226, 366, 1), 10: (196, 444, 1),
            11: (250, 286, 1), 12: (272, 374, 1), 13: (290, 454, 1),
        }),
        controlnet_strength=0.0,
        num_frames=49,
        fps=12,
        sprite_frames=48,
        optimize_loop_seam=True,
    ),
    "run_right": PosePreset(
        slug="run_right",
        label="Run Right",
        pose_description=(
            "a dynamic right-facing three-quarter side-view running contact pose; torso leaning slightly forward, "
            "right knee driving forward, left leg extending behind, opposite arm action; preserve all source-existing elements"
        ),
        motion_prompt=(
            "perform one complete right-facing run cycle in place with two distinct strides: right-leg drive then "
            "left-leg drive, including contact, flight and recovery phases; return exactly to the starting pose for "
            "a seamless loop; fixed camera, scale, baseline and root position; no world translation"
        ),
        keypoints_2d=_make_pose({
            0: (286, 128, 1), 1: (258, 184, 1),
            2: (256, 198, 1), 3: (290, 226, 1), 4: (316, 260, 1),
            5: (260, 198, 1), 6: (230, 230, 1), 7: (208, 270, 1),
            8: (256, 278, 1), 9: (294, 330, 1), 10: (326, 382, 1),
            11: (260, 278, 1), 12: (230, 354, 1), 13: (202, 430, 1),
        }),
        controlnet_strength=0.0,
        num_frames=49,
        fps=14,
        sprite_frames=48,
        optimize_loop_seam=True,
    ),
    "run_left": PosePreset(
        slug="run_left",
        label="Run Left",
        pose_description=(
            "a dynamic left-facing three-quarter side-view running contact pose; torso leaning slightly forward, "
            "left knee driving forward, right leg extending behind, opposite arm action; preserve all source-existing elements"
        ),
        motion_prompt=(
            "perform one complete left-facing run cycle in place with two distinct strides: left-leg drive then "
            "right-leg drive, including contact, flight and recovery phases; return exactly to the starting pose for "
            "a seamless loop; fixed camera, scale, baseline and root position; no world translation"
        ),
        keypoints_2d=_make_pose({
            0: (226, 128, 1), 1: (254, 184, 1),
            2: (256, 198, 1), 3: (222, 226, 1), 4: (196, 260, 1),
            5: (252, 198, 1), 6: (282, 230, 1), 7: (304, 270, 1),
            8: (256, 278, 1), 9: (218, 330, 1), 10: (186, 382, 1),
            11: (252, 278, 1), 12: (282, 354, 1), 13: (310, 430, 1),
        }),
        controlnet_strength=0.0,
        num_frames=49,
        fps=14,
        sprite_frames=48,
        optimize_loop_seam=True,
    ),
    "walk_right": PosePreset(
        slug="walk_right",
        label="Walk Right",
        pose_description=(
            "a STRICT full side-profile walk-cycle starting pose facing screen-right; the nose, face, chest, knees, "
            "feet, and toes point toward the RIGHT EDGE of the image; show only one eye; shoulders and hips are "
            "side-on, never front-facing or three-quarter; the character must not face or move toward the viewer"
        ),
        motion_prompt=(
            "perform exactly TWO distinct walking steps forming one complete gait cycle while facing screen-right. "
            "in a stable right-facing three-quarter side view: STEP 1 moves the right leg forward through contact "
            "and passing pose; STEP 2 moves the left leg forward through contact and passing pose; after both steps "
            "return exactly to the starting contact pose for a seamless loop; preserve existing held equipment in the same original "
            "hand in every frame; never swap hands and never mirror the character; the nose, "
            "chest, knees, feet, and toes remain pointed toward the RIGHT EDGE in every frame; move only toward "
            "screen-right, never screen-left and never toward the camera; feet remain on the same ground "
            "line; root motion is disabled; no world translation; root position remains fixed"
        ),
        keypoints_2d=_make_pose({
            0: (286, 132, 1), 1: (260, 188, 1),
            2: (258, 204, 1), 3: (286, 244, 1), 4: (312, 286, 1),
            5: (262, 204, 1), 6: (238, 248, 1), 7: (218, 294, 1),
            8: (258, 286, 1), 9: (286, 366, 1), 10: (316, 444, 1),
            11: (262, 286, 1), 12: (240, 374, 1), 13: (222, 454, 1),
        }),
        controlnet_strength=0.0,
        num_frames=49,
        fps=12,
        sprite_frames=48,
        optimize_loop_seam=True,
    ),
    "thoughtful": PosePreset(
        slug="thoughtful",
        label="Thoughtful",
        pose_description="a thoughtful standing pose, front-facing, one hand near the chin, posture calm and reflective",
        motion_prompt="start at the key pose; bring one hand to the chin; tilt the head slightly; animate the eyes naturally; make one small chest breath; straighten the head; lower the hand; return exactly to the key pose",
        keypoints_2d=_make_pose({
            0: (256, 124, 1), 1: (256, 186, 1),
            2: (228, 202, 1), 3: (222, 250, 1), 4: (230, 300, 1),
            5: (284, 202, 1), 6: (292, 198, 1), 7: (286, 162, 1),
            8: (242, 286, 1), 9: (238, 374, 1), 10: (236, 460, 1),
            11: (270, 286, 1), 12: (274, 374, 1), 13: (276, 460, 1),
        }),
    ),
    "angry": PosePreset(
        slug="angry",
        label="Angry",
        pose_description="an angry standing pose, front-facing, chest forward, fists tense, stance firm and confrontational",
        motion_prompt="start at the key pose; clench both fists; lower the brows; move the chest slightly forward without moving the root; make one controlled shoulder rise and fall; relax and return exactly to the key pose",
        keypoints_2d=_make_pose({
            0: (256, 126, 1), 1: (256, 188, 1),
            2: (228, 204, 1), 3: (220, 246, 1), 4: (216, 290, 1),
            5: (284, 204, 1), 6: (292, 246, 1), 7: (296, 290, 1),
            8: (242, 286, 1), 9: (236, 376, 1), 10: (232, 462, 1),
            11: (270, 286, 1), 12: (276, 376, 1), 13: (280, 462, 1),
        }),
    ),
    "jump_forward": PosePreset(
        slug="jump_forward",
        label="Jump Forward",
        pose_description="a vertical jump pose, front-facing, body kept at a fixed distance from the viewer, arms reacting to the leap",
        motion_prompt="perform one complete vertical jump only: anticipation, takeoff straight upward, apex, landing on the same ground line, recovery, then return to the identical standing position; no movement toward or away from the camera and no perspective scaling",
        keypoints_2d=_make_pose({
            0: (256, 112, 1), 1: (256, 170, 1),
            2: (230, 186, 1), 3: (214, 228, 1), 4: (206, 268, 1),
            5: (282, 186, 1), 6: (298, 230, 1), 7: (306, 270, 1),
            8: (242, 256, 1), 9: (226, 316, 1), 10: (214, 374, 1),
            11: (270, 256, 1), 12: (286, 316, 1), 13: (298, 374, 1),
        }),
    ),
    "jump_back": PosePreset(
        slug="jump_back",
        label="Jump Back",
        pose_description="a backward evasive jump pose, front-facing, upper body pulled back, legs tucked to retreat",
        motion_prompt="perform one evasive recoil without root translation: lean back, tuck the legs, recover, and return exactly to the identical standing position; no movement toward or away from the camera and no perspective scaling",
        keypoints_2d=_make_pose({
            0: (256, 118, 1), 1: (256, 176, 1),
            2: (232, 192, 1), 3: (218, 234, 1), 4: (206, 276, 1),
            5: (280, 192, 1), 6: (294, 234, 1), 7: (306, 276, 1),
            8: (244, 264, 1), 9: (236, 326, 1), 10: (230, 382, 1),
            11: (268, 264, 1), 12: (276, 326, 1), 13: (282, 382, 1),
        }),
    ),
    "jump_right": PosePreset(
        slug="jump_right",
        label="Jump Right",
        pose_description="a lateral jump pose toward the right, body leaning to the right with airborne legs and arms balancing the motion",
        motion_prompt="perform one vertical jump with a rightward body lean while the root and pivot remain fixed: anticipation, takeoff, apex, landing on the same ground line, recovery, then return exactly to the identical position; no horizontal translation",
        keypoints_2d=_make_pose({
            0: (270, 114, 1), 1: (270, 172, 1),
            2: (242, 188, 1), 3: (230, 232, 1), 4: (222, 276, 1),
            5: (296, 188, 1), 6: (314, 226, 1), 7: (326, 264, 1),
            8: (258, 262, 1), 9: (246, 322, 1), 10: (238, 378, 1),
            11: (282, 262, 1), 12: (294, 336, 1), 13: (308, 402, 1),
        }),
    ),
    "jump_left": PosePreset(
        slug="jump_left",
        label="Jump Left",
        pose_description="a lateral jump pose toward the left, body leaning to the left with airborne legs and arms balancing the motion",
        motion_prompt="perform one vertical jump with a leftward body lean while the root and pivot remain fixed: anticipation, takeoff, apex, landing on the same ground line, recovery, then return exactly to the identical position; no horizontal translation",
        keypoints_2d=_make_pose({
            0: (242, 114, 1), 1: (242, 172, 1),
            2: (216, 188, 1), 3: (198, 226, 1), 4: (186, 264, 1),
            5: (270, 188, 1), 6: (282, 232, 1), 7: (290, 276, 1),
            8: (230, 262, 1), 9: (218, 336, 1), 10: (204, 402, 1),
            11: (254, 262, 1), 12: (266, 322, 1), 13: (274, 378, 1),
        }),
    ),
    "weapon_spin": PosePreset(
        slug="weapon_spin",
        label="Weapon Spin",
        pose_description="a flashy weapon-spin stance, front-facing, one arm lifted and opened for a circular flourish, body balanced confidently",
        motion_prompt="perform one complete weapon-spin cycle: prepare, rotate the weapon through one readable circular arc, decelerate, recover, then return exactly to the starting pose; the weapon remains attached to the same hand and never duplicates or morphs",
        keypoints_2d=_make_pose({
            0: (256, 120, 1), 1: (256, 182, 1),
            2: (228, 198, 1), 3: (210, 170, 1), 4: (196, 136, 1),
            5: (284, 198, 1), 6: (300, 244, 1), 7: (312, 296, 1),
            8: (242, 284, 1), 9: (238, 372, 1), 10: (236, 458, 1),
            11: (270, 284, 1), 12: (274, 372, 1), 13: (276, 458, 1),
        }),
        num_frames=17,
    ),
}


# Result-workbench actions which were previously rendered as permanently
# disabled buttons. Each gets a real pipeline preset and a distinct motion
# prompt; related actions may share a proven OpenPose starting silhouette.
_BUTTON_PRESET_SPECS: dict[str, tuple[str, str, str, bool]] = {
    "idle_3": ("battle_stance", "Combat Idle", "hold a guarded combat idle with subtle breathing and one controlled weight shift; return exactly to the starting guard", True),
    "idle_4": ("thoughtful", "Thoughtful Idle", "hold a thoughtful idle with one hand near the chin, subtle breathing and small eye movement; return exactly to the starting pose", True),
    "idle_5": ("angry", "Angry Idle", "hold a tense angry idle with clenched fists, subtle breathing and one restrained shoulder rise; return exactly to the starting pose", True),
    "fall": ("jump", "Fall", "loop a readable airborne falling pose with limbs reacting to downward motion, fixed camera and scale, no landing", True),
    "fall_fast": ("jump", "Fast Fall", "loop a compact fast-fall pose with arms tucked and clothing trailing upward, fixed camera and scale, no landing", True),
    "land": ("jump", "Land", "begin airborne, contact the ground with both feet, compress knees and hips, recover to the exact neutral standing pose", False),
    "drop_down": ("jump", "Drop Down", "step off a platform, descend vertically with controlled posture and finish in a soft landing on the same baseline", False),
    "climb_idle": ("battle_stance", "Climb Idle", "hold a ladder-climbing pose with alternating hand and foot tension plus subtle breathing; root and camera stay fixed", True),
    "climb_up": ("walk_cycle", "Climb Up", "perform one seamless two-rung upward climbing cycle with alternating hands and feet; fixed camera and root", True),
    "climb_down": ("walk_cycle", "Climb Down", "perform one seamless two-rung downward climbing cycle with alternating hands and feet; fixed camera and root", True),
    "ledge_grab": ("jump", "Ledge Grab", "rise from below, reach with both hands, catch an overhead ledge and settle into a stable hanging pose", False),
    "ledge_climb": ("jump", "Ledge Climb", "start hanging from a ledge, pull the torso up, plant one knee, stand and recover to neutral", False),
    "vault": ("jump_forward", "Vault", "plant both hands on a waist-high obstacle, swing both legs over it and recover to the exact standing pose", False),
    "crouch": ("jump_start", "Crouch", "lower from standing into a stable deep crouch, hold briefly, then return exactly to standing", False),
    "crawl": ("walk_cycle", "Crawl", "perform one seamless crawl cycle on hands and knees with alternating limbs and fixed root position", True),
    "roll": ("jump_forward", "Roll", "tuck the head and perform one complete forward shoulder roll, rise and return exactly to neutral", False),
    "dash": ("run_right", "Dash", "perform one explosive lateral dash toward screen-right with anticipation, speed pose and recovery; keep the root inside the frame", False),
    "swim": ("walk_cycle", "Swim", "perform one seamless swimming stroke cycle with coordinated arms, legs and torso, fixed camera and scale", True),
    "float": ("idle_breathing", "Float", "loop a relaxed floating pose with slow buoyant rise and fall and gentle limb drift; return exactly to the first frame", True),
    "attack_1": ("attack", "Attack 1", "perform one quick horizontal primary strike with clear wind-up, contact, recovery and exact return to idle", False),
    "attack_2": ("attack", "Attack 2", "perform one rising secondary strike from the opposite side with wind-up, contact, recovery and exact return to idle", False),
    "attack_heavy": ("attack", "Heavy Attack", "perform one slow powerful overhead strike with deep anticipation, impact follow-through and exact recovery to idle", False),
    "attack_ranged": ("attack", "Ranged Attack", "aim toward screen-right, release exactly one ranged shot, absorb recoil and return exactly to idle; generate no projectile", False),
    "block": ("battle_stance", "Block", "raise a clear defensive guard, absorb one impact with a small recoil, lower the guard and return exactly to idle", False),
    "dodge": ("jump_back", "Dodge", "perform one quick evasive side-step and body lean, recover and return exactly to the original position", False),
    "hit": ("hurt", "Hit Reaction", "receive one readable impact, recoil through the torso and shoulders, recover and return exactly to idle", False),
    "knockdown": ("hurt", "Knockdown", "receive one heavy impact, lose balance and fall to the ground in a readable final pose; no recovery", False),
    "death": ("hurt", "Death", "lose strength, collapse once into a final still ground pose and remain there; no recovery or loop", False),
    "interact": ("wave", "Interact", "reach one hand toward an object at chest height, make contact, withdraw and return exactly to idle", False),
    "pickup": ("jump_start", "Pickup", "bend at knees and hips, pick up one small object from the ground, stand and return exactly to idle; generate no object", False),
    "use": ("wave", "Use", "reach forward and perform one clear press-or-activate gesture, withdraw and return exactly to idle", False),
    "push": ("attack", "Push", "brace the legs, place both palms forward, perform one strong push, release and return exactly to idle", False),
    "pull": ("attack", "Pull", "reach with both hands, grip, perform one strong pull toward the torso, release and return exactly to idle", False),
    "talk": ("idle_smile", "Talk", "loop a conversational idle with subtle mouth, head and hand gestures while feet and root remain locked", True),
    "spell_1": ("cast_spell", "Spell 1", "perform one compact one-handed casting gesture, release at chest height and return exactly to idle; no generated particles", False),
    "spell_2": ("cast_spell", "Spell 2", "perform one two-handed forward casting gesture with a clear release and exact recovery; no generated particles", False),
    "spell_3": ("cast_spell", "Spell 3", "channel upward with one raised hand, release once and return exactly to idle; no generated particles", False),
    "spell_4": ("cast_spell", "Spell 4", "draw both hands inward, perform one ground-directed cast and recover exactly to idle; no generated particles", False),
    "spell_5": ("cast_spell", "Spell 5", "perform one large ultimate casting gesture with wide anticipation, overhead release and controlled recovery; no generated particles", False),
}

for _slug, (_base, _label, _prompt, _loop) in _BUTTON_PRESET_SPECS.items():
    _source = POSE_PRESETS[_base]
    POSE_PRESETS[_slug] = replace(
        _source,
        slug=_slug,
        label=_label,
        motion_prompt=_prompt,
        num_frames=49 if _loop else _source.num_frames,
        sprite_frames=48 if _loop else _source.sprite_frames,
        optimize_loop_seam=_loop,
    )


def list_presets() -> list[PosePreset]:
    return list(POSE_PRESETS.values())


def get_preset(slug: str) -> PosePreset:
    try:
        return POSE_PRESETS[slug]
    except KeyError as exc:
        raise KeyError(
            f"Unknown preset '{slug}'. Available: {', '.join(sorted(POSE_PRESETS))}"
        ) from exc
