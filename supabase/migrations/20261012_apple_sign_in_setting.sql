-- Apple sign-in button is hidden until an admin sets apple_sign_in = 'on'.
INSERT INTO app_settings (key, value) VALUES ('apple_sign_in', 'off') ON CONFLICT (key) DO NOTHING;

DROP POLICY IF EXISTS app_settings_read ON app_settings;
CREATE POLICY app_settings_read ON app_settings FOR SELECT
  USING (key IN ('beautap_ecocash_number', 'beautap_ecocash_name', 'apple_sign_in') OR public.is_admin());
GRANT SELECT ON app_settings TO anon;
