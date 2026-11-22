# YourSpace --- Social Media Platform Plan

> **Project goal:** Build a Rust-based social platform for user
> profiles, posts, media, discovery, and real-time messaging. This
> document defines an initial architecture, feature scope, data model
> direction, security rules, and an implementation roadmap. It is a
> living plan; update it as the ER model and product requirements become
> clearer.

## 1. Product overview

YourSpace is a social media platform where people can:

-   Create accounts and customizable profiles.
-   Publish text, image, and video posts.
-   Like posts and follow other accounts.
-   Browse a personalized feed, discovery feed, and search results.
-   Chat in real time, including media, stickers, emoji, typing
    indicators, and read receipts.
-   Create and use stickers in posts and chats.

The platform has three account roles:

  -----------------------------------------------------------------------
  Role                                Main permissions
  ----------------------------------- -----------------------------------
  User                                Manage own profile and content;
                                      follow accounts; post, like, and
                                      chat

  Moderator                           User permissions plus moderation
                                      access to soft-deleted posts and
                                      moderation actions

  Administrator                       Full platform control, including
                                      account management, audit
                                      information, and permanent deletion
  -----------------------------------------------------------------------

Use **role-based access control (RBAC)** and enforce permissions in the
backend. Hiding a button in the frontend is not access control.

## 2. Recommended initial technology stack

Prefer a modular monolith first: one Rust application with clearly
separated modules. Split services only when scale or operational needs
justify it.

  -----------------------------------------------------------------------
  Area                    Initial recommendation  Notes
  ----------------------- ----------------------- -----------------------
  Language                Rust                    Shared domain types and
                                                  validation

  Web framework           Axum                    Async HTTP routing and
                                                  middleware

  HTML rendering          Server-side rendering   Send complete HTML; use
                          with Askama or Maud     small amounts of
                                                  JavaScript for
                                                  interactive features

  Database                PostgreSQL              Primary source of truth
                                                  for accounts, posts,
                                                  follows, likes,
                                                  permissions, and chat
                                                  metadata

  Database access         SQLx                    Compile-time checked
                                                  queries and migrations

  Cache / ephemeral state Redis                   Cache, sessions if
                                                  desired, rate-limit
                                                  counters, presence, and
                                                  short-lived state

  Background jobs         RabbitMQ, if needed     Asynchronous media
                                                  processing,
                                                  notifications,
                                                  indexing, and other
                                                  durable jobs

  Realtime transport      WebSockets              Chat, typing
                                                  indicators, presence,
                                                  and read-receipt
                                                  updates

  Media storage           S3-compatible object    Store original
                          storage                 images/videos and
                                                  generated variants
                                                  outside PostgreSQL

  Reverse proxy / load    Nginx or Caddy          TLS termination,
  balancer                initially               routing, static/media
                                                  delivery, and request
                                                  limits

  Search                  PostgreSQL full-text    Evaluate dedicated
                          search initially        search later if
                                                  requirements outgrow it

  Image/video             Separate background     Ollama or a vision
  understanding           worker                  model can generate
                                                  searchable descriptions
                                                  asynchronously

  Observability           tracing + metrics +     Request IDs, latency,
                          structured logs         errors, queue depth,
                                                  and worker health
  -----------------------------------------------------------------------

### 2.1 PostgreSQL vs. Neo4j

**Recommendation: use PostgreSQL as the primary database.**

Most of YourSpace's core data is relational:

-   Users, profiles, roles, posts, comments, likes, follows, and
    permissions.
-   Chat conversations, participants, messages, and read states.
-   Moderation records and audit history.

PostgreSQL supports transactions, constraints, indexes, joins, JSONB,
and full-text search. A follow graph can initially be represented by a
normal `follows` table with indexes on both user IDs.

Neo4j is designed for graph traversal and may become useful if complex
multi-hop relationship queries become a major product feature. It adds
another database to operate and keep consistent. Do not introduce it
just because the platform has followers.

**Revisit Neo4j only if measured query workloads show PostgreSQL cannot
meet graph-query requirements.** If that happens, define which system
owns the canonical relationship data and how the graph projection is
updated.

### 2.2 RabbitMQ: do we need it?

Do not put every request through RabbitMQ. Normal page reads and writes
should use the application and PostgreSQL directly.

