"""Backward-compatible export — default strategy is S1 session break retest. """

from .common import Signal  # noqa: F401
from .strategies.session_break_retest import generate_signals  # noqa: F401
