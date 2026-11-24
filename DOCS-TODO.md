1. **Do approved followers see hidden sections?** 
- ok ditch the whole public/private switch to "public, 'firends only', private" for likes, posts, reposts, etc

- need to add feature for posts explicitly on each post to allow "public, friends only, private"
    - this is different than your posts being set to private
    - if we set "account posts visibility" to private but each post is public they are actually private
    - "visibility for posts account setting" > "individual post visiblity setting on post"

2. **Replies from muted accounts in threads.**
- YES as you said this is correct: Still shown; mute only affects feeds, discover, search and the story tray.


3. **Avatar on private profiles.** actually always show the avatar don't hide it i forgot about it.




- need to add notification feature
    - on frontend it will be an icon with popup that lists
        - friend requests
        - replies in a comment section
        - system noticitaions: "your content has been removed for posting content that messes with our terms of service", "account banneded" / "site updates" / "..."
        - etc. can't remember what else to add if you have ideas tell me
    - for chats notifications new messages will be beside the chat icon in topbar
        - so i don't want new messages to mess with notifications
        - if an influsnser that get's bombarded with messages won't be able to see comment section replies etc
    

- we also need notification settings
    - show/hide comments on your posts
    - show/hide comment replies
    - show/hide friend requests
    - ...
    if im missing something tell me

- right now we will have a Discover page but what about a sperate Trending page? idea?

- also we need to brainstorm a topbar
    - for anon user it's login/register top left ; top right: discover, trending?
    - for logged in user top left will be a button for account with userpic "name" clicking takes you to your account
        - the rest of top bar top left: trending, discover, fyp, etc


4. **Private → public behaviour.**
    (Only flips the flag; toggles are unchanged and pending follow requests stay pending.)
    we will have 3 radio buttons:
        - stay pending (default)
        - reject all follow requests
        - accept all follow requests 


5. **Video duration cap, image size cap, and whether to transcode on upload.**
- video duration is is = 10 min
- image size is = 50 mb
- video size is = 50 mb
- all of these options will be global settings which we will be able to change in .env file
- also we will need enable disable ceirtan heavy parts of the site as a flag that can be enabled in .env
    - for example the ai ollama image flag detector that happens in the worker
    - we need to add a flag that lets the dev temporarily disable that heavy workload feature
    - if you have any other flags to switch during testing tell me
- transcode on upload keep that as maybe