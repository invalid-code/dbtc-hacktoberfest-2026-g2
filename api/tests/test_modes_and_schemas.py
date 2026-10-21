"""Unit tests for the pump mode helpers and the request schemas."""

import pytest
from pydantic import ValidationError

from app.modes import (
    INDEX_MODE,
    MODE_INDEX,
    mode_index,
    mode_index_from_name,
    mode_name,
)
from app.schemas import PumpHistoryRequest, PumpModeRequest, SensorDataRequest


def test_the_modes_match_the_microcontroller_order():
    assert [INDEX_MODE[index] for index in range(4)] == [
        "FAST",
        "SLOW",
        "DRIP",
        "SPRINKLE",
    ]
    assert MODE_INDEX["SPRINKLE"] == 3


def test_an_unknown_mode_falls_back_to_fast():
    assert mode_name(9) == "FAST"
    assert mode_index(9) == 0


def test_a_mode_name_is_turned_into_its_index():
    assert mode_index_from_name("DRIP") == 2
    assert mode_index_from_name("drip") == 2
    assert mode_index_from_name("CANDY") is None


def test_a_reading_is_not_garbled_by_default():
    assert SensorDataRequest(
        sensor=1, moisture_level=42, humidity=78, temperature=23.5
    ).garbled is False


def test_a_reading_can_be_marked_as_garbled():
    assert SensorDataRequest(
        sensor=1, moisture_level=42, humidity=78, temperature=23.5, garbled=True
    ).garbled is True


def test_a_reading_without_a_sensor_is_rejected():
    with pytest.raises(ValidationError):
        SensorDataRequest(moisture_level=42, humidity=78, temperature=23.5)


def test_a_pump_mode_needs_a_pump_and_a_mode():
    assert PumpModeRequest(pump=1, pump_mode=2).pump == 1

    with pytest.raises(ValidationError):
        PumpModeRequest(pump=1)


def test_a_pump_history_can_be_without_a_pump():
    assert PumpHistoryRequest(liters=1.5).pump is None
    assert PumpHistoryRequest(liters=1.5, pump=2).pump == 2
