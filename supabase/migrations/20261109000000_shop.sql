-- Phase 7: the shop. Pros list items; anyone (clients and pros) can buy,
-- but not their own items. Checkout sends an order request; buyer and
-- seller agree on payment and delivery in the order chat (the seller sends
-- a terms card, the buyer accepts it). Money goes straight to the seller:
-- BeauTap never holds it.

-- ---------------------------------------------------------------------
-- Products: more photos, a category and stock
-- ---------------------------------------------------------------------
ALTER TABLE products ADD COLUMN IF NOT EXISTS images text[] NOT NULL DEFAULT '{}';
ALTER TABLE products ADD COLUMN IF NOT EXISTS category text NOT NULL DEFAULT 'Other';
ALTER TABLE products ADD COLUMN IF NOT EXISTS in_stock boolean NOT NULL DEFAULT true;
ALTER TABLE products ADD COLUMN IF NOT EXISTS stock_qty int;
ALTER TABLE products DROP CONSTRAINT IF EXISTS products_description_check;
ALTER TABLE products DROP CONSTRAINT IF EXISTS products_description_len;
ALTER TABLE products ADD CONSTRAINT products_description_len CHECK (description IS NULL OR length(description) <= 1000);
ALTER TABLE products DROP CONSTRAINT IF EXISTS products_category_check;
ALTER TABLE products ADD CONSTRAINT products_category_check
  CHECK (category IN ('Hair', 'Wigs & extensions', 'Skin care', 'Nails', 'Makeup', 'Tools', 'Other'));
ALTER TABLE products DROP CONSTRAINT IF EXISTS products_images_max;
ALTER TABLE products ADD CONSTRAINT products_images_max CHECK (coalesce(array_length(images, 1), 0) <= 5);
ALTER TABLE products DROP CONSTRAINT IF EXISTS products_stock_qty_check;
ALTER TABLE products ADD CONSTRAINT products_stock_qty_check CHECK (stock_qty IS NULL OR stock_qty >= 0);
UPDATE products SET images = ARRAY[image_url] WHERE image_url IS NOT NULL AND images = '{}';

