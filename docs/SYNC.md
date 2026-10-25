# Syncing Nudge between your Mac and Android phone

Nudge syncs through a free [Supabase](https://supabase.com) project. Supabase gives you a
Postgres database plus email/password sign-in on its free plan. Both apps talk to it with plain
HTTPS calls, so there is no SDK to install.

## One-time setup (about 5 minutes)

1. Sign up at supabase.com and create a **New project** (any name, pick a region near you, set a
   database password and keep it somewhere safe; the apps never need it).
2. In the dashboard open **SQL Editor → New query**, paste the contents of
   [`supabase/schema.sql`](../supabase/schema.sql) and press **Run**.
3. Open **Authentication → Sign In / Providers → Email** and turn **Confirm email** *off*
   (otherwise you have to click a link in a verification email before the first sign-in works).
4. Open **Project Settings → API** and copy two values:
   - **Project URL** (looks like `https://abcdefgh.supabase.co`)
   - **anon public** key (a long `eyJ…` string). This key is safe to put in the apps; row-level
     security means each signed-in user can only see their own rows.

## Connect the apps

**Mac**: Nudge → Settings (⌘,) → **Account** tab → paste the URL and anon key → enter an email and
password → **Create Account** the first time, **Sign In** afterwards.

**Android**: Nudge → ⚙ Settings → **Account** → same URL and key → same email/password → Sign In.

Each app syncs on launch, a couple of seconds after any change, and about once a minute while open.
The Android app also syncs in the background roughly every 15 minutes.

## How sync works

- Every todo carries `updated_at`. Whichever device saved most recently wins.
- Deleting a todo sets `deleted_at` instead of removing the row, so the delete reaches other devices.
- "Already shown" state for reminders stays local to each device, so both your Mac and your phone
  nudge you. Snoozing or completing on one device updates the other.

## Free plan caveat

Free Supabase projects **pause after 7 days without any database request**. Your data is kept, but
sync stops until you click **Restore** in the Supabase dashboard. Using Nudge most days keeps it awake.
If that is a problem, Firebase's free Spark plan does not pause, but it requires its native SDKs.
