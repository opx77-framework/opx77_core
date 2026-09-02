-- opx77_core, migration 0001_users. One account, as the Master directory knows it.
--
-- No password and no email: the platform proved who this is before the session existed.
-- `user_id` is ascii_bin because a case-insensitive collation would make two Master-issued
-- GUIDs compare equal.
--
-- The runner in server/storage/schema.lua applies this statement itself at boot. This file is
-- the copy an operator reads and, if they migrate by hand, runs.

CREATE TABLE IF NOT EXISTS opx77_users (
    user_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
    display_name VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;
