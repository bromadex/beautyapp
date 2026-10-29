-- Say who owes a refund when a paid booking is cancelled.
CREATE OR REPLACE FUNCTION public.cancel_booking(p_booking_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE b bookings; pol cancellation_policies; fee numeric := 0; by_client boolean;
BEGIN
  SELECT * INTO b FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND OR (auth.uid() IS DISTINCT FROM b.provider_id AND auth.uid() IS DISTINCT FROM b.client_id) THEN
    RAISE EXCEPTION 'Booking not found';
  END IF;
  IF b.status NOT IN ('pending', 'confirmed') THEN
    RAISE EXCEPTION 'This booking can no longer be cancelled';
  END IF;
  by_client := auth.uid() = b.client_id;

  IF by_client AND b.status = 'confirmed' THEN
    SELECT * INTO pol FROM cancellation_policies WHERE provider_id = b.provider_id;
    IF FOUND AND b.booking_time - now() < make_interval(hours => pol.free_cancel_hours) THEN
      fee := round(b.total_price * pol.late_cancel_fee_percent / 100.0, 2);
    END IF;
  END IF;

  PERFORM public._bypass();
  UPDATE bookings SET status = 'cancelled',
         cancelled_by = CASE WHEN by_client THEN 'client' ELSE 'provider' END,
         cancelled_at = now(), cancel_reason = nullif(trim(p_reason), ''),
         cancellation_fee = fee
   WHERE id = p_booking_id;

  INSERT INTO notifications (user_id, type, title, body, reference_id)
  VALUES (CASE WHEN by_client THEN b.provider_id ELSE b.client_id END, 'booking',
          'Booking Cancelled',
          CASE WHEN by_client THEN 'The client cancelled their booking.' ELSE 'Your pro cancelled the booking.' END
          || coalesce(' Reason: ' || rtrim(nullif(trim(p_reason), ''), '.') || '.', '')
          || CASE WHEN fee > 0 THEN format(' Late cancellation fee: $%s.', fee) ELSE '' END
          || CASE WHEN NOT by_client AND (b.payment_status = 'paid' OR b.deposit_paid)
                  THEN format(' They will refund the $%s you paid.',
                              CASE WHEN b.payment_status = 'paid' THEN b.total_price ELSE b.deposit_amount END)
                  WHEN by_client AND (b.payment_status = 'paid' OR b.deposit_paid)
                  THEN format(' They had paid you $%s. Agree any refund with them.',
                              CASE WHEN b.payment_status = 'paid' THEN b.total_price ELSE b.deposit_amount END)
                  ELSE '' END,
          p_booking_id::text);
  RETURN fee;
END;
$function$
;
