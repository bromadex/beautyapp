-- Demo content: show the verified badge on two demo pros (Rudo Moyo and
-- Tendai Dube), like an admin approving their ID check. Matches only these
-- two @demo.beautap.app accounts; does nothing once they are deleted.
UPDATE profiles
   SET is_verified = true
 WHERE id IN (SELECT id FROM auth.users
               WHERE email IN ('demo-rudo@demo.beautap.app', 'demo-tendai@demo.beautap.app'))
   AND NOT coalesce(is_verified, false);
