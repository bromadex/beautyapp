-- What a pro specialises in (service category ids), picked at sign-up or in
-- the profile editor and shown on their public profile.
ALTER TABLE provider_profiles ADD COLUMN IF NOT EXISTS specialties uuid[] NOT NULL DEFAULT '{}';
ALTER TABLE provider_profiles DROP CONSTRAINT IF EXISTS provider_specialties_max;
ALTER TABLE provider_profiles ADD CONSTRAINT provider_specialties_max CHECK (cardinality(specialties) <= 12);

-- Pros who already have services get their specialties filled from them.
UPDATE provider_profiles pp
   SET specialties = sub.ids
  FROM (SELECT provider_id, (array_agg(DISTINCT category_id))[1:8] AS ids
          FROM services WHERE is_active AND category_id IS NOT NULL GROUP BY provider_id) sub
 WHERE sub.provider_id = pp.provider_id AND cardinality(pp.specialties) = 0;

-- Dismiss the old test report filed against the admin account on 29 Sep 2026.
UPDATE disputes SET status = 'dismissed', resolved_at = now(),
       resolution = coalesce(resolution, 'Test report, dismissed.')
 WHERE id = '9ddf82ad-ee94-46ad-a71c-45884ad88448' AND status IN ('open', 'under_review');
