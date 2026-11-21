# yourspace
my social media platform

# it will include
## techstack
- written in rust
- postgres or neo4j (need to plan db)
- rabbitmq for messages?
- rust backend html server render and send to user
- real content caching (use rust's or redis? need to research)
- load balancer (write own or use nginx)

## pages
- accounts (bio, pic, posts, ...)
- posts (user, time, profile pic)
    - videos
    - image
    - simple markdown posts styling
    - making a post with video/image gens content description
      (add to hidden html element robots can see element or user with inspect element)
    - stickers
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

