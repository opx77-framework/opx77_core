-- opx77_core, the whole schema: every table the core owns, in dependency order.
--
-- server/storage/schema.lua carries the same statements, without these comments, and runs them
-- at every boot: the Open77 server runtime has no file reader, so the core cannot load this
-- file. This copy is what an operator reads, and may run by hand on an empty database.
--
-- There are no migrations. `CREATE TABLE IF NOT EXISTS` creates a missing table and never
-- alters an existing one: after a change to a table, drop it (or the database) and let the core
-- create it again. opx77_status creates its own table, opx77_character_status, in its own
-- resource.

-- One account, as the Master directory knows it. No password and no email: the platform proved
-- who this is before the session existed. `user_id` is ascii_bin because a case-insensitive
-- collation would make two Master-issued GUIDs compare equal.
CREATE TABLE IF NOT EXISTS opx77_users (
    user_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
    display_name VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- One character. `citizen_id` is the primary key because it is also the character key every
-- satellite addresses a character by. The JSON columns are never queried by their contents.
-- `cid` is a slot number and not an identity, so deleting character 2 of 3 leaves the third as
-- cid 3. `appearance` is NULL for a character that has never been to the mirror. A delete is
-- soft: `deleted_at` is stamped and the row stays.
CREATE TABLE IF NOT EXISTS opx77_characters (
    citizen_id VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
    user_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    cid TINYINT UNSIGNED NOT NULL DEFAULT 1,
    name VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '',
    char_info JSON NOT NULL,
    money JSON NOT NULL,
    job JSON NOT NULL,
    gang JSON NOT NULL,
    position JSON NULL DEFAULT NULL,
    metadata JSON NOT NULL,
    appearance JSON NULL DEFAULT NULL,
    last_logged_out TIMESTAMP NULL DEFAULT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL DEFAULT NULL,
    KEY idx_opx77_characters_user (user_id, deleted_at),
    CONSTRAINT fk_opx77_character_user
        FOREIGN KEY (user_id) REFERENCES opx77_users (user_id)
        ON DELETE CASCADE
) ENGINE=InnoDB;

-- Every job and gang membership a character holds. The composite primary key makes rejoining a
-- group a promotion, not a duplicate row.
CREATE TABLE IF NOT EXISTS opx77_character_groups (
    citizen_id VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    group_type ENUM('job', 'gang') NOT NULL,
    group_name VARCHAR(48) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    grade TINYINT UNSIGNED NOT NULL DEFAULT 0,
    joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (citizen_id, group_type, group_name),
    KEY idx_opx77_character_groups_lookup (group_type, group_name, grade),
    CONSTRAINT fk_opx77_character_group_character
        FOREIGN KEY (citizen_id) REFERENCES opx77_characters (citizen_id)
        ON DELETE CASCADE
) ENGINE=InnoDB;

-- What one character wears: the nine equipment slots, the seven wardrobe outfits and the active
-- one, as one JSON document written by server/clothing.lua and nothing else. A table of its own
-- rather than a column on opx77_characters, so the autosave that rewrites a character row never
-- rewrites what it wears. One row per character, none for a character whose clothing was never
-- saved.
CREATE TABLE IF NOT EXISTS opx77_character_clothing (
    citizen_id VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
    clothing JSON NOT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_opx77_character_clothing_character
        FOREIGN KEY (citizen_id) REFERENCES opx77_characters (citizen_id)
        ON DELETE CASCADE
) ENGINE=InnoDB;

-- One owned vehicle, keyed on the plate rather than the runtime id: the Open77 vehicle id is
-- issued at spawn and is gone the moment the resource that owns it reloads. `state` is 0 out,
-- 1 stored, 2 impounded; `body` carries the whole damage view.
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

-- One container: a character's bag, a stash, the trunk or glovebox of an owned vehicle. `kind`
-- says which, `owner` says whose within that kind, and the pair is unique. Free text rather than
-- an ENUM, so a new kind of container needs no schema change. A bag carries its citizen id and a
-- vehicle's storage its plate, each with a cascading foreign key. `slots` and `max_weight`
-- (grams) are the size the container was created with, kept rather than re-read from a config,
-- so shrinking a size never evaporates what a container already holds.
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

-- One item stack in one slot of one container, so "who holds this" is a query rather than a
-- walk over every serialised bag. The primary key keeps two stacks out of one slot. `name` has
-- no foreign key: the item catalogue is a config file of opx77_inventory, and an item taken out
-- of it must not delete what players hold. `metadata` is what makes one copy unlike another and
-- is NULL for an ordinary one. A save rewrites a container's rows in one transaction.
CREATE TABLE IF NOT EXISTS opx77_inventory_items (
    inventory_id INT UNSIGNED NOT NULL,
    slot SMALLINT UNSIGNED NOT NULL,
    name VARCHAR(48) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    quantity INT UNSIGNED NOT NULL,
    metadata JSON NULL DEFAULT NULL,
    PRIMARY KEY (inventory_id, slot),
    KEY idx_opx77_inventory_items_name (name),
    CONSTRAINT fk_opx77_inventory_item_inventory
        FOREIGN KEY (inventory_id) REFERENCES opx77_inventories (id)
        ON DELETE CASCADE
) ENGINE=InnoDB;
