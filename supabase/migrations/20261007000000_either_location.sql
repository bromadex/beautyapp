-- Clients can choose "Come to me" or "I'll go to them" unless the pro says
-- otherwise. Services made before this choice existed get "either"
-- (studio-only categories like massage stay at the pro's place).
ALTER TABLE services ALTER COLUMN location_mode SET DEFAULT 'either';
UPDATE services s SET location_mode = 'either'
 WHERE location_mode = 'client' AND created_at < '2026-09-29'
   AND NOT EXISTS (SELECT 1 FROM service_categories c WHERE c.id = s.category_id AND c.studio_only);
