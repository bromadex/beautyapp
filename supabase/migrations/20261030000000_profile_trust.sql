-- Trust numbers on a pro's public profile: years of experience (the pro
-- fills it in) and how many bookings they have completed on BeauTap.

ALTER TABLE provider_profiles ADD COLUMN IF NOT EXISTS years_experience smallint;
ALTER TABLE provider_profiles DROP CONSTRAINT IF EXISTS provider_years_experience_range;
ALTER TABLE provider_profiles ADD CONSTRAINT provider_years_experience_range
  CHECK (years_experience IS NULL OR years_experience BETWEEN 0 AND 60);

-- Bookings are private, so the public profile gets only the count.
CREATE OR REPLACE FUNCTION public.provider_completed_bookings(p_provider uuid) RETURNS integer
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT count(*)::int FROM bookings WHERE provider_id = p_provider AND status = 'completed';
$$;
GRANT EXECUTE ON FUNCTION public.provider_completed_bookings(uuid) TO anon, authenticated;
