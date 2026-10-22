"""Unit tests for the pump service."""

from datetime import datetime, timedelta

from app.schemas import PumpHistoryRequest
from app.services import pump_service


async def test_the_default_pumps_are_created(db_session):
    pumps = await pump_service.get_pumps(db_session)

    assert [pump.id for pump in pumps] == [1, 2, 3]


async def test_the_default_pump_modes_are_created(db_session):
    modes = await pump_service.get_pump_modes(db_session)

    assert {mode.pump_id: mode.mode for mode in modes} == {1: 0, 2: 0, 3: 0}


async def test_updating_a_mode_creates_the_pump_if_needed(db_session):
    updated = await pump_service.update_pump_mode(db_session, 4, 2)

    assert updated.pump_id == 4
    assert updated.mode == 2

    pumps = await pump_service.get_pumps(db_session)
    assert 4 in [pump.id for pump in pumps]


async def test_updating_a_mode_overwrites_the_previous_one(db_session):
    await pump_service.update_pump_mode(db_session, 1, 0)
    updated = await pump_service.update_pump_mode(db_session, 1, 3)

    assert updated.mode == 3

    modes = await pump_service.get_pump_modes(db_session)
    assert [mode.mode for mode in modes if mode.pump_id == 1] == [3]


async def test_the_history_is_stored_newest_first(db_session):
    await pump_service.create_pump_history(
        db_session, PumpHistoryRequest(liters=1.5, recorded_at=datetime(2026, 10, 30, 8))
    )
    await pump_service.create_pump_history(
        db_session, PumpHistoryRequest(liters=2.5, recorded_at=datetime(2026, 10, 31, 8))
    )

    history = await pump_service.get_pump_history(db_session)

    assert [entry.liters for entry in history] == [2.5, 1.5]


async def test_the_history_keeps_the_pump_it_belongs_to(db_session):
    await pump_service.create_pump_history(
        db_session, PumpHistoryRequest(liters=1.0, pump=2)
    )

    history = await pump_service.get_pump_history(db_session)

    assert [entry.pump_id for entry in history] == [2]


async def test_the_usage_of_today_only_counts_today(db_session):
    await pump_service.create_pump_history(
        db_session,
        PumpHistoryRequest(liters=4.0, recorded_at=datetime.now()),
    )
    await pump_service.create_pump_history(
        db_session,
        PumpHistoryRequest(
            liters=100.0, recorded_at=datetime.now() - timedelta(days=2)
        ),
    )

    assert await pump_service.get_today_usage(db_session) == 4.0


async def test_the_usage_of_today_is_zero_without_history(db_session):
    assert await pump_service.get_today_usage(db_session) == 0.0
