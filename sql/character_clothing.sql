-- opx77_core, migration 0007_character_clothing. What one character wears: the nine equipment
-- slots, the seven wardrobe outfits and the active one, as one JSON document written by
-- server/clothing.lua and nothing else. Its own table rather than a column on
-- opx77_characters, so a database without it still loads every character, and the autosave
-- that rewrites a character row never rewrites what it wears.
--
-- One row per character, and none for a character whose clothing was never saved. The foreign
-- key cascades, so the row goes when the character row is really deleted; a character's delete
-- is soft, so it stays, as its bag and vehicles do.
--
-- The runner in server/storage/schema.lua applies this statement itself at boot, and boots
-- without it when it fails: clothing is then neither restored nor saved. This file is the copy
-- an operator reads and, if they migrate by hand, runs.

CREATE TABLE IF NOT EXISTS opx77_character_clothing (
    citizen_id VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
    clothing JSON NOT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_opx77_character_clothing_character
        FOREIGN KEY (citizen_id) REFERENCES opx77_characters (citizen_id)
        ON DELETE CASCADE
) ENGINE=InnoDB;
