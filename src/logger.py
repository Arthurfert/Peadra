"""
Professional logging system for Peadra.

Creates one log file per session in the system's temp directory.
Logs older than LOG_RETENTION_DAYS are automatically cleaned up.
"""

import logging
import os
import glob
import tempfile
from datetime import datetime, timedelta

LOG_DIR = os.path.join(tempfile.gettempdir(), "Peadra", "logs")
LOG_RETENTION_DAYS = 7
LOG_LEVEL = logging.DEBUG
_LOG_FORMAT = "%(asctime)s | %(levelname)-8s | %(name)s | %(message)s"
_DATE_FORMAT = "%Y-%m-%d %H:%M:%S"

_initialized = False
_current_log_path: str | None = None


def get_current_log_path() -> str | None:
    return _current_log_path


def setup_logger():
    global _initialized, _current_log_path
    if _initialized:
        return logging.getLogger()

    os.makedirs(LOG_DIR, exist_ok=True)

    _current_log_path = os.path.join(
        LOG_DIR, f"peadra_{datetime.now().strftime('%Y-%m-%d_%H-%M-%S')}.log"
    )

    _clean_old_logs()

    logger = logging.getLogger()
    logger.setLevel(LOG_LEVEL)

    file_handler = logging.FileHandler(_current_log_path, encoding="utf-8")
    file_handler.setLevel(LOG_LEVEL)
    file_handler.setFormatter(logging.Formatter(_LOG_FORMAT, datefmt=_DATE_FORMAT))
    logger.addHandler(file_handler)

    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.INFO)
    console_handler.setFormatter(logging.Formatter(_LOG_FORMAT, datefmt=_DATE_FORMAT))
    logger.addHandler(console_handler)

    _initialized = True
    logger.info("Logging initialized: %s", _current_log_path)
    return logger


def _clean_old_logs():
    cutoff = datetime.now() - timedelta(days=LOG_RETENTION_DAYS)
    for log_file in glob.glob(os.path.join(LOG_DIR, "peadra_*.log")):
        try:
            mtime = datetime.fromtimestamp(os.path.getmtime(log_file))
            if mtime < cutoff:
                os.remove(log_file)
        except OSError:
            pass
