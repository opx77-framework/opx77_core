--- Schema migrations, append-only: the runner keys on the name, so an edited statement never
--- runs again on a database that has it. `user_id` is ascii_bin because a case-insensitive
--- collation would make two Master-issued GUIDs compare equal; `citizen_id` is the primary
--- key because it is also the `character_key`. No comment inside any SQL string.

OPX.Schema = {
  {
    name = "0001_accounts",
    statements = {
      -- no password and no email: the platform proved who this is before the session existed
      [[
CREATE TABLE IF NOT EXISTS opx77_accounts (
    user_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
    display_name VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB
      ]],
    },
  },

  {
    name = "0002_players",
    statements = {
      -- the JSON columns are never queried by their contents; `cid` is a slot number, not an
      -- identity, so deleting character 2 of 3 leaves the third as cid 3
      [[
CREATE TABLE IF NOT EXISTS opx77_players (
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
    last_logged_out TIMESTAMP NULL DEFAULT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL DEFAULT NULL,
    KEY idx_opx77_players_user (user_id, deleted_at),
    CONSTRAINT fk_opx77_player_account
        FOREIGN KEY (user_id) REFERENCES opx77_accounts (user_id)
        ON DELETE CASCADE
) ENGINE=InnoDB
      ]],
    },
  },

  {
    name = "0003_player_groups",
    statements = {
      -- the composite primary key makes rejoining a group a promotion, not a duplicate row
      [[
CREATE TABLE IF NOT EXISTS opx77_player_groups (
    citizen_id VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    group_type ENUM('job', 'gang') NOT NULL,
    group_name VARCHAR(48) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    grade TINYINT UNSIGNED NOT NULL DEFAULT 0,
    joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (citizen_id, group_type, group_name),
    KEY idx_opx77_groups_lookup (group_type, group_name, grade),
    CONSTRAINT fk_opx77_group_player
        FOREIGN KEY (citizen_id) REFERENCES opx77_players (citizen_id)
        ON DELETE CASCADE
) ENGINE=InnoDB
      ]],
    },
  },

  {
    name = "0004_vehicles",
    statements = {
      -- keyed on the plate, not the runtime id: the Open77 vehicle id is issued at spawn and
      -- is gone the moment the resource that owns it reloads
      [[
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
    CONSTRAINT fk_opx77_vehicle_player
        FOREIGN KEY (citizen_id) REFERENCES opx77_players (citizen_id)
        ON DELETE CASCADE
) ENGINE=InnoDB
      ]],
    },
  },
}
