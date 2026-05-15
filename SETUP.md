# Electric Monk - Setup Guide

## 1. Environment Variables

Create a `.env` file in the project root:

```bash
# Supabase Configuration
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key-here

# Venice AI Configuration (for prayer validation)
VITE_VENICE_API_KEY=your-venice-api-key-here
```

## 2. Supabase Database Setup

1. Go to [Supabase Dashboard](https://app.supabase.com)
2. Select your project
3. Navigate to **SQL Editor**
4. Copy and paste the contents of [`src/lib/supabase-schema.sql`](src/lib/supabase-schema.sql)
5. Click **Run** to execute the migration

This will create:
- `profiles` table (user metadata, ban timers, daily counts)
- `prayers` table (prayer history and status)
- `indulgences` table (ad view tracking)
- RLS policies for security
- Database functions for ban reduction and daily resets

## 3. Enable Google OAuth

1. In Supabase Dashboard, go to **Authentication** → **Providers**
2. Enable **Google**
3. You'll need:
   - **Google Cloud Console** → Create a new project or select existing
   - Enable **Google+ API**
   - Create **OAuth 2.0 Credentials**
   - Add authorized redirect URIs:
     - `https://your-project.supabase.co/auth/v1/callback`
     - `http://localhost:5173/auth/v1/callback` (for local dev)
4. Copy the **Client ID** and **Client Secret** to Supabase
5. Save the provider

## 4. Install Dependencies

```bash
npm install
```

## 5. Run Development Server

```bash
npm run dev
```

The app will be available at `http://localhost:5173`

## 6. Test the App

1. **Sign Up**: Create an account with email/password or Google OAuth
2. **Submit a Prayer**: Use the altar to submit a prayer request
3. **Test Ban System**: (Optional) Modify [`useBanTimer.js`](src/composables/useBanTimer.js) to test the Purgatory view
4. **Watch Indulgence**: If banned, test the ad reduction feature

---

## File Structure Summary

```
src/
├── composables/
│   ├── useAuth.js        # Authentication (Google + Email/Password)
│   ├── useBanTimer.js    # Ban timer and indulgence logic
│   └── usePrayers.js     # Prayer submission and history
├── views/
│   ├── LoginView.vue     # Login/Signup screen
│   ├── AltarView.vue     # Main prayer interface
│   └── PurgatoryView.vue # Ban timer + ad view screen
├── lib/
│   ├── supabase.js       # Supabase client initialization
│   └── supabase-schema.sql # Database migration script
└── App.vue               # Main app with view routing
```
