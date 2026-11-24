-- yourspace: initial PostgreSQL schema (PostgreSQL 17 + pgvector)
-- Runs once on an empty data volume via /docker-entrypoint-initdb.d.
-- When the Rust app exists, move this into sqlx migrations (migrations/0001_init.sql).

CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS vector;

-- ───────────── enums ─────────────
CREATE TYPE user_role         AS ENUM ('user', 'mod', 'admin');
CREATE TYPE media_kind        AS ENUM ('image', 'video');
CREATE TYPE sensitivity_state AS ENUM ('pending', 'safe', 'sensitive', 'blocked');
CREATE TYPE conversation_kind AS ENUM ('direct', 'group');

-- ───────────── users ─────────────
CREATE TABLE users (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username        CITEXT      NOT NULL UNIQUE CHECK (username ~ '^[A-Za-z0-9_]{3,32}$'),
    display_name    TEXT        NOT NULL CHECK (char_length(display_name) BETWEEN 1 AND 64),
    email           CITEXT      NOT NULL UNIQUE,
    password_hash   TEXT        NOT NULL,                 -- argon2id
    bio             TEXT        NOT NULL DEFAULT '' CHECK (char_length(bio) <= 500),
    avatar_media_id BIGINT,                               -- FK added after media table
    role            user_role   NOT NULL DEFAULT 'user',
    is_suspended    BOOLEAN     NOT NULL DEFAULT FALSE,
    follower_count  INT         NOT NULL DEFAULT 0,
    following_count INT         NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE user_settings (
    user_id        BIGINT  PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    hide_sensitive BOOLEAN NOT NULL DEFAULT TRUE,
    dm_policy      TEXT    NOT NULL DEFAULT 'everyone' CHECK (dm_policy IN ('everyone', 'following', 'nobody')),
    language       TEXT    NOT NULL DEFAULT 'en',
    theme          TEXT    NOT NULL DEFAULT 'system',
    extra          JSONB   NOT NULL DEFAULT '{}'::jsonb   -- future settings without migrations
);

CREATE TABLE sessions (
    token_hash BYTEA       PRIMARY KEY,                   -- sha256 of the cookie token
    user_id    BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    ip         INET,
    user_agent TEXT
);
CREATE INDEX sessions_user_idx    ON sessions (user_id);
CREATE INDEX sessions_expires_idx ON sessions (expires_at);

-- ───────────── media ─────────────
CREATE TABLE media (
    id                    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    owner_id              BIGINT            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind                  media_kind        NOT NULL,
    mime                  TEXT              NOT NULL,
    storage_key           TEXT              NOT NULL UNIQUE,   -- path under MEDIA_DIR
    thumbnail_key         TEXT,
    size_bytes            BIGINT            NOT NULL,
    width                 INT,
    height                INT,
    duration_ms           INT,
    sha256                BYTEA             NOT NULL,
    sensitivity           sensitivity_state NOT NULL DEFAULT 'pending',
    moderation_labels     JSONB,                               -- raw classifier output
    description           TEXT,                                -- AI-generated, searchable
    description_tsv       TSVECTOR GENERATED ALWAYS AS (to_tsvector('simple', coalesce(description, ''))) STORED,
    description_embedding VECTOR(768),                         -- nomic-embed-text is 768-dim
    processed_at          TIMESTAMPTZ,
    created_at            TIMESTAMPTZ       NOT NULL DEFAULT now()
);
CREATE INDEX media_owner_idx     ON media (owner_id, created_at DESC);
CREATE INDEX media_sha_idx       ON media (sha256);
CREATE INDEX media_pending_idx   ON media (created_at) WHERE sensitivity = 'pending';
CREATE INDEX media_desc_tsv_idx  ON media USING GIN (description_tsv);
CREATE INDEX media_desc_vec_idx  ON media USING hnsw (description_embedding vector_cosine_ops);

ALTER TABLE users
    ADD CONSTRAINT users_avatar_fk FOREIGN KEY (avatar_media_id) REFERENCES media(id) ON DELETE SET NULL;

-- ───────────── stickers ─────────────
CREATE TABLE stickers (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    owner_id   BIGINT REFERENCES users(id) ON DELETE CASCADE,   -- NULL = built-in/global
    name       TEXT   NOT NULL,
    media_id   BIGINT NOT NULL REFERENCES media(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX stickers_owner_idx ON stickers (owner_id);

-- ───────────── posts (every post can be a thread node) ─────────────
CREATE TABLE posts (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    author_id     BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    parent_id     BIGINT      REFERENCES posts(id) ON DELETE CASCADE,   -- NULL = thread start
    root_id       BIGINT      NOT NULL REFERENCES posts(id) ON DELETE CASCADE, -- set by trigger
    depth         INT         NOT NULL DEFAULT 0 CHECK (depth <= 50),            -- set by trigger
    body_md       TEXT        NOT NULL DEFAULT '' CHECK (char_length(body_md) <= 5000),
    body_html     TEXT        NOT NULL DEFAULT '',                      -- sanitized render of body_md
    like_count    INT         NOT NULL DEFAULT 0,
    reply_count   INT         NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    edited_at     TIMESTAMPTZ,
    -- "view delete": hidden from normal users, still visible to mods/admins
    deleted_at    TIMESTAMPTZ,
    deleted_by    BIGINT      REFERENCES users(id) ON DELETE SET NULL,
    delete_reason TEXT,
    search_tsv    TSVECTOR GENERATED ALWAYS AS (to_tsvector('simple', body_md)) STORED
);
CREATE INDEX posts_parent_idx   ON posts (parent_id, created_at);
CREATE INDEX posts_root_idx     ON posts (root_id, created_at);
CREATE INDEX posts_author_idx   ON posts (author_id, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX posts_timeline_idx ON posts (created_at DESC) WHERE deleted_at IS NULL AND parent_id IS NULL;
CREATE INDEX posts_search_idx   ON posts USING GIN (search_tsv);

CREATE FUNCTION posts_set_thread() RETURNS trigger AS $$
BEGIN
    IF NEW.parent_id IS NULL THEN
        NEW.root_id := NEW.id;
        NEW.depth   := 0;
    ELSE
        SELECT root_id, depth + 1 INTO NEW.root_id, NEW.depth FROM posts WHERE id = NEW.parent_id;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER posts_thread_bi BEFORE INSERT ON posts
    FOR EACH ROW EXECUTE FUNCTION posts_set_thread();

-- what normal users query; mods/admins query `posts` directly
CREATE VIEW public_posts AS SELECT * FROM posts WHERE deleted_at IS NULL;

CREATE TABLE post_media (
    post_id  BIGINT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    media_id BIGINT NOT NULL REFERENCES media(id) ON DELETE CASCADE,
    position SMALLINT NOT NULL DEFAULT 0,
    PRIMARY KEY (post_id, media_id)
);
CREATE INDEX post_media_media_idx ON post_media (media_id);

CREATE TABLE post_stickers (
    post_id    BIGINT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    sticker_id BIGINT NOT NULL REFERENCES stickers(id) ON DELETE CASCADE,
    position   SMALLINT NOT NULL DEFAULT 0,
    PRIMARY KEY (post_id, sticker_id, position)
);

-- ───────────── tags ─────────────
CREATE TABLE tags (
    id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name CITEXT NOT NULL UNIQUE CHECK (name ~ '^[a-z0-9_]{1,64}$')
);
CREATE TABLE post_tags (
    post_id BIGINT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    tag_id  BIGINT NOT NULL REFERENCES tags(id)  ON DELETE CASCADE,
    PRIMARY KEY (post_id, tag_id)
);
CREATE INDEX post_tags_tag_idx ON post_tags (tag_id, post_id DESC);

-- ───────────── polls ─────────────
CREATE TABLE polls (
    post_id        BIGINT PRIMARY KEY REFERENCES posts(id) ON DELETE CASCADE,
    allow_multiple BOOLEAN NOT NULL DEFAULT FALSE,
    closes_at      TIMESTAMPTZ
);
CREATE TABLE poll_options (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    poll_id    BIGINT NOT NULL REFERENCES polls(post_id) ON DELETE CASCADE,
    label      TEXT   NOT NULL CHECK (char_length(label) BETWEEN 1 AND 100),
    position   SMALLINT NOT NULL,
    vote_count INT NOT NULL DEFAULT 0,
    UNIQUE (poll_id, position)
);
CREATE TABLE poll_votes (
    option_id BIGINT NOT NULL REFERENCES poll_options(id) ON DELETE CASCADE,
    user_id   BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    poll_id   BIGINT NOT NULL REFERENCES polls(post_id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (option_id, user_id)
    -- single-choice polls: enforce "one vote per (poll_id, user_id)" in the app, inside the vote transaction
);
CREATE INDEX poll_votes_user_idx ON poll_votes (user_id, poll_id);

-- ───────────── social graph ─────────────
CREATE TABLE likes (
    user_id    BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    post_id    BIGINT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, post_id)
);
CREATE INDEX likes_post_idx ON likes (post_id);

CREATE TABLE follows (
    follower_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    followee_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (follower_id, followee_id),
    CHECK (follower_id <> followee_id)
);
CREATE INDEX follows_followee_idx ON follows (followee_id, follower_id);

-- ───────────── chat ─────────────
CREATE TABLE conversations (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    kind       conversation_kind NOT NULL DEFAULT 'direct',
    title      TEXT,
    direct_key TEXT UNIQUE,        -- 'min(userA,userB):max(...)' prevents duplicate 1:1 chats
    created_by BIGINT REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE conversation_members (
    conversation_id      BIGINT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id              BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    joined_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_read_message_id BIGINT,          -- read receipts: one pointer per member, not a row per message
    muted                BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (conversation_id, user_id)
);
CREATE INDEX conv_members_user_idx ON conversation_members (user_id);

CREATE TABLE messages (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    conversation_id BIGINT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id       BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body            TEXT   NOT NULL DEFAULT '' CHECK (char_length(body) <= 4000),
    media_id        BIGINT REFERENCES media(id)    ON DELETE SET NULL,
    sticker_id      BIGINT REFERENCES stickers(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    edited_at       TIMESTAMPTZ,
    deleted_at      TIMESTAMPTZ
);
CREATE INDEX messages_conv_idx ON messages (conversation_id, id DESC);
-- typing indicators are NOT stored: ephemeral over WebSocket + Redis pub/sub

-- ───────────── moderation audit ─────────────
CREATE TABLE audit_log (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    actor_id    BIGINT REFERENCES users(id) ON DELETE SET NULL,
    action      TEXT   NOT NULL,        -- 'post.view_delete', 'post.hard_delete', 'user.edit', 'user.suspend', ...
    target_type TEXT   NOT NULL,        -- 'post' | 'user' | 'media' | 'message'
    target_id   BIGINT NOT NULL,
    reason      TEXT,
    meta        JSONB  NOT NULL DEFAULT '{}'::jsonb,   -- before/after snapshot
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX audit_target_idx ON audit_log (target_type, target_id, created_at DESC);
CREATE INDEX audit_actor_idx  ON audit_log (actor_id, created_at DESC);
