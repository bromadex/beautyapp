-- Crash and error reports from the app. The same error is grouped into one
-- row (by fingerprint) with a count, so admins see what's breaking most.

CREATE TABLE IF NOT EXISTS app_errors (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fingerprint text NOT NULL UNIQUE,
  message text NOT NULL,
  stack text,
  route text,
  platform text,
  app_version text,
  last_user_id uuid,
  count int NOT NULL DEFAULT 1,
  users_affected int NOT NULL DEFAULT 1,
  first_seen timestamptz NOT NULL DEFAULT now(),
  last_seen timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz
);
CREATE INDEX IF NOT EXISTS app_errors_last_seen ON app_errors (last_seen DESC);
ALTER TABLE app_errors ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS app_errors_admin ON app_errors;
CREATE POLICY app_errors_admin ON app_errors FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Who has hit each error, so "users affected" is right.
CREATE TABLE IF NOT EXISTS app_error_users (
  error_id uuid REFERENCES app_errors(id) ON DELETE CASCADE,
  user_key text,
  PRIMARY KEY (error_id, user_key)
);
ALTER TABLE app_error_users ENABLE ROW LEVEL SECURITY;

-- Rate limit per device/user: at most 30 reports an hour.
CREATE TABLE IF NOT EXISTS app_error_rate (
  user_key text PRIMARY KEY,
  window_start timestamptz NOT NULL DEFAULT now(),
  n int NOT NULL DEFAULT 0
);
ALTER TABLE app_error_rate ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.log_app_error(p_message text, p_stack text DEFAULT NULL, p_route text DEFAULT NULL,
                                                p_platform text DEFAULT NULL, p_app_version text DEFAULT NULL,
                                                p_device text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  msg text := left(coalesce(nullif(trim(p_message), ''), 'Unknown error'), 1000);
  stk text := left(p_stack, 6000);
  ukey text := coalesce(auth.uid()::text, 'device:' || left(coalesce(p_device, 'unknown'), 64));
  -- Same message (numbers stripped) at the same top app frame = same error.
  top_frame text := (SELECT l FROM regexp_split_to_table(coalesce(stk, ''), E'\n') l
                      WHERE l ~ 'package:beauty|lib/' LIMIT 1);
  fp text := md5(regexp_replace(left(msg, 200), '[0-9]+', '#', 'g') || '|' || coalesce(top_frame, left(coalesce(stk, ''), 200)));
  rid uuid;
  was_new boolean;
  was_resolved boolean;
  r app_error_rate;
BEGIN
  SELECT * INTO r FROM app_error_rate WHERE user_key = ukey;
  IF FOUND AND r.window_start > now() - interval '1 hour' AND r.n >= 30 THEN RETURN; END IF;
  INSERT INTO app_error_rate (user_key, window_start, n) VALUES (ukey, now(), 1)
  ON CONFLICT (user_key) DO UPDATE
    SET n = CASE WHEN app_error_rate.window_start > now() - interval '1 hour' THEN app_error_rate.n + 1 ELSE 1 END,
        window_start = CASE WHEN app_error_rate.window_start > now() - interval '1 hour' THEN app_error_rate.window_start ELSE now() END;

  SELECT id, resolved_at IS NOT NULL INTO rid, was_resolved FROM app_errors WHERE fingerprint = fp;
  was_new := rid IS NULL;
  IF was_new THEN
    INSERT INTO app_errors (fingerprint, message, stack, route, platform, app_version, last_user_id)
    VALUES (fp, msg, stk, left(p_route, 200), left(p_platform, 40), left(p_app_version, 40), auth.uid())
    ON CONFLICT (fingerprint) DO NOTHING
    RETURNING id INTO rid;
    IF rid IS NULL THEN SELECT id INTO rid FROM app_errors WHERE fingerprint = fp; was_new := false; END IF;
  ELSE
    UPDATE app_errors SET count = count + 1, last_seen = now(), stack = coalesce(stk, stack),
           route = coalesce(left(p_route, 200), route), platform = coalesce(left(p_platform, 40), platform),
           app_version = coalesce(left(p_app_version, 40), app_version),
           last_user_id = coalesce(auth.uid(), last_user_id), resolved_at = NULL
     WHERE id = rid;
  END IF;

  INSERT INTO app_error_users (error_id, user_key) VALUES (rid, ukey) ON CONFLICT DO NOTHING;
  IF FOUND AND NOT was_new THEN
    UPDATE app_errors SET users_affected = users_affected + 1 WHERE id = rid;
  END IF;

  -- Tell admins about brand-new errors, and ones that came back after being fixed.
  IF was_new OR was_resolved THEN
    INSERT INTO notifications (user_id, type, title, body)
    SELECT a.user_id, 'app_error',
           CASE WHEN was_new THEN 'New app error' ELSE 'An error came back' END,
           left(msg, 160) || coalesce(' · ' || left(p_route, 60), '')
      FROM admins a;
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.log_app_error(text, text, text, text, text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.log_app_error(text, text, text, text, text, text) TO anon, authenticated;

-- Keep the tables small: forget resolved errors after 60 days, rate rows after a day.
DO $$ BEGIN
  PERFORM cron.unschedule('beautap-app-errors-cleanup') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'beautap-app-errors-cleanup');
  PERFORM cron.schedule('beautap-app-errors-cleanup', '17 3 * * *', $c$
    DELETE FROM app_errors WHERE resolved_at < now() - interval '60 days';
    DELETE FROM app_errors WHERE last_seen < now() - interval '120 days';
    DELETE FROM app_error_rate WHERE window_start < now() - interval '1 day';
  $c$);
END $$;
