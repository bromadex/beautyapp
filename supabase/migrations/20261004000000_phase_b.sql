-- Phase B: clients pay pros directly. BeauTap never holds the pro's money.
-- Pros list the ways they accept payment; clients send money themselves
-- (EcoCash, InnBucks, OneMoney, bank) and tap "I've paid" with a
-- transaction ID or screenshot; the pro confirms whether it arrived.

-- 1. How each pro gets paid ------------------------------------------------
ALTER TABLE provider_profiles
  ADD COLUMN IF NOT EXISTS accepts_cash boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS ecocash_number text,
  ADD COLUMN IF NOT EXISTS ecocash_name text,
  ADD COLUMN IF NOT EXISTS ecocash_merchant text,
  ADD COLUMN IF NOT EXISTS innbucks_number text,
  ADD COLUMN IF NOT EXISTS onemoney_number text,
  ADD COLUMN IF NOT EXISTS bank_details text,
  ADD COLUMN IF NOT EXISTS pay_note text;

ALTER TABLE provider_profiles DROP CONSTRAINT IF EXISTS provider_pay_fields_chk;
ALTER TABLE provider_profiles ADD CONSTRAINT provider_pay_fields_chk CHECK (
      (ecocash_number IS NULL OR ecocash_number ~ '^0?7[0-9]{8}$')
  AND (innbucks_number IS NULL OR innbucks_number ~ '^0?7[0-9]{8}$')
  AND (onemoney_number IS NULL OR onemoney_number ~ '^0?7[0-9]{8}$')
  AND (ecocash_merchant IS NULL OR ecocash_merchant ~ '^[0-9]{3,10}$')
  AND (ecocash_name IS NULL OR length(ecocash_name) <= 60)
  AND (bank_details IS NULL OR length(bank_details) <= 300)
  AND (pay_note IS NULL OR length(pay_note) <= 200)
) NOT VALID;

