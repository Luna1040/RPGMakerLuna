from __future__ import annotations
import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class WebSettings:
    data_root: Path
    config_path: Path
    username: str | None = None
    password: str | None = None
    secret: str = "development-only-change-me"
    base_path: str = ""
    upload_limit: int = 20 * 1024 * 1024
    pixel_limit: int = 40_000_000
    scheduler: bool = True
    no_auth: bool = False
    static_root: Path | None = None

    @classmethod
    def from_env(cls) -> "WebSettings":
        root = Path(
            os.environ.get("SPRITE_EXTRACTOR_DATA", "./sprite-extractor-data")
        ).resolve()
        config = Path(
            os.environ.get("SPRITE_EXTRACTOR_CONFIG", root / "config.yaml")
        ).resolve()
        upload = int(
            os.environ.get("SPRITE_EXTRACTOR_UPLOAD_LIMIT_BYTES", 20 * 1024 * 1024)
        )
        pixels = int(os.environ.get("SPRITE_EXTRACTOR_PIXEL_LIMIT", 40_000_000))
        no_auth_value = os.environ.get("SPRITE_EXTRACTOR_NO_AUTH", "").strip().lower()
        if no_auth_value not in {"", "0", "false", "no", "1", "true", "yes"}:
            raise ValueError(
                "SPRITE_EXTRACTOR_NO_AUTH must be true/false, yes/no, or 1/0"
            )
        no_scheduler = (
            os.environ.get("SPRITE_EXTRACTOR_NO_SCHEDULER", "").strip().lower()
        )
        if no_scheduler not in {"", "0", "false", "no", "1", "true", "yes"}:
            raise ValueError("SPRITE_EXTRACTOR_NO_SCHEDULER must be a boolean")
        static_value = os.environ.get("SPRITE_EXTRACTOR_STATIC_ROOT")
        return cls(
            data_root=root,
            config_path=config,
            username=os.environ.get("SPRITE_EXTRACTOR_USERNAME"),
            password=os.environ.get("SPRITE_EXTRACTOR_PASSWORD"),
            secret=os.environ.get(
                "SPRITE_EXTRACTOR_SECRET", "development-only-change-me"
            ),
            base_path=os.environ.get("SPRITE_EXTRACTOR_BASE_PATH", "").rstrip("/"),
            upload_limit=upload,
            pixel_limit=pixels,
            scheduler=no_scheduler not in {"1", "true", "yes"},
            no_auth=no_auth_value in {"1", "true", "yes"},
            static_root=Path(static_value).resolve() if static_value else None,
        )
