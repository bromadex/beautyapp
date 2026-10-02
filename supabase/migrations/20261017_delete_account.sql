-- Deleting an account (by the person, or by an admin). Everything about the
-- person goes, using the database's cascades so newer tables are covered too.
-- Payment records stay (with the person removed) so BeauTap's income history
-- and the books stay right.

ALTER TABLE payments ALTER COLUMN client_id DROP NOT NULL;
ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_client_id_fkey;
ALTER TABLE payments ADD CONSTRAINT payments_client_id_fkey
  FOREIGN KEY (client_id) REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_provider_id_fkey;
ALTER TABLE payments ADD CONSTRAINT payments_provider_id_fkey
  FOREIGN KEY (provider_id) REFERENCES profiles(id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public._delete_account(p_user uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE pros uuid[];
BEGIN
  PERFORM public._bypass();
  SELECT array_agg(DISTINCT provider_id) INTO pros FROM reviews WHERE client_id = p_user;
  UPDATE business_verifications SET reviewed_by = NULL WHERE reviewed_by = p_user;
  UPDATE disputes SET resolved_by = NULL WHERE resolved_by = p_user;
  UPDATE disputes SET reported_user_id = NULL WHERE reported_user_id = p_user;
  DELETE FROM reviews WHERE client_id = p_user OR provider_id = p_user;
  DELETE FROM auth.users WHERE id = p_user;   -- cascades to profiles and the rest
  -- Their reviews are gone, so recount the pros they reviewed.
  UPDATE provider_profiles pp
     SET average_rating = coalesce((SELECT round(avg(rating)::numeric, 1) FROM reviews r
                                     WHERE r.provider_id = pp.provider_id AND NOT coalesce(r.is_hidden, false)), 0),
         total_reviews = (SELECT count(*) FROM reviews r
                           WHERE r.provider_id = pp.provider_id AND NOT coalesce(r.is_hidden, false))
   WHERE pp.provider_id = ANY (coalesce(pros, '{}'));
END $$;
REVOKE ALL ON FUNCTION public._delete_account(uuid) FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.delete_user_account() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not signed in'; END IF;
  PERFORM public._delete_account(auth.uid());
END $$;
REVOKE ALL ON FUNCTION public.delete_user_account() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.delete_user_account() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_delete_user(target_user_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Only admins can do this'; END IF;
  IF target_user_id = auth.uid() THEN RAISE EXCEPTION 'You can''t delete your own account here'; END IF;
  IF EXISTS (SELECT 1 FROM admins WHERE user_id = target_user_id) THEN
    RAISE EXCEPTION 'Remove their admin access first';
  END IF;
  PERFORM public._delete_account(target_user_id);
END $$;
REVOKE ALL ON FUNCTION public.admin_delete_user(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_user(uuid) TO authenticated;

-- ID verification decision: updates the request and the profile together,
-- and tells the person either way.
CREATE OR REPLACE FUNCTION public.admin_review_verification(p_id uuid, p_approve boolean, p_note text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v verifications; note text := nullif(trim(coalesce(p_note, '')), '');
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Only admins can do this'; END IF;
  SELECT * INTO v FROM verifications WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Request not found'; END IF;
  IF v.status <> 'pending' THEN RAISE EXCEPTION 'This request was already reviewed'; END IF;
  IF NOT p_approve AND note IS NULL THEN RAISE EXCEPTION 'Say why, so they can fix it and try again'; END IF;

  UPDATE verifications SET status = CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
         admin_note = note, reviewed_at = now()
   WHERE id = p_id;
  IF p_approve THEN
    UPDATE profiles SET is_verified = true WHERE id = v.user_id;
  END IF;
  INSERT INTO notifications (user_id, type, title, body)
  VALUES (v.user_id, 'verification',
          CASE WHEN p_approve THEN 'You''re verified' ELSE 'ID check not approved' END,
          CASE WHEN p_approve THEN 'Your ID check passed. Clients now see the verified badge on your profile.'
               ELSE note || ' Please send new photos from Settings.' END);
END $$;
REVOKE ALL ON FUNCTION public.admin_review_verification(uuid, boolean, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_verification(uuid, boolean, text) TO authenticated;

-- So deleting a user from anywhere (including the Supabase dashboard) works:
-- their reviews go with them, and "who reviewed/resolved it" is just cleared.
ALTER TABLE reviews DROP CONSTRAINT IF EXISTS reviews_client_id_fkey;
ALTER TABLE reviews ADD CONSTRAINT reviews_client_id_fkey FOREIGN KEY (client_id) REFERENCES profiles(id) ON DELETE CASCADE;
ALTER TABLE reviews DROP CONSTRAINT IF EXISTS reviews_provider_id_fkey;
ALTER TABLE reviews ADD CONSTRAINT reviews_provider_id_fkey FOREIGN KEY (provider_id) REFERENCES profiles(id) ON DELETE CASCADE;
ALTER TABLE business_verifications DROP CONSTRAINT IF EXISTS business_verifications_reviewed_by_fkey;
ALTER TABLE business_verifications ADD CONSTRAINT business_verifications_reviewed_by_fkey
  FOREIGN KEY (reviewed_by) REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE disputes DROP CONSTRAINT IF EXISTS disputes_resolved_by_fkey;
ALTER TABLE disputes ADD CONSTRAINT disputes_resolved_by_fkey FOREIGN KEY (resolved_by) REFERENCES profiles(id) ON DELETE SET NULL;
