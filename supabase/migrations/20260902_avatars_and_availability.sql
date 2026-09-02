-- ============================================================
-- BeauTap Migration: Avatars & Provider Availability
-- Run this in Supabase Dashboard → SQL Editor
-- ============================================================

-- 1. Add avatar_url to profiles
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS avatar_url text;

-- 2. Create avatars storage bucket (public so images load without auth)
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;

-- 3. Storage policies for avatars bucket
CREATE POLICY "Anyone can view avatars"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');

CREATE POLICY "Authenticated users upload own avatar"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'avatars'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Users update own avatar"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'avatars'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Users delete own avatar"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'avatars'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- 4. Provider availability / working hours
CREATE TABLE IF NOT EXISTS provider_availability (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  day_of_week smallint NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
  start_time time NOT NULL,
  end_time time NOT NULL,
  is_available boolean NOT NULL DEFAULT true,
  created_at timestamptz DEFAULT now(),
  UNIQUE (provider_id, day_of_week)
);

-- 5. Blocked dates (holidays, personal days off)
CREATE TABLE IF NOT EXISTS provider_blocked_dates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  blocked_date date NOT NULL,
  reason text,
  created_at timestamptz DEFAULT now(),
  UNIQUE (provider_id, blocked_date)
);

-- 6. RLS for availability
ALTER TABLE provider_availability ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view provider availability"
  ON provider_availability FOR SELECT USING (true);

CREATE POLICY "Providers manage own availability"
  ON provider_availability FOR INSERT
  WITH CHECK (auth.uid() = provider_id);

CREATE POLICY "Providers update own availability"
  ON provider_availability FOR UPDATE
  USING (auth.uid() = provider_id);

CREATE POLICY "Providers delete own availability"
  ON provider_availability FOR DELETE
  USING (auth.uid() = provider_id);

-- 7. RLS for blocked dates
ALTER TABLE provider_blocked_dates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view blocked dates"
  ON provider_blocked_dates FOR SELECT USING (true);

CREATE POLICY "Providers manage own blocked dates"
  ON provider_blocked_dates FOR INSERT
  WITH CHECK (auth.uid() = provider_id);

CREATE POLICY "Providers update own blocked dates"
  ON provider_blocked_dates FOR UPDATE
  USING (auth.uid() = provider_id);

CREATE POLICY "Providers delete own blocked dates"
  ON provider_blocked_dates FOR DELETE
  USING (auth.uid() = provider_id);

-- 8. Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_availability_provider ON provider_availability(provider_id);
CREATE INDEX IF NOT EXISTS idx_blocked_dates_provider ON provider_blocked_dates(provider_id);
CREATE INDEX IF NOT EXISTS idx_blocked_dates_date ON provider_blocked_dates(blocked_date);
