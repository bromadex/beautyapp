-- One call for the admin dashboard and analytics, worked out in the database
-- so the numbers are right and the screens stay fast.
--
-- BeauTap's income is what pros paid BeauTap (plans, featured, product packs
-- and boosts), taken from the payments ledger. Booking money goes straight
-- from client to pro, so it's shown separately as "booked through BeauTap".

CREATE OR REPLACE FUNCTION public.admin_stats() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  m0 timestamptz := date_trunc('month', now());
  m1 timestamptz := date_trunc('month', now()) - interval '1 month';
  fee_purposes text[] := ARRAY['subscription', 'activation', 'featured', 'product_pack', 'product_boost'];
  out jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Only admins can do this'; END IF;

  SELECT jsonb_build_object(
    'users', (SELECT jsonb_build_object(
        'total', count(*),
        'providers', count(*) FILTER (WHERE user_type = 'provider'),
        'clients', count(*) FILTER (WHERE user_type = 'client'),
        'verified_providers', count(*) FILTER (WHERE user_type = 'provider' AND is_verified),
        'new_this_month', count(*) FILTER (WHERE created_at >= m0),
        'new_last_month', count(*) FILTER (WHERE created_at >= m1 AND created_at < m0),
        'banned', count(*) FILTER (WHERE is_banned),
        'pros_findable', (SELECT count(*) FROM provider_profiles pp JOIN profiles p ON p.id = pp.provider_id
                           WHERE public.provider_has_location(pp.provider_id)
                             AND NOT coalesce(pp.is_hidden, false) AND NOT coalesce(p.is_banned, false)),
        'pros_no_location', (SELECT count(*) FROM provider_profiles pp
                              WHERE NOT public.provider_has_location(pp.provider_id)))
      FROM profiles),
    'bookings', (SELECT jsonb_build_object(
        'total', count(*),
        'this_month', count(*) FILTER (WHERE created_at >= m0),
        'last_month', count(*) FILTER (WHERE created_at >= m1 AND created_at < m0),
        'pending', count(*) FILTER (WHERE status = 'pending'),
        'confirmed', count(*) FILTER (WHERE status = 'confirmed'),
        'completed', count(*) FILTER (WHERE status = 'completed'),
        'cancelled', count(*) FILTER (WHERE status = 'cancelled'),
        'completed_value', coalesce(sum(coalesce(agreed_price, total_price)) FILTER (WHERE status = 'completed'), 0),
        'completed_value_this_month', coalesce(sum(coalesce(agreed_price, total_price))
                                         FILTER (WHERE status = 'completed' AND booking_time >= m0), 0))
      FROM bookings WHERE source = 'app'),
    'income', (SELECT jsonb_build_object(
        'total', coalesce(sum(amount), 0),
        'this_month', coalesce(sum(amount) FILTER (WHERE coalesce(paid_at, created_at) >= m0), 0),
        'last_month', coalesce(sum(amount) FILTER (WHERE coalesce(paid_at, created_at) >= m1
                                                    AND coalesce(paid_at, created_at) < m0), 0),
        'plans', coalesce(sum(amount) FILTER (WHERE purpose IN ('subscription', 'activation')), 0),
        'featured', coalesce(sum(amount) FILTER (WHERE purpose = 'featured'), 0),
        'products', coalesce(sum(amount) FILTER (WHERE purpose IN ('product_pack', 'product_boost')), 0),
        'paynow', coalesce(sum(amount) FILTER (WHERE coalesce(gateway, 'paynow') <> 'manual'), 0),
        'ecocash_manual', coalesce(sum(amount) FILTER (WHERE gateway = 'manual'), 0))
      FROM payments WHERE status = 'paid' AND purpose = ANY (fee_purposes)),
    'income_by_month', (SELECT coalesce(jsonb_agg(x ORDER BY x.month DESC), '[]'::jsonb) FROM (
        SELECT to_char(date_trunc('month', coalesce(paid_at, created_at)), 'YYYY-MM') AS month, sum(amount) AS amount
          FROM payments WHERE status = 'paid' AND purpose = ANY (fee_purposes)
         GROUP BY 1 ORDER BY 1 DESC LIMIT 6) x),
    'active_plans', (SELECT jsonb_build_object(
        'total', count(*),
        'salon', count(*) FILTER (WHERE plan = 'salon'))
      FROM subscriptions WHERE status = 'active' AND end_date >= current_date),
    'popular_services', (SELECT coalesce(jsonb_agg(x ORDER BY x.count DESC), '[]'::jsonb) FROM (
        SELECT coalesce(c.name, s.service_name) AS name, count(*) AS count
          FROM bookings b JOIN services s ON s.id = b.service_id
          LEFT JOIN service_categories c ON c.id = s.category_id
         WHERE b.source = 'app'
         GROUP BY 1 ORDER BY 2 DESC LIMIT 5) x),
    'top_providers', (SELECT coalesce(jsonb_agg(x ORDER BY x.rating DESC, x.reviews DESC), '[]'::jsonb) FROM (
        SELECT p.full_name AS name, pp.average_rating AS rating, pp.total_reviews AS reviews,
               (SELECT count(*) FROM bookings b WHERE b.provider_id = pp.provider_id AND b.status = 'completed') AS bookings
          FROM provider_profiles pp JOIN profiles p ON p.id = pp.provider_id
         WHERE pp.total_reviews > 0 AND NOT coalesce(p.is_banned, false)
         ORDER BY pp.average_rating DESC, pp.total_reviews DESC LIMIT 5) x),
    -- Things waiting for an admin, shown as badges on the dashboard.
    'todo', jsonb_build_object(
        'verifications', (SELECT count(*) FROM verifications WHERE status = 'pending'),
        'business', (SELECT count(*) FROM business_verifications WHERE status = 'pending'),
        'disputes', (SELECT count(*) FROM disputes WHERE status IN ('open', 'under_review')),
        'sexual_conduct', (SELECT count(*) FROM disputes WHERE status IN ('open', 'under_review') AND category = 'sexual_conduct'),
        'fees', (SELECT count(*) FROM fee_claims WHERE status = 'claimed'),
        'reported_reviews', (SELECT count(*) FROM review_reports WHERE status = 'open'),
        'flagged_services', (SELECT count(*) FROM services WHERE review_status = 'flagged'),
        'errors', (SELECT count(*) FROM app_errors WHERE resolved_at IS NULL))
  ) INTO out;
  RETURN out;
