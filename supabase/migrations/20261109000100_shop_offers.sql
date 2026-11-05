-- Price negotiation: the buyer can offer a price; the seller's terms can
-- set any agreed total (e.g. a discount). The buyer still accepts the
-- terms, so the agreed price is what's on the order.

ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS buyer_offer numeric(10,2);
ALTER TABLE public.order_messages DROP CONSTRAINT IF EXISTS order_messages_kind_check;
ALTER TABLE public.order_messages ADD CONSTRAINT order_messages_kind_check CHECK (kind IN ('text', 'terms', 'status', 'offer'));

CREATE OR REPLACE FUNCTION public.offer_order_price(p_order uuid, p_amount numeric, p_note text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE o orders; note text := left(nullif(trim(coalesce(p_note, '')), ''), 300);
BEGIN
  SELECT * INTO o FROM orders WHERE id = p_order AND buyer_id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found'; END IF;
  IF o.status NOT IN ('requested', 'terms_sent') THEN RAISE EXCEPTION 'The price is already agreed'; END IF;
  IF p_amount IS NULL OR p_amount <= 0 OR p_amount > 100000 THEN RAISE EXCEPTION 'Enter the price you''d like to pay'; END IF;
  -- An offer replaces any terms the seller sent, so they answer the offer.
  UPDATE orders SET buyer_offer = round(p_amount, 2), status = 'requested', updated_at = now() WHERE id = o.id;
  INSERT INTO order_messages (order_id, sender_id, kind, body)
  VALUES (o.id, auth.uid(), 'offer', 'Offer: $' || trim_scale(round(p_amount, 2)) || coalesce(' · ' || note, ''));
  INSERT INTO notifications (user_id, type, title, body, reference_id)
  VALUES (o.seller_id, 'order', 'Order ' || o.ref || ': price offer',
          public._first(auth.uid()) || ' offered $' || trim_scale(round(p_amount, 2)) || ' (you asked $' || trim_scale(o.total)
          || '). Send terms with the price you agree on, or reply in the chat.', o.id::text);
END $$;
GRANT EXECUTE ON FUNCTION public.offer_order_price(uuid, numeric, text) TO authenticated;

-- Terms with an agreed total (the old version, without p_total, still works).
CREATE OR REPLACE FUNCTION public.send_order_terms(p_order uuid, p_get text, p_pay text, p_delivery_fee numeric,
                                                   p_details text, p_total numeric)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE o orders; fee numeric := greatest(0, least(coalesce(p_delivery_fee, 0), 100)); tot numeric;
BEGIN
  SELECT * INTO o FROM orders WHERE id = p_order AND seller_id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found'; END IF;
  IF o.status NOT IN ('requested', 'terms_sent') THEN RAISE EXCEPTION 'The terms are already agreed'; END IF;
  tot := CASE WHEN p_total IS NOT NULL AND p_total > 0 THEN round(p_total, 2) ELSE o.items_total + fee END;
  UPDATE orders SET status = 'terms_sent', terms_sent_at = now(), delivery_fee = fee, total = tot,
         terms = jsonb_build_object(
           'get', CASE WHEN p_get IN ('collect', 'deliver', 'post', 'appointment') THEN p_get ELSE o.pref_get END,
           'pay', CASE WHEN p_pay IN ('ecocash', 'innbucks', 'onemoney', 'bank', 'cash') THEN p_pay ELSE o.pref_pay END,
           'delivery_fee', fee, 'total', tot,
           'discount', greatest(0, o.items_total + fee - tot),
           'details', left(nullif(trim(coalesce(p_details, '')), ''), 500))
   WHERE id = o.id;
  INSERT INTO order_messages (order_id, sender_id, kind, body)
  VALUES (o.id, auth.uid(), 'terms', 'Terms: $' || trim_scale(tot) || coalesce(' · ' || nullif(trim(coalesce(p_details, '')), ''), ''));
  INSERT INTO notifications (user_id, type, title, body, reference_id)
  VALUES (o.buyer_id, 'order', 'Order ' || o.ref || ': terms to check',
          public._first(o.seller_id) || ' sent the terms: $' || trim_scale(tot) || ' in total. Accept them or reply in the chat.', o.id::text);
END $$;
GRANT EXECUTE ON FUNCTION public.send_order_terms(uuid, text, text, numeric, text, numeric) TO authenticated;