-- ---------------------------------------------------------------------
-- How each seller usually hands over and gets paid
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.shop_settings (
  provider_id uuid PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
  accepts_orders boolean NOT NULL DEFAULT true,
  can_collect boolean NOT NULL DEFAULT true,
  can_deliver boolean NOT NULL DEFAULT false,
  delivery_fee numeric(10,2) CHECK (delivery_fee IS NULL OR delivery_fee BETWEEN 0 AND 100),
  can_post boolean NOT NULL DEFAULT false,
  at_appointment boolean NOT NULL DEFAULT true,
  note text CHECK (note IS NULL OR length(note) <= 200),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.shop_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS shop_settings_read ON public.shop_settings;
CREATE POLICY shop_settings_read ON public.shop_settings FOR SELECT USING (true);
DROP POLICY IF EXISTS shop_settings_own ON public.shop_settings;
CREATE POLICY shop_settings_own ON public.shop_settings FOR ALL TO authenticated
  USING (provider_id = auth.uid()) WITH CHECK (provider_id = auth.uid());
GRANT SELECT ON public.shop_settings TO anon;

-- ---------------------------------------------------------------------
-- Orders
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ref text NOT NULL DEFAULT upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6)),
  buyer_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  seller_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'requested'
    CHECK (status IN ('requested', 'terms_sent', 'agreed', 'paid', 'ready', 'done', 'declined', 'cancelled')),
  items_total numeric(10,2) NOT NULL DEFAULT 0,
  delivery_fee numeric(10,2) NOT NULL DEFAULT 0,
  total numeric(10,2) NOT NULL DEFAULT 0,
  pref_get text,      -- collect | deliver | post | appointment
  pref_pay text,      -- ecocash | innbucks | onemoney | bank | cash
  buyer_note text CHECK (buyer_note IS NULL OR length(buyer_note) <= 300),
  terms jsonb,        -- {get, pay, delivery_fee, total, details}
  terms_sent_at timestamptz,
  agreed_at timestamptz,
  buyer_paid_at timestamptz,
  paid_at timestamptz,
  ready_at timestamptz,
  ready_note text,
  done_at timestamptz,
  cancelled_at timestamptz,
  cancelled_by text,
  cancel_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (buyer_id <> seller_id)
);
CREATE INDEX IF NOT EXISTS orders_buyer ON public.orders(buyer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS orders_seller ON public.orders(seller_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.order_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  product_id uuid REFERENCES products(id) ON DELETE SET NULL,
  name text NOT NULL,
  image_url text,
  price numeric(10,2) NOT NULL,
  qty int NOT NULL CHECK (qty BETWEEN 1 AND 50)
);

CREATE TABLE IF NOT EXISTS public.order_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  sender_id uuid REFERENCES profiles(id) ON DELETE SET NULL,  -- null: BeauTap (status notes)
  kind text NOT NULL DEFAULT 'text' CHECK (kind IN ('text', 'terms', 'status')),
  body text NOT NULL CHECK (length(body) BETWEEN 1 AND 1000),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS order_messages_order ON public.order_messages(order_id, created_at);

CREATE TABLE IF NOT EXISTS public.seller_ratings (
  order_id uuid PRIMARY KEY REFERENCES public.orders(id) ON DELETE CASCADE,
  seller_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  buyer_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  rating smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment text CHECK (comment IS NULL OR length(comment) <= 300),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS seller_ratings_seller ON public.seller_ratings(seller_id);

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seller_ratings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS orders_read ON public.orders;
CREATE POLICY orders_read ON public.orders FOR SELECT TO authenticated
  USING (buyer_id = auth.uid() OR seller_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS order_items_read ON public.order_items;
CREATE POLICY order_items_read ON public.order_items FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM orders o WHERE o.id = order_id
                  AND (o.buyer_id = auth.uid() OR o.seller_id = auth.uid() OR public.is_admin())));
DROP POLICY IF EXISTS order_messages_read ON public.order_messages;
CREATE POLICY order_messages_read ON public.order_messages FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM orders o WHERE o.id = order_id
                  AND (o.buyer_id = auth.uid() OR o.seller_id = auth.uid() OR public.is_admin())));
DROP POLICY IF EXISTS order_messages_send ON public.order_messages;
CREATE POLICY order_messages_send ON public.order_messages FOR INSERT TO authenticated
  WITH CHECK (sender_id = auth.uid() AND kind = 'text'
              AND EXISTS (SELECT 1 FROM orders o WHERE o.id = order_id
                           AND (o.buyer_id = auth.uid() OR o.seller_id = auth.uid())));
DROP POLICY IF EXISTS seller_ratings_read ON public.seller_ratings;
CREATE POLICY seller_ratings_read ON public.seller_ratings FOR SELECT USING (true);
GRANT SELECT ON public.seller_ratings TO anon;
-- Orders, items and ratings change only through the functions below.
REVOKE INSERT, UPDATE, DELETE ON public.orders, public.order_items, public.seller_ratings FROM anon, authenticated;

-- New messages notify the other person.
CREATE OR REPLACE FUNCTION public.order_message_notice() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE o orders; other uuid;
BEGIN
  IF NEW.kind <> 'text' THEN RETURN NEW; END IF;
  SELECT * INTO o FROM orders WHERE id = NEW.order_id;
  other := CASE WHEN NEW.sender_id = o.buyer_id THEN o.seller_id ELSE o.buyer_id END;
  INSERT INTO notifications (user_id, type, title, body, reference_id)
  VALUES (other, 'order', 'Order ' || o.ref || ': new message',
          coalesce((SELECT full_name FROM profiles WHERE id = NEW.sender_id), 'Someone') || ': ' || left(NEW.body, 120),
          o.id::text);
  UPDATE orders SET updated_at = now() WHERE id = o.id;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_order_message_notice ON public.order_messages;
CREATE TRIGGER trg_order_message_notice AFTER INSERT ON public.order_messages
  FOR EACH ROW EXECUTE FUNCTION public.order_message_notice();

