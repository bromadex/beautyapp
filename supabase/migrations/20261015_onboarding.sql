-- Google/Apple sign-ups skip the sign-up form, so the app asks them a few
-- questions after their first sign-in (account type, phone, referral code).
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS needs_onboarding boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.handle_new_user() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER AS $function$
BEGIN
  INSERT INTO public.profiles (id, user_type, full_name, phone, location, needs_onboarding)
  VALUES (
    new.id,
    COALESCE((new.raw_user_meta_data->>'user_type')::text, 'client'),
    COALESCE((new.raw_user_meta_data->>'full_name')::text, (new.raw_user_meta_data->>'name')::text, 'User'),
    (new.raw_user_meta_data->>'phone')::text,
    (new.raw_user_meta_data->>'location')::text,
    COALESCE(new.raw_app_meta_data->>'provider', 'email') NOT IN ('email', 'phone')
  );
  RETURN new;
END;
$function$;
