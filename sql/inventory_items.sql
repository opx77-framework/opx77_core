-- opx77_core, migration 0006_inventory_items. One item stack in one slot of one container, so
-- "who holds this" is a query rather than a walk over every serialised bag. The primary key is
-- what keeps two stacks out of one slot.
--
-- `name` has no foreign key: the item catalogue is a config file of opx77_inventory, and an item
-- taken out of it must not delete what players hold. `metadata` is what makes this one copy
-- unlike another -- a serial, rounds, a condition -- and is NULL for an ordinary one.
--
-- A save rewrites a container's rows in one transaction: delete, then insert.
--
-- The runner in server/storage/schema.lua applies this statement itself at boot. This file is
-- the copy an operator reads and, if they migrate by hand, runs.

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
