# Sharing Club Host across devices

Club Host keeps each club encrypted with its password. With sync switched on, the
encrypted records live on your own free Supabase project, so every founder can open
the club on their own phone or laptop with the club name and password, and changes
appear on every device within seconds.

The server only ever stores scrambled data. The password never leaves anyone's device,
and there is still no password reset: if the password is lost, so are the records.

## 1. Create the Supabase project (about 5 minutes, one time)

1. Go to <https://supabase.com>, sign up (free) and click **New project**.
   Pick any name (e.g. `club-host`), set a database password (just for Supabase —
   keep it somewhere safe) and choose the region closest to you (e.g. *South Asia (Mumbai)*).
2. When the project is ready, open **SQL Editor → New query**, paste the whole of
   `supabase-setup.sql` from this folder, and press **Run**. You should see "Success".
3. Open **Project Settings → API Keys** (or the **Connect** button) and copy:
   - the **Project URL** — looks like `https://abcdefghijklmnop.supabase.co`
   - the **publishable key** (`sb_publishable_…`) or the legacy **anon public** key (`eyJ…`).
     Both are meant to be public. Never use the *secret* / *service_role* key.

## 2. Put the two values into Club Host

Open `index.html` in a text editor (Notepad is fine). Near the top you'll find:

```html
window.CLUB_HOST_CLOUD = {
  url: "",
  anonKey: ""
};
```

Paste the Project URL between the first pair of quotes and the key between the second, then save.

## 3. Put the site online

Every founder needs the same web address. This club's site is on **GitHub Pages**:

- Live site: <https://harshmpatel30.github.io/club-host/>
- Source files: <https://github.com/harshmpatel30/club-host> (repository `club-host`,
  published from the `main` branch in *Settings → Pages*)

The page must be opened over **https** (GitHub Pages always is), because the browser only
allows encryption on secure pages.

## 4. Move your club online and invite the founders

1. Open the new link on **your** device first and log in to your club as usual. You'll be
   asked **"Put '…' online?"**; choose **OK**. You'll then see "…is now online".
2. Send the founders the link, the club name and the password (in person or a private chat).
3. On their device they choose **Log in**, type the club name and password, and they're in.

If a founder had made their *own* club with the same name before sync, the app opens the
shared club and asks what to do with theirs:

- **OK** adds its members, attendance and sessions to the shared club.
- **Cancel** keeps it separately on that device as "… (this device)".

The top bar shows **Synced** when everything is saved, **Offline · saved on this device**
without internet (changes go up automatically when the connection returns), and
"2 open now" when several devices have the club open.

## Keeping your data safe (important)

Your club's records live in several places at once and sync between them: on Supabase,
and an encrypted copy on every device that opens the club. So one device breaking, or
the server pausing, does not lose anything.

Two things are still on you:

1. **Write the password down** somewhere safe. Everything is encrypted with it, and there
   is **no password reset** — if it's lost, the records can't be recovered by anyone.
2. **Download a backup now and then.** In the top bar, click the **shield** button →
   **Download a backup**. It saves a file to your device with the whole club in it. Keep it
   in Google Drive or email it to yourself. If anything ever goes wrong, open the club and
   use **Restore from a backup** to put it all back. A good habit: download one after each
   meeting.

## Changing the website later

The website (`index.html`) and your club's records are separate. Updating the website
never touches the records, which stay in Supabase and on each device.

1. **Edit the master copy only:** `index.html` in this folder
   (`OneDrive\Desktop\club host`). Any copy you downloaded from a chat is just a duplicate.
   Open this folder in Claude Code and describe the change you want, or edit it yourself.
2. **Keep the sync settings** near the top (`url` and `anonKey`). If they're emptied, the
   site stops syncing and falls back to "this device only".
3. **Download a backup first** (shield button). It's a cheap safety net.
4. **Publish the new version:** this folder is a Git repository connected to GitHub.
   Commit the change and push it (Claude Code does this for you when you ask:
   "commit and push"). GitHub Pages rebuilds the site by itself in about a minute, at the
   same link.
5. **Founders just refresh the page** to get the new version. Nothing to reinstall, and
   nobody has to log in again unless they had locked the club.

Never commit a downloaded backup file: it holds members' names and the repository is
public. The `.gitignore` in this folder already blocks every `.json` file for that reason.

## Good to know

- If two founders change things at the same moment, both changes are kept. For example,
  one marks attendance while the other logs a session.
- **School or library computer?** Tick *"Shared or public computer"* on the login screen
  and nothing is kept on that computer. On your own devices, the × next to a club under
  *Opened on this device* removes that device's copy; the club stays online.
- After 10 wrong passwords within 15 minutes, logins for that club from that internet
  connection are paused for 15 minutes. This slows down anyone guessing.
- Free Supabase projects are paused after about a week with no use at all. If the site
  says it can't reach the club server, open your Supabase dashboard and press **Restore**.
- To go back to "this device only", empty the two values again. Clubs stay on each device
  they were opened on.
