"""The shared pump-mode ordinal contract between the API, the Arduino sketch and the frontend."""

from enum import Enum


class PumpModeName(str, Enum):
    """Pump modes, in the same order as the Arduino ``OperatingMode`` enum.

    The integer stored in the database is the enum ordinal, so it matches
    ``FAST=0, SLOW=1, DRIP=2, SPRINKLE=3`` on the microcontroller.
    """

    FAST = "FAST"
    SLOW = "SLOW"
    DRIP = "DRIP"
    SPRINKLE = "SPRINKLE"


MODE_INDEX = {mode.name: index for index, mode in enumerate(PumpModeName)}
INDEX_MODE = {index: mode.name for index, mode in enumerate(PumpModeName)}

# The litres one run of each mode gives, mirrored from the firmware:
# PUMP_LITRES_PER_SECOND and the run times of microcontroller.ino.
MODE_LITRES = {
    PumpModeName.FAST.name: 0.006,
    PumpModeName.SLOW.name: 0.0028,
    PumpModeName.DRIP.name: 0.0012,
    PumpModeName.SPRINKLE.name: 0.0,
}


def mode_index(mode: int) -> int:
    return mode if mode in INDEX_MODE else MODE_INDEX[PumpModeName.FAST.name]


def mode_name(mode: int) -> str:
    return INDEX_MODE.get(mode, PumpModeName.FAST.name)


def mode_litres(mode: int) -> float:
    """The litres one run of that mode gives."""
    return MODE_LITRES[mode_name(mode)]


def mode_index_from_name(name: str) -> int | None:
    try:
        return MODE_INDEX[PumpModeName(name.upper()).name]
    except (KeyError, ValueError):
        return None
