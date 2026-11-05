-- One shop item with its seller, for the product page (signed out too).
-- Sellers also see their own hidden items.
CREATE OR REPLACE FUNCTION public.shop_item(p_id uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT to_jsonb(x) FROM (
    SELECT pr.id, pr.name, pr.price, pr.description, pr.category, pr.in_stock, pr.stock_qty, pr.is_active,
           CASE WHEN array_length(pr.images, 1) > 0 THEN to_jsonb(pr.images)
                WHEN pr.image_url IS NOT NULL THEN jsonb_build_array(pr.image_url) ELSE '[]'::jsonb END AS images,
           pr.created_at, coalesce(pr.boosted_until > now(), false) AS boosted,
           pr.provider_id AS seller_id, p.full_name AS seller_name, p.avatar_url AS seller_avatar,
           coalesce(p.is_verified, false) AS seller_verified, pp.area, c.name AS city,
           (SELECT round(avg(rating)::numeric, 1) FROM seller_ratings r WHERE r.seller_id = pr.provider_id) AS seller_rating,
           (SELECT count(*) FROM seller_ratings r WHERE r.seller_id = pr.provider_id) AS seller_ratings,
           (SELECT count(*) FROM orders o WHERE o.seller_id = pr.provider_id AND o.status = 'done') AS seller_sold,
           (SELECT count(*) FROM order_items oi JOIN orders o ON o.id = oi.order_id
             WHERE oi.product_id = pr.id AND o.status IN ('paid', 'ready', 'done')) AS sold,
           (SELECT to_jsonb(s) - 'provider_id' - 'updated_at' FROM shop_settings s WHERE s.provider_id = pr.provider_id) AS settings
      FROM products pr
      JOIN profiles p ON p.id = pr.provider_id
      JOIN provider_profiles pp ON pp.provider_id = pr.provider_id
      LEFT JOIN cities c ON c.id = pp.city_id
     WHERE pr.id = p_id
       AND ((pr.is_active AND NOT coalesce(pp.is_hidden, false) AND NOT coalesce(p.is_banned, false))
            OR pr.provider_id = auth.uid())
  ) x;
$$;
GRANT EXECUTE ON FUNCTION public.shop_item(uuid) TO anon, authenticated;

-- A seller's storefront header: who they are, their ratings and how they sell.
CREATE OR REPLACE FUNCTION public.shop_seller(p_seller uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'id', p.id, 'name', p.full_name, 'avatar', p.avatar_url, 'verified', coalesce(p.is_verified, false),
    'area', pp.area, 'city', c.name, 'bio', pp.bio,
    'rating', (SELECT round(avg(rating)::numeric, 1) FROM seller_ratings WHERE seller_id = p.id),
    'ratings', (SELECT count(*) FROM seller_ratings WHERE seller_id = p.id),
    'sold', (SELECT count(*) FROM orders WHERE seller_id = p.id AND status = 'done'),
    'settings', (SELECT to_jsonb(s) - 'provider_id' - 'updated_at' FROM shop_settings s WHERE s.provider_id = p.id),
    'reviews', (SELECT coalesce(jsonb_agg(r ORDER BY r.created_at DESC), '[]'::jsonb) FROM (
                  SELECT sr.rating, sr.comment, sr.created_at, split_part(coalesce(b.full_name, ''), ' ', 1) AS buyer
                    FROM seller_ratings sr JOIN profiles b ON b.id = sr.buyer_id
                   WHERE sr.seller_id = p.id ORDER BY sr.created_at DESC LIMIT 10) r))
    FROM profiles p
    JOIN provider_profiles pp ON pp.provider_id = p.id
    LEFT JOIN cities c ON c.id = pp.city_id
   WHERE p.id = p_seller AND NOT coalesce(p.is_banned, false);
$$;
GRANT EXECUTE ON FUNCTION public.shop_seller(uuid) TO anon, authenticated;
