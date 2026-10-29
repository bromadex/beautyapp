-- Cancelling Pro now drops a stylist to the Free plan instead of hiding them.
CREATE OR REPLACE FUNCTION public.cancel_my_subscription() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public._bypass();
  UPDATE subscriptions SET status = 'cancelled' WHERE provider_id = auth.uid();
END;
$$;