Use a message broker for work that can happen after the user's request
has completed:

-   Video transcoding and thumbnail generation.
-   Image resizing and metadata extraction.
-   AI-generated media descriptions and embeddings.
-   Notifications and email delivery.
-   Search indexing.
-   Feed fan-out jobs, if needed.
-   Cleanup and scheduled maintenance.

RabbitMQ is a reasonable choice when durable queues, acknowledgements,
retries, and routing are useful. Start with a small number of queues and
define retry limits and dead-letter handling. For a smaller first
version, a PostgreSQL-backed job queue can reduce infrastructure. Choose
one deliberately rather than operating both without a need.

### 2.3 Caching strategy

Use a layered strategy rather than trying to cache everything.

1.  **HTTP/browser caching:** Cache versioned static assets for a long
    time. Set correct `Cache-Control`, `ETag`, and `Last-Modified`
    headers where appropriate.
2.  **CDN or reverse-proxy caching:** Cache public, immutable media
    derivatives and public static resources.
3.  **Redis:** Cache expensive, frequently requested application data
    such as public profile summaries, selected post data, and feed
    fragments. Use short TTLs where freshness matters.
4.  **PostgreSQL:** Remains the source of truth. Cache misses must be
    safe and normal.

Define invalidation rules for profile edits, post edits/deletions,
privacy changes, and moderation actions. Never let a stale cache reveal
content that a user is no longer allowed to see.

Avoid caching personalized or private responses in shared HTTP caches.
Cache keys must include the relevant user/permission context when data
is user-specific.

### 2.4 Load balancing and deployment

Start with Nginx or Caddy in front of the Rust application. They already
handle TLS, reverse proxying, connection management, and common
operational concerns.

Do not write a custom load balancer for the initial release. A custom
implementation creates security, reliability, and maintenance work
without being a core product feature.

Possible deployment shape:

``` text
Browser / Mobile client
        |
   DNS + CDN (optional)
        |
 Nginx / Caddy
        |
  Rust web application  -------- PostgreSQL
        |                         Redis
        |                         Object storage
        |
   WebSocket endpoint
        |
 Background job publisher
        |
     RabbitMQ
        |
 Media / indexing / notification workers
```

Run multiple stateless application instances behind the proxy when
needed. Store sessions and shared ephemeral state outside individual
application processes. Use health checks and graceful shutdown.

## 3. Rate limiting and abuse protection

Rate limits should be applied by endpoint category and account state,
not as one global number.

  -----------------------------------------------------------------------
  Category                            Policy direction
  ----------------------------------- -----------------------------------
  HTML page reads                     Moderate limits; protect expensive
                                      routes and anonymous traffic

  Login / registration / password     Strict limits, progressive delays,
  reset                               and abuse monitoring

  Post creation / likes / follows     Limits based on user and action;
                                      prevent spam and automation

  Search                              Moderate limits; account for
                                      expensive queries

  Media downloads                     High tolerance for normal browsing
                                      and repeated playback; use
                                      CDN/object-storage delivery and
                                      bandwidth controls rather than an
                                      aggressively low request count

  Media uploads                       Limits based on file size, total
                                      storage, user quota, and concurrent
                                      uploads

  Chat messages                       Prevent flooding while allowing
                                      normal conversation

  WebSocket connections               Limit concurrent connections and
                                      reconnect frequency
  -----------------------------------------------------------------------

Implementation notes:

-   Use Redis-backed counters or token buckets when multiple app
    instances need shared limits.
-   Apply limits by IP and authenticated account where appropriate.
-   Account for shared IPs so schools, workplaces, and households are
    not unfairly blocked.
-   Return HTTP `429` with a useful `Retry-After` header.
-   Log limit events without recording private message contents.
-   Add per-user storage quotas, upload size limits, and maximum media
    duration.
-   Validate file type from content, not only the filename or
    browser-provided MIME type.
-   Never trust client-supplied paths or media metadata.

The intended media policy is **high tolerance for legitimate repeated
access**, not unlimited resource consumption. Protect bandwidth and
infrastructure with caching, quotas, and anomaly detection.

## 4. Feature requirements

### 4.1 Accounts and profiles

Each account has:

-   Unique username and account ID.
-   Display name.
-   Profile picture.
-   Bio.
-   Role: user, moderator, or administrator.
-   Account creation and update timestamps.
-   Account status (active, suspended, disabled, etc.).
-   Privacy settings to be defined.
-   Follower and following relationships.
-   Posts and other user-owned content.

Users can edit their own display name, username, profile picture, and
bio, subject to validation and rate limits.

Plan username rules early: allowed characters, case sensitivity,
reserved names, rename cooldowns, and uniqueness.

### 4.2 Posts

A post can contain:

-   Text with a restricted Markdown-style formatting subset.
-   One or more images.
-   Video.
-   Stickers.
-   Emoji.
-   A generated media description used for accessibility and search.

Each post should store its author, creation time, update time,
visibility, moderation state, and media references.

Post pages or feed cards should show:

-   Author name and profile picture.
-   Post timestamp.
-   Text and attached media.
-   Stickers and emoji.
-   Like and other interaction counts, where visible.

#### Media descriptions and accessibility

When a user uploads an image or video:

1.  Store the original media in object storage.
2.  Create a background processing job.
3.  Generate thumbnails and optimized variants.
4.  Optionally generate an image/video description using a vision model.
5.  Save the description and model metadata in the database.
6.  Make the description searchable and available as accessible
    alternative text when appropriate.

Do **not** hide keyword-stuffed text in an invisible HTML element for
search engines. Hidden text intended to manipulate indexing can be
treated as spam and is not a reliable accessibility solution.

Instead: - Store the generated description as structured post/media
metadata. - Render a proper `alt` attribute for images when a meaningful
description is available. - Offer users a way to review or edit
generated descriptions. - Use visible captions or descriptions when they
add context. - Keep machine-generated descriptions clearly
distinguishable from user-written text.

Video descriptions are more difficult and expensive. Consider extracting
representative frames and combining them with audio transcription only
if the product needs it. Make this asynchronous and optional.

#### Post deletion and moderation

Use soft deletion for normal deletion and moderation:

-   A deleted post is hidden from ordinary users.
-   Moderators and administrators can view soft-deleted posts where
    their permissions allow it.
-   Record who deleted or moderated the post, when, and why.
-   Preserve the original content for the configured retention period.

Permanent deletion is an administrator-only operation:

-   Require explicit confirmation.
-   Record the action in an immutable or append-only audit log.
-   Remove associated media and derived data according to the retention
    policy.
-   Define how backups and search indexes are handled; deleting a
    database row alone does not erase every copy.

### 4.3 Likes and follows

Required relationships:

-   User follows another user.
-   User likes a post.
-   Users can view follower/following lists subject to privacy settings.
-   Users can see like counts and, if allowed, who liked a post.

Use uniqueness constraints to prevent duplicate follows and likes. Add
indexes for both directions of the follow relationship and for post
engagement queries.

### 4.4 Feed, FYP, and Discover

Treat these as separate product surfaces:

-   **Following feed:** Posts from accounts the user follows.
-   **For You feed:** A ranked feed using relevance signals.
-   **Discover:** Content and accounts selected for exploration, trends,
    or categories.

Start with a chronological Following feed. Add a simple, explainable
ranking system later.

Potential ranking signals: - Follow relationship. - Recency. - User
interactions. - Topic or keyword relevance. - Content quality and
moderation status. - Repeated exposure controls.

Do not make the first release depend on a complex recommendation model.
Build event tracking and privacy controls before optimizing ranking.

### 4.5 Search

Initial search features:

-   Search users by username/display name.
-   Search posts by keyword.
-   Sort by newest, relevance, and possibly popularity.
-   Filter by author, media type, and date where useful.

Start with PostgreSQL full-text search and suitable indexes. Evaluate a
dedicated search engine only when search volume, typo tolerance,
faceting, or ranking requirements justify it.

For media search: - Generate image descriptions asynchronously. - Store
searchable text separately from the original post text. - Keep the
source of each description (user-provided, model-generated, edited). -
Consider embeddings/vector search later. PostgreSQL with `pgvector` may
be sufficient before adding another service. - Treat model output as
untrusted metadata: it can be inaccurate and must not override
moderation or access-control decisions.

### 4.6 Chat

Chat should support:

-   One-to-one conversations initially; group chats can follow.
-   Text messages.
-   Image and video attachments.
-   Stickers and emoji.
-   Message timestamps.
-   Delivery/read state.
-   Typing indicators.
-   Online/presence indicators, if enabled.
-   Message deletion/editing policy to be defined.

Use WebSockets for live updates. Persist messages in PostgreSQL; do not
rely on WebSocket memory as message storage.

Typing and presence are ephemeral and can live in Redis with short
expirations. Read receipts should be persisted or represented with
per-conversation/per-user read cursors, depending on the desired
behavior.

Plan for: - Reconnection and missed-message recovery. - Message
ordering. - Duplicate delivery and idempotency. - Per-conversation
authorization. - Attachment access control. - Blocking and reporting. -
Retention and deletion policies.

### 4.7 Stickers and emoji

**Stickers** - Users can create or upload stickers. - Stickers can be
used in posts and chat. - Define allowed formats, dimensions, file size,
animation policy, and moderation rules. - Store sticker files in object
storage and metadata in PostgreSQL. - Consider personal sticker
collections and favorites.

**Emoji** - Support standard Unicode emoji. - Add frontend autocomplete
such as `:joy:` that converts a shortcode into the corresponding
emoji. - Maintain a shortcode-to-Unicode mapping. - Use the same
picker/autocomplete behavior in posts and chat. - Ensure the text editor
does not unexpectedly convert code or ordinary text.

### 4.8 Admin panel

The admin panel should be a separate protected area with
backend-enforced permissions.

Administrator capabilities:

-   Search and inspect accounts.
-   Edit account fields and account status.
-   View account relationships, including who an account follows.
-   View, soft-delete, restore, and permanently delete posts.
-   View extra post information, such as moderation state,
    media-processing status, and relevant internal IDs.
-   Review reports and moderation history.
-   Manage roles and permissions.
-   Review audit logs.

Moderators should have a smaller interface and only the permissions
needed for moderation. They must not receive administrator-only account
controls or permanent-delete capabilities.

Every sensitive admin action should create an audit record containing
actor, action, target, timestamp, and reason. Avoid exposing passwords,
session secrets, or unnecessary private data in admin views.

## 5. Initial database design

PostgreSQL is the canonical data store. This is a starting point, not
the final ER model.

  -----------------------------------------------------------------------
  Table                               Purpose / likely fields
  ----------------------------------- -----------------------------------
  `users`                             `id`, `username`, `email`, password
                                      hash, role, status, timestamps

  `profiles`                          `user_id`, display name, bio,
                                      avatar media ID

  `follows`                           `follower_id`, `followed_id`,
                                      created time

  `posts`                             `id`, `author_id`, body,
                                      visibility, deletion state,
                                      timestamps

  `post_media`                        `id`, `post_id`, media ID,
                                      position, media type

  `media`                             object key, MIME type, size,
                                      dimensions/duration, processing
                                      state

  `likes`                             `user_id`, `post_id`, created time

  `stickers`                          owner, media ID, name, visibility,
                                      timestamps

  `post_stickers`                     `post_id`, `sticker_id`, position

  `conversations`                     `id`, type, created time

  `conversation_members`              `conversation_id`, `user_id`,
                                      joined time, read cursor

  `messages`                          `id`, `conversation_id`,
                                      `sender_id`, body, timestamps,
                                      deletion state

  `message_media`                     `message_id`, media ID, position

  `message_stickers`                  `message_id`, sticker ID, position

  `post_reports`                      reporter, post, reason, status,
                                      timestamps

  `moderation_actions`                actor, target, action, reason,
                                      timestamp

  `audit_logs`                        actor, action, target, metadata,
                                      timestamp

  `media_descriptions`                media ID, description, source,
                                      model/version, review state

  `notifications`                     recipient, type, related entity,
                                      read state, timestamp
  -----------------------------------------------------------------------

### Database design rules

-   Use generated UUIDs or another consistent primary-key strategy.
-   Add foreign keys and uniqueness constraints.
-   Add indexes based on actual query patterns.
-   Use transactions for multi-row operations such as creating a post
    with media references.
-   Keep media bytes out of PostgreSQL; store object-storage keys and
    metadata.
