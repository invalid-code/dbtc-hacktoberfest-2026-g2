"""Tests for the microcontroller registration."""

from app.services import device_service, pump_service, sensor_service


async def test_registering_a_microcontroller_provisions_the_greenhouse(
    empty_db_session,
):
    await device_service.register_microcontroller(empty_db_session, "test-device")

    sensors = await sensor_service.get_sensors(empty_db_session)
    pumps = await pump_service.get_pumps(empty_db_session)
    modes = await pump_service.get_pump_modes(empty_db_session)

    assert [sensor.id for sensor in sensors] == [1, 2, 3]
    assert [pump.id for pump in pumps] == [1, 2, 3]
    assert {mode.pump_id: mode.mode for mode in modes} == {1: 0, 2: 0, 3: 0}


async def test_registering_twice_does_not_duplicate_the_greenhouse(
    empty_db_session,
):
    await device_service.register_microcontroller(empty_db_session)
    await device_service.register_microcontroller(empty_db_session)

    sensors = await sensor_service.get_sensors(empty_db_session)
    pumps = await pump_service.get_pumps(empty_db_session)

    assert [sensor.id for sensor in sensors] == [1, 2, 3]
    assert [pump.id for pump in pumps] == [1, 2, 3]
