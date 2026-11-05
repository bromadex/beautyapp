-- One inbox for shop messages: every order I'm in, newest message first,
-- with what I haven't read yet.

CREATE TABLE IF NOT EXISTS public.order_reads (
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  read_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (order_id, user_id)
);
ALTER TABLE public.order_reads ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS order_reads_own ON public.order_reads;
CREATE POLICY order_reads_own ON public.order_reads FOR SELECT TO authenticated USING (user_id = auth.uid());
REVOKE INSERT, UPDATE, DELETE ON public.order_reads FROM anon, authenticated;

-- Called when the order page is open.
CREATE OR REPLACE FUNCTION public.mark_order_read(p_order uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM orders WHERE id = p_order AND auth.uid() IN (buyer_id, seller_id)) THEN RETURN; END IF;
  INSERT INTO order_reads (order_id, user_id, read_at) VALUES (p_order, auth.uid(), now())
  ON CONFLICT (order_id, user_id) DO UPDATE SET read_at = now();
  -- The order's notifications are read too.
  UPDATE notifications SET is_read = true
   WHERE user_id = auth.uid() AND type = 'order' AND reference_id = p_order::text AND NOT coalesce(is_read, false);
END $$;
GRANT EXECUTE ON FUNCTION public.mark_order_read(uuid) TO authenticated;

-- Unread = messages from anyone but me (status notes included) since I last opened it.
CREATE OR REPLACE FUNCTION public._order_unread(p_order uuid, p_user uuid) RETURNS int
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT count(*)::int FROM order_messages m
   WHERE m.order_id = p_order AND m.sender_id IS DISTINCT FROM p_user
     AND m.created_at > coalesce((SELECT read_at FROM order_reads r WHERE r.order_id = p_order AND r.user_id = p_user), '-infinity');
$$;
REVOKE ALL ON FUNCTION public._order_unread(uuid, uuid) FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.order_inbox(p_limit int DEFAULT 100) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce(jsonb_agg(x ORDER BY x.last_at DESC), '[]'::jsonb) FROM (
    SELECT o.id, o.ref, o.status, o.total, o.buyer_offer, o.buyer_paid_at, o.terms, o.pref_get,
           (o.seller_id = auth.uid()) AS selling,
           op.full_name AS other_name, op.avatar_url AS other_avatar,
           (SELECT oi.image_url FROM order_items oi WHERE oi.order_id = o.id LIMIT 1) AS image,
           (SELECT oi.name FROM order_items oi WHERE oi.order_id = o.id LIMIT 1) AS item,
           (SELECT count(*) FROM order_items oi WHERE oi.order_id = o.id) AS items,
           lm.body AS last_body, lm.kind AS last_kind, (lm.sender_id = auth.uid()) AS last_mine,
           coalesce(lm.created_at, o.created_at) AS last_at,
           public._order_unread(o.id, auth.uid()) AS unread
      FROM orders o
      JOIN profiles op ON op.id = CASE WHEN o.seller_id = auth.uid() THEN o.buyer_id ELSE o.seller_id END
      LEFT JOIN LATERAL (SELECT body, kind, sender_id, created_at FROM order_messages m
                          WHERE m.order_id = o.id ORDER BY created_at DESC LIMIT 1) lm ON true
     WHERE auth.uid() IN (o.buyer_id, o.seller_id)
     ORDER BY coalesce(lm.created_at, o.created_at) DESC
     LIMIT least(greatest(coalesce(p_limit, 100), 1), 200)
  ) x;
$$;
GRANT EXECUTE ON FUNCTION public.order_inbox(int) TO authenticated;

-- Badge counts gain unread messages.
CREATE OR REPLACE FUNCTION public.my_order_counts() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'selling', (SELECT count(*) FROM orders WHERE seller_id = auth.uid()
                 AND (status = 'requested' OR (status = 'agreed' AND buyer_paid_at IS NOT NULL) OR status = 'paid')),
    'buying', (SELECT count(*) FROM orders WHERE buyer_id = auth.uid()
                AND (status = 'terms_sent' OR status = 'ready')),
    'unread', (SELECT coalesce(sum(public._order_unread(id, auth.uid())), 0) FROM orders
                WHERE auth.uid() IN (buyer_id, seller_id)));
$$;
GRANT EXECUTE ON FUNCTION public.my_order_counts() TO authenticated;