-   Define deletion and retention behavior before launch.
-   Use migrations from the beginning.
-   Do not store a follower count as the only source of truth. If
    denormalized counts are added for speed, define how they are
    reconciled.
-   Keep role and permission checks explicit and testable.

## 6. Backend structure

Suggested Rust workspace layout:

``` text
yourspace/
├── Cargo.toml
├── crates/
│   ├── app/                 # startup, configuration, dependency wiring
│   ├── web/                 # HTTP routes, SSR handlers, templates
│   ├── domain/              # entities, rules, permission checks
│   ├── db/                  # SQLx queries, repositories, migrations
│   ├── auth/                # sessions, password hashing, authorization
│   ├── media/               # upload validation and object storage
│   ├── chat/                # WebSocket handling and message logic
│   ├── jobs/                # background job definitions and workers
│   └── search/              # indexing and search queries
├── migrations/
├── templates/
├── static/
├── tests/
├── docs/
│   ├── architecture.md
│   ├── er-model.md
│   ├── permissions.md
│   └── api.md
└── deploy/
```

Keep domain logic independent of HTTP handlers. Route handlers should
validate input, call domain/application services, and render HTML or
return protocol responses.

## 7. Security, privacy, and reliability requirements

These are release requirements, not optional polish:

-   Hash passwords with a modern password-hashing algorithm such as
    Argon2id.
-   Use secure, HTTP-only, SameSite cookies for browser sessions.
-   Protect state-changing browser requests against CSRF.
-   Escape user-generated content and sanitize supported Markdown/HTML.
-   Validate and limit all uploads; scan or safely process untrusted
    media.
-   Authorize every post, message, media, and admin request on the
    server.
-   Use TLS in production.
-   Keep secrets out of source control and logs.
-   Add account recovery and session revocation.
-   Add blocking, reporting, and moderation workflows.
-   Define account privacy and content visibility rules.
-   Back up PostgreSQL and object storage; test restores.
-   Use database migrations and a rollback/recovery plan.
-   Add audit logs for privileged actions.
-   Set retention rules for deleted content, messages, logs, and
    backups.
-   Monitor queue failures, worker retries, storage usage, and database
    health.

## 8. Performance and scaling plan

Optimize based on measurements, not assumptions.

1.  Add indexes for common feed, profile, search, and chat queries.
2.  Paginate every potentially large list; prefer cursor pagination for
    feeds and messages.
3.  Resize and transcode media into multiple variants.
4.  Serve media through object storage/CDN rather than streaming every
    file through the Rust application.
5.  Cache public, frequently accessed data with explicit invalidation.
6.  Move slow work to background jobs.
7.  Add application instances behind Nginx/Caddy when CPU or concurrency
    requires it.
8.  Measure feed query performance before implementing feed fan-out.
9.  Add read replicas or specialized search infrastructure only when
    metrics justify them.

Track at least: - HTTP request rate, latency, and error rate. -
PostgreSQL query latency and connection-pool saturation. - Redis latency
and memory. - Queue depth, job age, retry count, and dead-letter
count. - Upload processing time and failure rate. - Object-storage usage
and egress. - WebSocket connections and message delivery latency.

## 9. Implementation roadmap

### Phase 0 --- Product and architecture decisions

-   [ ] Define public/private account behavior.
-   [ ] Define post visibility and deletion semantics.
-   [ ] Define username and account rules.
-   [ ] Define chat scope (one-to-one first or groups from day one).
-   [ ] Finalize the ER model.
-   [ ] Write permission matrix for user, moderator, and administrator.
-   [ ] Choose deployment and object-storage provider.
-   [ ] Document retention, privacy, and backup policies.

### Phase 1 --- Project foundation

-   [ ] Create Rust workspace and application configuration.
-   [ ] Set up Axum, SSR templates, and static assets.
-   [ ] Set up PostgreSQL, SQLx, and migrations.
-   [ ] Add authentication, sessions, and RBAC.
-   [ ] Add structured logging, tracing, and health checks.
-   [ ] Set up development and production deployment.

### Phase 2 --- Accounts and core social features

-   [ ] Registration, login, logout, and account recovery.
-   [ ] Profile pages and profile editing.
-   [ ] Follow/unfollow.
-   [ ] Create, edit, and soft-delete text posts.
-   [ ] Like/unlike posts.
-   [ ] Chronological Following feed.
-   [ ] Basic user and post search.

