-- Fixes from a full test pass.

-- 1. Signed-out visitors couldn't read reviews: some older policies look at
--    the admins table directly, and anon had no access to it at all, so the
--    whole query failed. Row-level security still hides every row from
--    anon (the only read policy is for signed-in people seeing themselves).
GRANT SELECT ON public.admins TO anon;

-- 2. Unread shop messages: count what the other person wrote (messages,
--    offers, terms), not the automatic status notes, which also counted
--    notes about your own actions.
CREATE OR REPLACE FUNCTION public._order_unread(p_order uuid, p_user uuid) RETURNS int
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT count(*)::int FROM order_messages m
   WHERE m.order_id = p_order AND m.sender_id IS NOT NULL AND m.sender_id <> p_user
     AND m.created_at > coalesce((SELECT read_at FROM order_reads r WHERE r.order_id = p_order AND r.user_id = p_user), '-infinity');
$$;
REVOKE ALL ON FUNCTION public._order_unread(uuid, uuid) FROM public, anon, authenticated;

-- 3. Booking requests the pro never answered: once the time has passed,
--    close them and tell the client, instead of leaving "Accept" on a
--    request for last week. Called by send-reminders every 15 minutes.
CREATE OR REPLACE FUNCTION public.expire_past_requests() RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE b record; n int := 0;
BEGIN
  PERFORM set_config('beautap.bypass', 'on', true);
  FOR b IN SELECT id, client_id, provider_id FROM bookings
            WHERE status = 'pending' AND booking_time < now() LOOP
    UPDATE bookings SET status = 'cancelled', cancelled_by = 'system', cancelled_at = now(),
           cancel_reason = 'The pro didn''t reply before the booking time.'
     WHERE id = b.id;
    IF b.client_id IS NOT NULL THEN
      INSERT INTO notifications (user_id, type, title, body, reference_id)
      VALUES (b.client_id, 'booking', 'Your request wasn''t answered',
              'The pro didn''t reply in time, so this booking is closed. Nothing was charged. Pick another time or another pro.', b.id::text);
    END IF;
    n := n + 1;
  END LOOP;
  RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.expire_past_requests() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expire_past_requests() TO service_role;
