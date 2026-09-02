--- Schema migrations, keyed by name and never by position. Every statement here is the one in
--- the matching `sql/` file and the two are edited together -- see README, "The schema".

OPX.Schema = {
  {
    name = "0001_users",
    file = "sql/users.sql",
    statements = {
      [[
CREATE TABLE IF NOT EXISTS opx77_users (
    user_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
    display_name VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB
      ]],
    },
  },

  {
    name = "0002_characters",
    file = "sql/characters.sql",
    statements = {
      [[
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
) ENGINE=InnoDB
      ]],
    },
  },

  {
    name = "0003_character_groups",
    file = "sql/character_groups.sql",
    statements = {
      [[
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
) ENGINE=InnoDB
      ]],
    },
  },

  {
    name = "0004_vehicles",
    file = "sql/vehicles.sql",
    statements = {
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
    CONSTRAINT fk_opx77_vehicle_character
        FOREIGN KEY (citizen_id) REFERENCES opx77_characters (citizen_id)
        ON DELETE CASCADE
) ENGINE=InnoDB
      ]],
    },
  },
}