END $$;
REVOKE ALL ON FUNCTION public.admin_stats() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_stats() TO authenticated;

-- Admin cancels a booking: records why, and tells both the client and the pro.
CREATE OR REPLACE FUNCTION public.admin_cancel_booking(p_booking uuid, p_reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE b bookings; reason text := nullif(trim(coalesce(p_reason, '')), ''); paid boolean; msg text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Only admins can do this'; END IF;
  IF reason IS NULL THEN RAISE EXCEPTION 'Add a reason. Both people will see it.'; END IF;
  SELECT * INTO b FROM bookings WHERE id = p_booking FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Booking not found'; END IF;
  IF b.status NOT IN ('pending', 'confirmed') THEN
    RAISE EXCEPTION 'Only pending or confirmed bookings can be cancelled';
  END IF;
  UPDATE bookings SET status = 'cancelled', cancelled_by = 'system', cancelled_at = now(),
         cancel_reason = 'Cancelled by BeauTap: ' || reason
   WHERE id = p_booking;
  paid := b.payment_status = 'paid' OR coalesce(b.deposit_paid, false);
  msg := 'BeauTap cancelled this booking: ' || reason
         || CASE WHEN paid THEN '. Money already paid to the pro should be refunded to the client.' ELSE '' END;
  INSERT INTO notifications (user_id, type, title, body, reference_id)
  SELECT u, 'booking_status', 'Booking cancelled by BeauTap', msg, b.id::text
    FROM unnest(ARRAY[b.client_id, b.provider_id]) u WHERE u IS NOT NULL;
END $$;
REVOKE ALL ON FUNCTION public.admin_cancel_booking(uuid, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_cancel_booking(uuid, text) TO authenticated;
