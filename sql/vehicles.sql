-- opx77_core, migration 0004_vehicles. One owned vehicle, keyed on the plate rather than the
-- runtime id: the Open77 vehicle id is issued at spawn and is gone the moment the resource
-- that owns it reloads.
--
-- The runner in server/storage/schema.lua applies this statement itself at boot. This file is
-- the copy an operator reads and, if they migrate by hand, runs.

CREATE TABLE IF NOT EXISTS opx77_vehicles (
    plate VARCHAR(12) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
    citizen_id VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    record VARCHAR(256) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    appearance VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NULL DEFAULT NULL,
    garage VARCHAR(48) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'impound',
    state TINYINT UNSIGNED NOT NULL DEFAULT 1,
    health FLOAT NOT NULL DEFAULT 1,
    body JSON NULL DEFAULT NULL,
    paint JSON NULL DEFAULT NULL,
    metadata JSON NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_opx77_vehicles_owner (citizen_id, state),
    CONSTRAINT fk_opx77_vehicle_character
        FOREIGN KEY (citizen_id) REFERENCES opx77_characters (citizen_id)
        ON DELETE CASCADE
) ENGINE=InnoDB;