-- A status note in the chat plus a notification for the other person.
CREATE OR REPLACE FUNCTION public._order_event(o orders, p_to uuid, p_title text, p_body text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO order_messages (order_id, sender_id, kind, body) VALUES (o.id, NULL, 'status', p_body);
  INSERT INTO notifications (user_id, type, title, body, reference_id)
  VALUES (p_to, 'order', 'Order ' || o.ref || ': ' || p_title, p_body, o.id::text);
  UPDATE orders SET updated_at = now() WHERE id = o.id;
END $$;
REVOKE ALL ON FUNCTION public._order_event(orders, uuid, text, text) FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION public._first(p_user uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT split_part(coalesce((SELECT full_name FROM profiles WHERE id = p_user), 'Someone'), ' ', 1);
$$;

-- Checkout: one order request per seller.
CREATE OR REPLACE FUNCTION public.place_order(p_seller uuid, p_items jsonb, p_get text, p_pay text, p_note text)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid uuid := auth.uid();
  oid uuid;
  it jsonb;
  pr products;
  q int;
  sum_ numeric := 0;
  st shop_settings;
BEGIN
  IF uid IS NULL OR coalesce((SELECT is_anonymous FROM auth.users WHERE id = uid), false) THEN
    RAISE EXCEPTION 'Create a free account to order';
  END IF;
  IF uid = p_seller THEN RAISE EXCEPTION 'You can''t buy your own items'; END IF;
  IF EXISTS (SELECT 1 FROM profiles WHERE id IN (uid, p_seller) AND is_banned) THEN
    RAISE EXCEPTION 'This shop isn''t available right now';
  END IF;
  SELECT * INTO st FROM shop_settings WHERE provider_id = p_seller;
  IF st.provider_id IS NOT NULL AND NOT st.accepts_orders THEN
    RAISE EXCEPTION 'This shop isn''t taking orders right now';
  END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN RAISE EXCEPTION 'Your cart is empty'; END IF;

  INSERT INTO orders (buyer_id, seller_id, pref_get, pref_pay, buyer_note)
  VALUES (uid, p_seller,
          CASE WHEN p_get IN ('collect', 'deliver', 'post', 'appointment') THEN p_get ELSE 'collect' END,
          CASE WHEN p_pay IN ('ecocash', 'innbucks', 'onemoney', 'bank', 'cash') THEN p_pay ELSE 'cash' END,
          left(nullif(trim(coalesce(p_note, '')), ''), 300))
  RETURNING id INTO oid;

  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    SELECT * INTO pr FROM products WHERE id = (it->>'product_id')::uuid;
    q := greatest(1, least(50, coalesce((it->>'qty')::int, 1)));
    IF pr.id IS NULL OR pr.provider_id <> p_seller OR NOT pr.is_active THEN
      RAISE EXCEPTION 'One of the items is no longer for sale';
    END IF;
    IF NOT pr.in_stock OR (pr.stock_qty IS NOT NULL AND pr.stock_qty < q) THEN
      RAISE EXCEPTION '% is out of stock%', pr.name,
        CASE WHEN pr.stock_qty IS NOT NULL AND pr.stock_qty > 0 THEN ' (only ' || pr.stock_qty || ' left)' ELSE '' END;
    END IF;
    IF pr.price IS NULL THEN RAISE EXCEPTION '% has no price yet. Message the seller.', pr.name; END IF;
    INSERT INTO order_items (order_id, product_id, name, image_url, price, qty)
    VALUES (oid, pr.id, pr.name, coalesce(pr.images[1], pr.image_url), pr.price, q);
    sum_ := sum_ + pr.price * q;
  END LOOP;

  UPDATE orders SET items_total = sum_, total = sum_ WHERE id = oid;
  PERFORM public._order_event((SELECT o FROM orders o WHERE id = oid), p_seller, 'new order',
    public._first(uid) || ' sent an order request for $' || trim_scale(sum_) || '. Reply with your terms: total, how to pay and how they get it.');
  RETURN oid;
END $$;
GRANT EXECUTE ON FUNCTION public.place_order(uuid, jsonb, text, text, text) TO authenticated;

-- Seller: the terms card (can be sent again until the buyer accepts).
CREATE OR REPLACE FUNCTION public.send_order_terms(p_order uuid, p_get text, p_pay text, p_delivery_fee numeric, p_details text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE o orders; fee numeric := greatest(0, least(coalesce(p_delivery_fee, 0), 100)); tot numeric;
BEGIN
  SELECT * INTO o FROM orders WHERE id = p_order AND seller_id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found'; END IF;
  IF o.status NOT IN ('requested', 'terms_sent') THEN RAISE EXCEPTION 'The terms are already agreed'; END IF;
  tot := o.items_total + fee;
  UPDATE orders SET status = 'terms_sent', terms_sent_at = now(), delivery_fee = fee, total = tot,
         terms = jsonb_build_object(
           'get', CASE WHEN p_get IN ('collect', 'deliver', 'post', 'appointment') THEN p_get ELSE o.pref_get END,
           'pay', CASE WHEN p_pay IN ('ecocash', 'innbucks', 'onemoney', 'bank', 'cash') THEN p_pay ELSE o.pref_pay END,
           'delivery_fee', fee, 'total', tot,
           'details', left(nullif(trim(coalesce(p_details, '')), ''), 500))
   WHERE id = o.id;
  INSERT INTO order_messages (order_id, sender_id, kind, body)
  VALUES (o.id, auth.uid(), 'terms', 'Terms: $' || trim_scale(tot) || coalesce(' · ' || nullif(trim(coalesce(p_details, '')), ''), ''));
  INSERT INTO notifications (user_id, type, title, body, reference_id)
  VALUES (o.buyer_id, 'order', 'Order ' || o.ref || ': terms to check',
          public._first(o.seller_id) || ' sent the terms: $' || trim_scale(tot) || ' in total. Accept them or reply in the chat.', o.id::text);
END $$;
GRANT EXECUTE ON FUNCTION public.send_order_terms(uuid, text, text, numeric, text) TO authenticated;

-- One function for the other steps, checked against who may do what.
--   accept   buyer   terms_sent -> agreed
--   paid     buyer   agreed: "I've paid" (buyer_paid_at)
--   received seller  agreed -> paid (stock goes down)
--   ready    seller  paid -> ready (p_note: where/when)
--   done     either  paid|ready -> done
--   decline  seller  requested|terms_sent -> declined
--   cancel   buyer   requested|terms_sent|agreed (not yet paid) -> cancelled
CREATE OR REPLACE FUNCTION public.order_step(p_order uuid, p_step text, p_note text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE o orders; uid uuid := auth.uid(); is_buyer boolean; is_seller boolean; it record;
        note text := left(nullif(trim(coalesce(p_note, '')), ''), 300);
BEGIN
  SELECT * INTO o FROM orders WHERE id = p_order FOR UPDATE;
  IF NOT FOUND OR uid NOT IN (o.buyer_id, o.seller_id) THEN RAISE EXCEPTION 'Order not found'; END IF;
  is_buyer := uid = o.buyer_id; is_seller := uid = o.seller_id;

  IF p_step = 'accept' AND is_buyer AND o.status = 'terms_sent' THEN
    UPDATE orders SET status = 'agreed', agreed_at = now() WHERE id = o.id;
    PERFORM public._order_event(o, o.seller_id, 'terms accepted',
      public._first(uid) || ' accepted the terms ($' || trim_scale(o.total) || ').');
  ELSIF p_step = 'paid' AND is_buyer AND o.status = 'agreed' THEN
    UPDATE orders SET buyer_paid_at = now() WHERE id = o.id;
    PERFORM public._order_event(o, o.seller_id, 'payment to check',
      public._first(uid) || ' says they paid $' || trim_scale(o.total) || '. Tap Received once it''s in.');
  ELSIF p_step = 'received' AND is_seller AND o.status = 'agreed' THEN
    UPDATE orders SET status = 'paid', paid_at = now() WHERE id = o.id;
    FOR it IN SELECT product_id, qty FROM order_items WHERE order_id = o.id AND product_id IS NOT NULL LOOP
      UPDATE products SET stock_qty = greatest(0, stock_qty - it.qty),
                          in_stock = CASE WHEN stock_qty IS NOT NULL AND stock_qty - it.qty <= 0 THEN false ELSE in_stock END
       WHERE id = it.product_id AND stock_qty IS NOT NULL;
    END LOOP;
    PERFORM public._order_event(o, o.buyer_id, 'payment received',
      public._first(uid) || ' received your payment. They''ll let you know when it''s ready.');
  ELSIF p_step = 'ready' AND is_seller AND o.status = 'paid' THEN
    UPDATE orders SET status = 'ready', ready_at = now(), ready_note = note WHERE id = o.id;
    PERFORM public._order_event(o, o.buyer_id,
      CASE WHEN coalesce(o.terms->>'get', o.pref_get) IN ('deliver', 'post') THEN 'on its way' ELSE 'ready to collect' END,
      CASE WHEN coalesce(o.terms->>'get', o.pref_get) IN ('deliver', 'post') THEN 'Your order is on its way.' ELSE 'Your order is ready to collect.' END
      || coalesce(' ' || note, ''));
  ELSIF p_step = 'done' AND o.status IN ('paid', 'ready') THEN
    UPDATE orders SET status = 'done', done_at = now() WHERE id = o.id;
    PERFORM public._order_event(o, CASE WHEN is_buyer THEN o.seller_id ELSE o.buyer_id END, 'complete',
      'Order complete. ' || CASE WHEN is_buyer THEN public._first(uid) || ' has their items.' ELSE 'Enjoy! You can rate the seller now.' END);
  ELSIF p_step = 'decline' AND is_seller AND o.status IN ('requested', 'terms_sent') THEN
    UPDATE orders SET status = 'declined', cancelled_at = now(), cancelled_by = 'seller', cancel_reason = note WHERE id = o.id;
    PERFORM public._order_event(o, o.buyer_id, 'declined',
      public._first(uid) || ' can''t take this order' || coalesce(': ' || note, '.'));
  ELSIF p_step = 'cancel' AND is_buyer AND o.status IN ('requested', 'terms_sent', 'agreed') THEN
    UPDATE orders SET status = 'cancelled', cancelled_at = now(), cancelled_by = 'buyer', cancel_reason = note WHERE id = o.id;
    PERFORM public._order_event(o, o.seller_id, 'cancelled',
      public._first(uid) || ' cancelled the order' || coalesce(': ' || note, '.'));
  ELSE
    RAISE EXCEPTION 'That can''t be done at this stage';
  END IF;
END $$;
GRANT EXECUTE ON FUNCTION public.order_step(uuid, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.rate_seller(p_order uuid, p_rating int, p_comment text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE o orders;
BEGIN
  SELECT * INTO o FROM orders WHERE id = p_order AND buyer_id = auth.uid() AND status = 'done';
  IF NOT FOUND THEN RAISE EXCEPTION 'You can rate a seller once the order is complete'; END IF;
  IF p_rating NOT BETWEEN 1 AND 5 THEN RAISE EXCEPTION 'Choose 1 to 5 stars'; END IF;
  INSERT INTO seller_ratings (order_id, seller_id, buyer_id, rating, comment)
  VALUES (o.id, o.seller_id, o.buyer_id, p_rating, left(nullif(trim(coalesce(p_comment, '')), ''), 300))
  ON CONFLICT (order_id) DO UPDATE SET rating = EXCLUDED.rating, comment = EXCLUDED.comment, created_at = now();
END $$;
GRANT EXECUTE ON FUNCTION public.rate_seller(uuid, int, text) TO authenticated;

-- ---------------------------------------------------------------------
-- The shop for everyone (signed out too)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seller_summary(p_seller uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'rating', (SELECT round(avg(rating)::numeric, 1) FROM seller_ratings WHERE seller_id = p_seller),
    'ratings', (SELECT count(*) FROM seller_ratings WHERE seller_id = p_seller),
    'sold', (SELECT count(*) FROM orders WHERE seller_id = p_seller AND status = 'done'),
    'since', (SELECT min(created_at) FROM products WHERE provider_id = p_seller));
$$;
GRANT EXECUTE ON FUNCTION public.seller_summary(uuid) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.shop_items(
  p_city text DEFAULT NULL, p_category text DEFAULT NULL, p_q text DEFAULT NULL,
  p_seller uuid DEFAULT NULL, p_sort text DEFAULT 'new', p_limit int DEFAULT 40, p_offset int DEFAULT 0)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce(jsonb_agg(x), '[]'::jsonb) FROM (
    SELECT pr.id, pr.name, pr.price, pr.description, pr.category, pr.in_stock, pr.stock_qty,
           CASE WHEN array_length(pr.images, 1) > 0 THEN to_jsonb(pr.images)
                WHEN pr.image_url IS NOT NULL THEN jsonb_build_array(pr.image_url) ELSE '[]'::jsonb END AS images,
           pr.created_at, coalesce(pr.boosted_until > now(), false) AS boosted,
           pr.provider_id AS seller_id, p.full_name AS seller_name, p.avatar_url AS seller_avatar,
           coalesce(p.is_verified, false) AS seller_verified, pp.area, c.name AS city,
           (SELECT round(avg(rating)::numeric, 1) FROM seller_ratings r WHERE r.seller_id = pr.provider_id) AS seller_rating,
           (SELECT count(*) FROM order_items oi JOIN orders o ON o.id = oi.order_id
             WHERE oi.product_id = pr.id AND o.status IN ('paid', 'ready', 'done')) AS sold
      FROM products pr
      JOIN profiles p ON p.id = pr.provider_id
      JOIN provider_profiles pp ON pp.provider_id = pr.provider_id
      LEFT JOIN cities c ON c.id = pp.city_id
     WHERE pr.is_active AND NOT coalesce(pp.is_hidden, false) AND NOT coalesce(p.is_banned, false)
       AND (p_seller IS NULL OR pr.provider_id = p_seller)
       AND (p_category IS NULL OR pr.category = p_category)
       AND (p_q IS NULL OR pr.name ILIKE '%' || p_q || '%' OR pr.description ILIKE '%' || p_q || '%'
            OR p.full_name ILIKE '%' || p_q || '%')
     ORDER BY (p_city IS NOT NULL AND c.name = p_city) DESC,
              CASE WHEN p_sort = 'price_low' THEN pr.price END ASC NULLS LAST,
              CASE WHEN p_sort = 'price_high' THEN pr.price END DESC NULLS LAST,
              CASE WHEN p_sort = 'popular' THEN (SELECT count(*) FROM order_items oi WHERE oi.product_id = pr.id) END DESC NULLS LAST,
              coalesce(pr.boosted_until > now(), false) DESC, pr.created_at DESC
     LIMIT least(greatest(coalesce(p_limit, 40), 1), 100) OFFSET greatest(coalesce(p_offset, 0), 0)
  ) x;
$$;
GRANT EXECUTE ON FUNCTION public.shop_items(text, text, text, uuid, text, int, int) TO anon, authenticated;

-- Badge counts: orders waiting for me (as seller and as buyer).
CREATE OR REPLACE FUNCTION public.my_order_counts() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'selling', (SELECT count(*) FROM orders WHERE seller_id = auth.uid()
                 AND (status = 'requested' OR (status = 'agreed' AND buyer_paid_at IS NOT NULL) OR status = 'paid')),
    'buying', (SELECT count(*) FROM orders WHERE buyer_id = auth.uid()
                AND (status = 'terms_sent' OR status = 'ready')));
$$;
GRANT EXECUTE ON FUNCTION public.my_order_counts() TO authenticated;

-- Live updates for the order page.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'order_messages') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.order_messages;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'orders') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
    END IF;
  END IF;
END $$;
