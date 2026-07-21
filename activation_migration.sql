-- Stage 19: Client Activation Fee ($1)
-- Run this in the Supabase Dashboard SQL editor.

-- 1. Add activation flag (defaults false for new accounts)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_activated BOOLEAN DEFAULT false;

-- 2. Grandfather all existing accounts (they signed up before the fee existed)
UPDATE profiles SET is_activated = true WHERE is_activated IS DISTINCT FROM true;

-- 3. Providers never pay the client activation fee — keep them activated
--    (covered by the grandfather update above; new providers are activated on signup
--    by the app, but this trigger guarantees it server-side)
CREATE OR REPLACE FUNCTION activate_providers()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.user_type = 'provider' THEN
    NEW.is_activated := true;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_activate_providers ON profiles;
CREATE TRIGGER trg_activate_providers
  BEFORE INSERT OR UPDATE OF user_type ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION activate_providers();