### Phase 3 --- Media and stickers

-   [ ] Object-storage integration.
-   [ ] Secure image/video uploads.
-   [ ] Background media processing.
-   [ ] Thumbnails and responsive media variants.
-   [ ] Media descriptions and accessible alt text.
-   [ ] Sticker creation and sticker picker.
-   [ ] Emoji shortcode autocomplete.

### Phase 4 --- Moderation and administration

-   [ ] Moderator tools for viewing and soft-deleted content.
-   [ ] Reporting workflow.
-   [ ] Admin account management.
-   [ ] Admin post inspection and restoration.
-   [ ] Permanent deletion with confirmation.
-   [ ] Audit log and permission tests.

### Phase 5 --- Chat

-   [ ] Conversation and participant model.
-   [ ] Persistent text messages.
-   [ ] WebSocket live delivery.
-   [ ] Reconnection and missed-message recovery.
-   [ ] Read receipts.
-   [ ] Typing indicators and presence.
-   [ ] Media, sticker, and emoji messages.
-   [ ] Blocking and reporting in chat.

### Phase 6 --- Discovery and advanced search

-   [ ] Discover page.
-   [ ] For You feed with a simple ranking model.
-   [ ] Search filters and sorting.
-   [ ] Background image-description generation.
-   [ ] Evaluate embeddings and `pgvector`.
-   [ ] Add dedicated search infrastructure only if needed.

### Phase 7 --- Production hardening

-   [ ] Redis cache and shared rate limiting.
-   [ ] CDN/reverse-proxy media caching.
-   [ ] Load and concurrency tests.
-   [ ] Backup and restore drills.
-   [ ] Security review and authorization tests.
-   [ ] Monitoring and alerting.
-   [ ] Document operational procedures.

## 10. Decisions to research and validate

  -----------------------------------------------------------------------
  Question                Starting position       What would change the
                                                  decision?
  ----------------------- ----------------------- -----------------------
  PostgreSQL or Neo4j?    PostgreSQL              Demonstrated graph
                                                  traversal bottlenecks

  RabbitMQ?               Add for durable         Job volume,
                          asynchronous jobs when  retry/routing needs,
                          needed                  operational complexity

  Redis or in-process     Redis for shared cache  Deployment topology and
  cache?                  and rate limits; local  measured cache workload
                          cache only for safe     
                          process-local data      

  Nginx or custom load    Nginx/Caddy             A genuine
  balancer?                                       product-specific
                                                  requirement that
                                                  existing proxies cannot
                                                  meet

  Search engine?          PostgreSQL full-text    Scale, typo tolerance,
                          search                  ranking, or faceting
                                                  requirements

  Ollama or CLIP?         Evaluate a              Accuracy, hardware
                          vision-language model   cost, latency, and
                          for descriptions and    privacy
                          embeddings for semantic 
                          similarity              

  Feed architecture?      Query-based             Feed latency at high
                          chronological feed      follower counts or high
                          first                   traffic

  Media delivery?         S3-compatible storage   Cost, geographic
                          plus CDN                distribution, and
                                                  provider constraints
  -----------------------------------------------------------------------

## 11. Suggested first milestone

The first usable release should be deliberately small:

1.  Registration and login.
2.  Editable user profiles.
3.  Text and image posts.
4.  Follow/unfollow.
5.  Likes.
6.  Chronological Following feed.
7.  Basic search.
8.  Moderator soft deletion and a minimal admin audit trail.

Do not start with recommendation algorithms, Neo4j, a custom load
balancer, or a complicated microservice architecture. Establish a
secure, testable core first, then expand.

------------------------------------------------------------------------

## Appendix: initial design principles

-   **PostgreSQL is the source of truth.**
-   **Object storage holds media; the database holds references and
    metadata.**
-   **The backend enforces every permission.**
-   **Slow or expensive work runs asynchronously.**
-   **SSR is the default page delivery model; JavaScript enhances
    interaction.**
-   **Caching must never bypass privacy or moderation rules.**
-   **Soft deletion and permanent deletion are distinct operations.**
-   **Start simple, measure, and scale the components that become
    bottlenecks.**