-- True when the pro can receive money before the appointment.
CREATE OR REPLACE FUNCTION public._takes_transfers(p_provider uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((SELECT ecocash_number IS NOT NULL OR ecocash_merchant IS NOT NULL
                       OR innbucks_number IS NOT NULL OR onemoney_number IS NOT NULL
                       OR bank_details IS NOT NULL
                     FROM provider_profiles WHERE provider_id = p_provider), false);
$$;

-- No deposit can be asked for if the pro has nowhere to receive it.
CREATE OR REPLACE FUNCTION public._deposit_for(p_provider uuid, p_total numeric)
 RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT CASE WHEN public._takes_transfers(p_provider) THEN
    round(coalesce(p_total, 0) * coalesce(
      (SELECT deposit_percent FROM provider_profiles WHERE provider_id = p_provider), 0) / 100.0, 2)
  ELSE 0 END;
$function$;

-- 2. Payment method on a booking must be one the pro takes ------------------
ALTER TABLE bookings DROP CONSTRAINT IF EXISTS bookings_payment_method_check;
ALTER TABLE bookings ADD CONSTRAINT bookings_payment_method_check
  CHECK (payment_method IN ('paynow', 'cash', 'ecocash', 'innbucks', 'onemoney', 'bank'));
ALTER TABLE bookings ALTER COLUMN payment_method SET DEFAULT 'cash';

CREATE OR REPLACE FUNCTION public.bookings_pay_method_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE pp provider_profiles;
BEGIN
  IF public.is_privileged() OR NEW.source = 'manual' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND NEW.payment_method IS NOT DISTINCT FROM OLD.payment_method THEN RETURN NEW; END IF;
  SELECT * INTO pp FROM provider_profiles WHERE provider_id = NEW.provider_id;
  NEW.payment_method := coalesce(NEW.payment_method, 'cash');
  IF NOT (CASE NEW.payment_method
      WHEN 'cash'     THEN coalesce(pp.accepts_cash, true)
      WHEN 'ecocash'  THEN pp.ecocash_number IS NOT NULL OR pp.ecocash_merchant IS NOT NULL
      WHEN 'innbucks' THEN pp.innbucks_number IS NOT NULL
      WHEN 'onemoney' THEN pp.onemoney_number IS NOT NULL
      WHEN 'bank'     THEN pp.bank_details IS NOT NULL
      ELSE false END) THEN
    RAISE EXCEPTION 'This pro doesn''t take that payment method. Please pick another.';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS bookings_pay_method_guard ON bookings;
CREATE TRIGGER bookings_pay_method_guard BEFORE INSERT OR UPDATE OF payment_method ON bookings
  FOR EACH ROW EXECUTE FUNCTION public.bookings_pay_method_guard();

-- 3. "I've paid" claims ------------------------------------------------------
CREATE TABLE IF NOT EXISTS pro_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  client_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  provider_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('deposit', 'balance', 'full')),
  amount numeric(10,2) NOT NULL CHECK (amount > 0),
  method text NOT NULL CHECK (method IN ('ecocash', 'innbucks', 'onemoney', 'bank')),
  reference text CHECK (reference IS NULL OR length(reference) <= 60),
  proof_path text,
  status text NOT NULL DEFAULT 'claimed' CHECK (status IN ('claimed', 'confirmed', 'rejected')),
  created_at timestamptz NOT NULL DEFAULT now(),
  decided_at timestamptz,
  CHECK (reference IS NOT NULL OR proof_path IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS pro_payments_booking_idx ON pro_payments(booking_id, created_at DESC);
CREATE INDEX IF NOT EXISTS pro_payments_provider_idx ON pro_payments(provider_id) WHERE status = 'claimed';
CREATE UNIQUE INDEX IF NOT EXISTS pro_payments_one_open ON pro_payments(booking_id) WHERE status = 'claimed';

ALTER TABLE pro_payments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pro_payments_read ON pro_payments;
CREATE POLICY pro_payments_read ON pro_payments FOR SELECT
  USING (auth.uid() = client_id OR auth.uid() = provider_id OR public.is_admin());
-- Writes only through the functions below.

-- What the client still owes the pro, and for what.
CREATE OR REPLACE FUNCTION public._amount_due(b bookings, OUT kind text, OUT amount numeric)
LANGUAGE plpgsql STABLE AS $$
BEGIN
  IF b.status NOT IN ('pending', 'confirmed', 'completed') OR b.payment_status = 'paid' THEN
    RETURN;
  END IF;
  IF coalesce(b.deposit_amount, 0) > 0 AND NOT b.deposit_paid THEN
    IF b.status = 'completed' THEN
      kind := 'full'; amount := b.total_price;
    ELSE
      kind := 'deposit'; amount := b.deposit_amount;
    END IF;
  ELSIF b.deposit_paid THEN
    kind := 'balance'; amount := greatest(coalesce(b.total_price, 0) - coalesce(b.deposit_amount, 0), 0);
  ELSE
    kind := 'full'; amount := b.total_price;
  END IF;
  IF coalesce(amount, 0) <= 0 THEN kind := NULL; amount := NULL; END IF;
END $$;

CREATE OR REPLACE FUNCTION public.claim_pro_payment(
  p_booking uuid, p_method text, p_reference text DEFAULT NULL, p_proof_path text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  b bookings; pp provider_profiles; due record; new_id uuid; who text; ref text;
BEGIN
  SELECT * INTO b FROM bookings WHERE id = p_booking FOR UPDATE;
  IF NOT FOUND OR b.client_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Booking not found';
  END IF;
  SELECT * INTO due FROM public._amount_due(b);
  IF due.kind IS NULL THEN RAISE EXCEPTION 'There is nothing to pay on this booking'; END IF;
  IF EXISTS (SELECT 1 FROM pro_payments WHERE booking_id = b.id AND status = 'claimed') THEN
    RAISE EXCEPTION 'Your pro is still checking your last payment';
  END IF;
  IF (SELECT count(*) FROM pro_payments WHERE booking_id = b.id AND status = 'rejected') >= 5 THEN
    RAISE EXCEPTION 'Too many payment attempts. Please message your pro or report an issue.';
  END IF;

  ref := nullif(upper(regexp_replace(coalesce(p_reference, ''), '\s', '', 'g')), '');
  IF ref IS NULL AND nullif(p_proof_path, '') IS NULL THEN
    RAISE EXCEPTION 'Add the transaction ID or a screenshot';
  END IF;
  IF p_proof_path IS NOT NULL AND split_part(p_proof_path, '/', 1) <> auth.uid()::text THEN
    RAISE EXCEPTION 'Invalid screenshot';
  END IF;

  SELECT * INTO pp FROM provider_profiles WHERE provider_id = b.provider_id;
  IF NOT (CASE p_method
      WHEN 'ecocash'  THEN pp.ecocash_number IS NOT NULL OR pp.ecocash_merchant IS NOT NULL
      WHEN 'innbucks' THEN pp.innbucks_number IS NOT NULL
      WHEN 'onemoney' THEN pp.onemoney_number IS NOT NULL
      WHEN 'bank'     THEN pp.bank_details IS NOT NULL
      ELSE false END) THEN
    RAISE EXCEPTION 'This pro doesn''t take that payment method';
  END IF;

  INSERT INTO pro_payments (booking_id, client_id, provider_id, kind, amount, method, reference, proof_path)
  VALUES (b.id, b.client_id, b.provider_id, due.kind, due.amount, p_method, ref, nullif(p_proof_path, ''))
  RETURNING id INTO new_id;

  SELECT coalesce(nullif(trim(full_name), ''), 'A client') INTO who FROM profiles WHERE id = b.client_id;
  INSERT INTO notifications (user_id, type, title, body, reference_id)
  VALUES (b.provider_id, 'payment', 'Payment to check',
          who || ' says they sent you $' || trim(to_char(due.amount, 'FM999990.00')) || ' by '
          || CASE p_method WHEN 'ecocash' THEN 'EcoCash' WHEN 'innbucks' THEN 'InnBucks'
                           WHEN 'onemoney' THEN 'OneMoney' ELSE 'bank transfer' END
          || coalesce(' (ref ' || ref || ')', '') || '. Check and confirm.',
          b.id::text);
  RETURN new_id;
END $$;

CREATE OR REPLACE FUNCTION public.decide_pro_payment(p_payment uuid, p_received boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE p pro_payments; who text; amt text;
BEGIN
  SELECT * INTO p FROM pro_payments WHERE id = p_payment FOR UPDATE;
  IF NOT FOUND OR p.provider_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Payment not found';
  END IF;
  IF p.status <> 'claimed' THEN RAISE EXCEPTION 'This payment was already answered'; END IF;

  UPDATE pro_payments SET status = CASE WHEN p_received THEN 'confirmed' ELSE 'rejected' END,
                          decided_at = now()
   WHERE id = p.id;

  SELECT coalesce(nullif(trim(full_name), ''), 'Your pro') INTO who FROM profiles WHERE id = p.provider_id;
  amt := '$' || trim(to_char(p.amount, 'FM999990.00'));

  IF p_received THEN
    PERFORM public._bypass();
    IF p.kind = 'deposit' THEN
      UPDATE bookings SET deposit_paid = true, payment_method = p.method WHERE id = p.booking_id;
    ELSE
      UPDATE bookings SET payment_status = 'paid', payment_method = p.method,
                          deposit_paid = deposit_paid OR deposit_amount > 0
       WHERE id = p.booking_id;
    END IF;
    INSERT INTO notifications (user_id, type, title, body, reference_id)
    VALUES (p.client_id, 'payment', 'Payment received',
            who || ' confirmed your ' || amt || CASE WHEN p.kind = 'deposit' THEN ' deposit.' ELSE ' payment.' END,
            p.booking_id::text);
  ELSE
    INSERT INTO notifications (user_id, type, title, body, reference_id)
    VALUES (p.client_id, 'payment', 'Payment not received',
            who || ' hasn''t received your ' || amt || ' yet. Check the number and transaction ID, then try again or message them.',
            p.booking_id::text);
  END IF;
END $$;

REVOKE ALL ON FUNCTION public.claim_pro_payment(uuid, text, text, text) FROM public, anon;
REVOKE ALL ON FUNCTION public.decide_pro_payment(uuid, boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.claim_pro_payment(uuid, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decide_pro_payment(uuid, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public._amount_due(bookings) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public._takes_transfers(uuid) FROM public, anon, authenticated;

-- 4. Screenshots of payments (private) -----------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('payment-proofs', 'payment-proofs', false, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "payment proofs upload own" ON storage.objects;
CREATE POLICY "payment proofs upload own" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'payment-proofs' AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "payment proofs read" ON storage.objects;
CREATE POLICY "payment proofs read" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'payment-proofs' AND (
    (storage.foldername(name))[1] = auth.uid()::text
    OR EXISTS (SELECT 1 FROM public.pro_payments p
                WHERE p.proof_path = storage.objects.name AND p.provider_id = auth.uid())
    OR public.is_admin()));
