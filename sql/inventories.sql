-- opx77_core, migration 0005_inventories. One container: a character's bag, a stash, the trunk
-- or glovebox of an owned vehicle. `kind` says which, `owner` says whose within that kind, and
-- the pair is unique. Free text rather than an ENUM, so a new kind of container needs no
-- migration.
--
-- A bag carries its citizen id and a vehicle's storage its plate, each with a cascading foreign
-- key: storage goes with the row it belongs to when that row is really deleted. A character's
-- delete is soft, so its bag stays, as its vehicles and memberships do.
--
-- `slots` and `max_weight` are the size the container was created with, in grams for the
-- weight. Kept rather than re-read from a config, so shrinking a size never evaporates what a
-- container already holds.
--
-- The runner in server/storage/schema.lua applies this statement itself at boot. This file is
-- the copy an operator reads and, if they migrate by hand, runs.

CREATE TABLE IF NOT EXISTS opx77_inventories (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    kind VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    owner VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    citizen_id VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NULL DEFAULT NULL,
    plate VARCHAR(12) CHARACTER SET ascii COLLATE ascii_bin NULL DEFAULT NULL,
    slots SMALLINT UNSIGNED NOT NULL,
    max_weight INT UNSIGNED NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_opx77_inventories_identity (kind, owner),
    KEY idx_opx77_inventories_citizen (citizen_id),
    KEY idx_opx77_inventories_plate (plate),
    CONSTRAINT fk_opx77_inventory_character
        FOREIGN KEY (citizen_id) REFERENCES opx77_characters (citizen_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_opx77_inventory_vehicle
        FOREIGN KEY (plate) REFERENCES opx77_vehicles (plate)
        ON DELETE CASCADE
) ENGINE=InnoDB;
