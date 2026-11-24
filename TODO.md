- mods can ban accounts
- add to notifications: repost, like, poll_closed 
- also add a settings for each thing in the notification to receive it or not

- soft and hard ip bans are rarely gonna be used
- only admins will do them

- mods can ban/unban user view their deleted posts and stuff
    - so they can search them and find them

- if a normal user or anon can't search banned account,
    they can't see his posts (while mods/admin can)
    going directly to the /users/{username} account will render
    "this account has been banned" always

> Interpretation: you wrote "tiny for media, bigger for pages". I read it as *media = very lenient limit, pages = tighter limit*. If you meant the opposite, swap the two `rate=` values.
Yes that is what i meant remove this notice ... lenient limit for media, tighter for pages


- drop markdown support in posts what i actually ment is just simple text bolding with *asterisk* _italic_ etc like other sites do no complex header markdown stuff


- Yes add:
    - email to accounts
        - we also need to check if email is valid on frontend and backend before register
        - we send email conformation request with an giant token hex number query string
            - no expiration
        - when user registers we redirect to page "confirm email" frontend waits for server to reply with email confirmed
            - "confirm email" page also has a "resend confirimation email" button
            - user can't do anything with account until they confirm email it's like they are anons
        - so i guess need to add email confirmation to ER
            - also add to User entity a bool that email is confirmed
        - when user gets the email he needs to click the link to confirm the email
        - when the link is clicked the "confirm email" frontend receives the message and redirects the user to his account settings page as we stated previously so he can manage "private" "public" etc
        - that welcome guide can be skiped which just redirects to users account page
        - the welcome guide let's the user select his options


Account deletion and data export. User-initiated deletion with a grace period, then a purge of rows and media files, plus an export of the user's own data. Legally required in many regions.
- also add in settings "disable account" which will log you out and hide the account from the site
 logging in will bring the account back, but hiding the account hides posts replies everything the account made
- where as "permanent delete account" actually deletes everything


add everything else you suggested below maybe