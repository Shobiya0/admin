# Choice Digital Marketing — Vercel + Supabase Client Portal

This version includes:
- Public Choice Digital Marketing website
- Gold logo/theme
- WhatsApp: +91 89032 68899
- Email: rshofiya@gmail.com
- Demo Admin panel
- Demo Client panel
- Admin-only pricing management
- Real Supabase email invitations for clients
- Client first-login password setup
- Client-specific data isolation with RLS
- Client changes publish immediately
- Admin notification for client website changes
- Vercel SPA routing

## 1. Local preview first

Open the `choice-digital-marketing` folder in VS Code.

```powershell
npm install
npm run dev
```

Open:
- Website: http://localhost:5173/
- Admin: http://localhost:5173/admin
- Client: http://localhost:5173/client

Without Supabase environment variables, the panels use local Demo Mode.

## 2. Important access rule

Pricing is ADMIN ONLY.

Clients can edit only:
- Homepage headline
- Homepage description
- Phone
- WhatsApp
- Email
- Address
- About text

Clients cannot edit pricing, other clients, admin settings, or another client's content.

The database also enforces the editable-field rule; do not rely only on the UI.

## 3. Create Supabase project

Create a Supabase project and open SQL Editor.

Run the complete `supabase.sql` file.

This creates:
- profiles
- clients
- site_content
- pricing
- notifications
- activity_logs
- RLS policies
- client-field protection trigger
- pricing realtime

## 4. Create your main admin

In Supabase:
1. Go to Authentication → Users.
2. Create a user with:
   `rshofiya@gmail.com`
3. Copy that user's UUID.
4. In SQL Editor run:

```sql
insert into public.profiles(id, role, email)
values('PASTE_AUTH_USER_UUID_HERE', 'super_admin', 'rshofiya@gmail.com')
on conflict (id) do update
set role='super_admin', email='rshofiya@gmail.com';
```

Now you can use `/admin` with that email/password.

## 5. Configure email invitations

In Supabase Authentication → URL Configuration, add your production client URL, for example:

`https://YOUR-DOMAIN.com/client`

Also add the local URL while testing:

`http://localhost:5173/client`

For reliable production invitation emails, configure a custom SMTP provider in Supabase Authentication settings.

## 6. Deploy the invitation Edge Function

The function is located at:

`supabase/functions/invite-client/index.ts`

Deploy it as a Supabase Edge Function named:

`invite-client`

If using Supabase CLI:

```powershell
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase functions deploy invite-client
```

The function uses the Supabase service-role key only on the server side. Never put the service-role key in Vercel frontend environment variables.

## 7. Vercel environment variables

Add these in Vercel:

`VITE_SUPABASE_URL`

`VITE_SUPABASE_ANON_KEY`

Use the Supabase Project URL and anon/public key.

Do NOT add `SUPABASE_SERVICE_ROLE_KEY` to Vercel frontend variables.

The Edge Function receives its service-role secret from Supabase's server-side environment.

## 8. How you give a client access

After production setup:

1. Login to `/admin`.
2. Open Clients.
3. Enter business/client name.
4. Enter client's email.
5. Click **Send invitation**.
6. Supabase sends the invitation email.
7. Client clicks the email.
8. Client is taken to `/client`.
9. Client creates a password on first login.
10. Client can then log in with email + password.

The client only sees the client dashboard attached to their client ID.

## 9. What happens when a client changes something

Client saves a permitted website field → it goes live immediately → database trigger creates an activity log + admin notification.

There is no approval workflow.

## 10. What happens with pricing

Only the main admin can edit pricing.

If the admin changes:

`Google Business Profile Setup — ₹4,999`

to:

`₹5,499`

clients cannot overwrite that price.

The public website reads production pricing from Supabase when configured and listens for realtime pricing changes.

## 11. Demo mode warning

Demo mode is for local testing only. It uses browser localStorage and is NOT real authentication.

Use Supabase Auth + RLS before giving the site to real clients.
