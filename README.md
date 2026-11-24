# yourspace
my social media platform

# it will include
## techstack
- everything is ran in docker
    - make Dockerfile for:
        - postgres (db)
        - my app (rust)
        - nginx (balance loader)
    - make docker compose file that runs everything
- written in rust
- postgres or neo4j (need to plan db)
- rabbitmq for messages?
- rust backend html server render and send to user
- real content caching (use rust's or redis? need to research)
- load balancer (write own or use nginx)
- rate limiter for pages
    - tiny for media files (user needs to spam really hard to get limited)
    - bigger for pages

## pages
- accounts (bio, pic, posts, ...)
a.k.a users
    - can be: normal users, mods, admins
- mods can 'view delete' posts (view delete: just means post is marked as deleted and normal users can't view them: mods and admins can)
- admin pannel
    - admins can also 'view delete' posts
    - admins can also delete fully posts
    - allows full control of accounts
        - what account you are following
    - can edit any users account delete his posts
    - view extra info for all posts
- my account (user, mod, admin)
    - allows user to edit his pic, bio, name, username
    - allows users to post, delete posts, make stickers, etc
- posts (user, time, profile pic)
    - videos
    - image
    - simple markdown posts styling
    - every post can be a thread
        - can have children posts which can have children and so on
        - so every post should have a parent field (it's null if it's a thread start) 
    - making a post with video/image gens content description
      (add to hidden html element robots can see element or user with inspect element)
    - stickers
    - poll (users can create and vote on polls)
    - make tags (optional/searchable for posts)
        - when user types "#something " space take that text put a span/div in the bottom with [x] to remove tag
- likes, followers
- feed,fyp,discover?
- search sorting posts
    - searching posts by keyword
    - extracting description of image/(maybe video) - use an ollama model or CLIP
      and storing the result which is searchable
- chat
    - sending msgs / videos
    - realtime chat
    - read receipts
    - typing indicator
... will expand with ER model
    - stickers
- stickers allowed in posts and in chat
- emojis allowed (autocomplete with :emoji: - e.g. :joy: - added on frontend) - in posts and chat

