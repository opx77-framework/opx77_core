--- Schema migrations, append-only.
---
--- Never edit an entry that has shipped: it has already run on live databases
--- and the runner keys on the name. Add a new one instead.

return {
  {
    name = "0001_accounts",
    statements = {
      -- user_id is the Master-signed durable identifier. It is the account:
      -- there is no password, no email, nothing else to verify.
      [[
        CREATE TABLE IF NOT EXISTS synk_accounts (
          user_id      VARCHAR(190) NOT NULL PRIMARY KEY,
          display_name VARCHAR(190) NOT NULL,
          created_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
          last_seen_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
      ]],
    },
  },
  {
    name = "0002_characters",
    statements = {
      -- public_code is what players type at each other: transfers, reports,
      -- admin lookups. It is not the primary key, so it can be reissued
      -- without rewriting every foreign key that points at a character.
      [[
        CREATE TABLE IF NOT EXISTS synk_characters (
          id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
          user_id        VARCHAR(190) NOT NULL,
          public_code    VARCHAR(16)  NOT NULL,
          first_name     VARCHAR(64)  NOT NULL,
          last_name      VARCHAR(64)  NOT NULL,
          position_x     DOUBLE       NULL,
          position_y     DOUBLE       NULL,
          position_z     DOUBLE       NULL,
          created_at     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
          last_played_at TIMESTAMP    NULL DEFAULT NULL,
          deleted_at     TIMESTAMP    NULL DEFAULT NULL,
          UNIQUE KEY uq_public_code (public_code),
          KEY idx_user (user_id, deleted_at),
          CONSTRAINT fk_character_account
            FOREIGN KEY (user_id) REFERENCES synk_accounts (user_id)
            ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
      ]],
    },
  },
}
