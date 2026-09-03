-- ============================================================
-- BeauTap Migration: Features Batch
-- Service add-ons, packages, travel fees, cancellation policies,
-- client notes, disputes, review replies, buffer time,
-- business verification, service requests marketplace
-- Run in Supabase Dashboard → SQL Editor
-- ============================================================

-- ========== A. SERVICE ADD-ONS ==========
CREATE TABLE IF NOT EXISTS service_addons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id uuid NOT NULL REFERENCES services(id) ON DELETE CASCADE,
  provider_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  name text NOT NULL,
  price numeric(10,2) NOT NULL DEFAULT 0,
  duration_minutes int NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  sort_order int NOT NULL DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE service_addons ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can view active addons" ON service_addons FOR SELECT USING (true);
CREATE POLICY "Providers manage own addons" ON service_addons FOR INSERT WITH CHECK (auth.uid() = provider_id);
CREATE POLICY "Providers update own addons" ON service_addons FOR UPDATE USING (auth.uid() = provider_id);
CREATE POLICY "Providers delete own addons" ON service_addons FOR DELETE USING (auth.uid() = provider_id);
CREATE INDEX IF NOT EXISTS idx_addons_service ON service_addons(service_id);

-- Booking add-ons junction table
CREATE TABLE IF NOT EXISTS booking_addons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  addon_id uuid NOT NULL REFERENCES service_addons(id) ON DELETE CASCADE,
  addon_name text NOT NULL,
  addon_price numeric(10,2) NOT NULL DEFAULT 0,
  addon_duration int NOT NULL DEFAULT 0,
  UNIQUE(booking_id, addon_id)
);

ALTER TABLE booking_addons ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Booking participants view addons" ON booking_addons FOR SELECT USING (true);
CREATE POLICY "Clients insert booking addons" ON booking_addons FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM bookings WHERE id = booking_id AND client_id = auth.uid())
);

-- ========== B. SERVICE PACKAGES ==========
CREATE TABLE IF NOT EXISTS service_packages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  package_price numeric(10,2) NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE service_packages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can view packages" ON service_packages FOR SELECT USING (true);
CREATE POLICY "Providers manage own packages" ON service_packages FOR INSERT WITH CHECK (auth.uid() = provider_id);
CREATE POLICY "Providers update own packages" ON service_packages FOR UPDATE USING (auth.uid() = provider_id);
CREATE POLICY "Providers delete own packages" ON service_packages FOR DELETE USING (auth.uid() = provider_id);

CREATE TABLE IF NOT EXISTS package_services (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  package_id uuid NOT NULL REFERENCES service_packages(id) ON DELETE CASCADE,
  service_id uuid NOT NULL REFERENCES services(id) ON DELETE CASCADE,
  UNIQUE(package_id, service_id)
);

ALTER TABLE package_services ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can view package services" ON package_services FOR SELECT USING (true);
CREATE POLICY "Providers manage package services" ON package_services FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM service_packages WHERE id = package_id AND provider_id = auth.uid())
);
CREATE POLICY "Providers delete package services" ON package_services FOR DELETE USING (
  EXISTS (SELECT 1 FROM service_packages WHERE id = package_id AND provider_id = auth.uid())
);

-- Add package_id to bookings for package-based bookings
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS package_id uuid REFERENCES service_packages(id);
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS addons_total numeric(10,2) DEFAULT 0;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS travel_fee numeric(10,2) DEFAULT 0;

-- ========== C. TRAVEL FEES ==========
ALTER TABLE provider_profiles ADD COLUMN IF NOT EXISTS travel_fee_per_km numeric(10,2) DEFAULT 0;
ALTER TABLE provider_profiles ADD COLUMN IF NOT EXISTS free_travel_radius_km numeric(10,2) DEFAULT 5;
ALTER TABLE provider_profiles ADD COLUMN IF NOT EXISTS max_travel_fee numeric(10,2) DEFAULT 20;

-- ========== D. CANCELLATION & NO-SHOW POLICIES ==========
CREATE TABLE IF NOT EXISTS cancellation_policies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE UNIQUE,
  free_cancel_hours int NOT NULL DEFAULT 24,
  late_cancel_fee_percent int NOT NULL DEFAULT 50,
  no_show_fee_percent int NOT NULL DEFAULT 100,
  provider_cancel_allowed boolean NOT NULL DEFAULT true,
  policy_text text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE cancellation_policies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can view cancellation policies" ON cancellation_policies FOR SELECT USING (true);
CREATE POLICY "Providers manage own policy" ON cancellation_policies FOR INSERT WITH CHECK (auth.uid() = provider_id);
CREATE POLICY "Providers update own policy" ON cancellation_policies FOR UPDATE USING (auth.uid() = provider_id);

-- Add cancellation fields to bookings
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS cancelled_by text CHECK (cancelled_by IN ('client', 'provider'));
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS cancelled_at timestamptz;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS cancel_reason text;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS cancellation_fee numeric(10,2) DEFAULT 0;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS no_show_by text CHECK (no_show_by IN ('client', 'provider'));
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS no_show_at timestamptz;

-- ========== E. PROVIDER CLIENT NOTES ==========
CREATE TABLE IF NOT EXISTS client_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  client_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  booking_id uuid REFERENCES bookings(id) ON DELETE SET NULL,
  note text NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE client_notes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Providers view own client notes" ON client_notes FOR SELECT USING (auth.uid() = provider_id);
CREATE POLICY "Providers insert client notes" ON client_notes FOR INSERT WITH CHECK (auth.uid() = provider_id);
CREATE POLICY "Providers update client notes" ON client_notes FOR UPDATE USING (auth.uid() = provider_id);
CREATE POLICY "Providers delete client notes" ON client_notes FOR DELETE USING (auth.uid() = provider_id);
CREATE INDEX IF NOT EXISTS idx_client_notes_provider_client ON client_notes(provider_id, client_id);

-- ========== G. DISPUTES & REPORTING ==========
CREATE TABLE IF NOT EXISTS disputes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  reporter_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  reported_user_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  category text NOT NULL CHECK (category IN ('service_problem', 'payment_issue', 'no_show', 'misconduct', 'other')),
  description text NOT NULL,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'under_review', 'resolved', 'dismissed')),
  admin_notes text,
  resolution text,
  resolved_by uuid REFERENCES profiles(id),
  created_at timestamptz DEFAULT now(),
  resolved_at timestamptz
);

ALTER TABLE disputes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users view own disputes" ON disputes FOR SELECT USING (auth.uid() = reporter_id OR auth.uid() = reported_user_id);
CREATE POLICY "Admins view all disputes" ON disputes FOR SELECT USING (
  EXISTS (SELECT 1 FROM admins WHERE user_id = auth.uid())
);
CREATE POLICY "Users create disputes" ON disputes FOR INSERT WITH CHECK (auth.uid() = reporter_id);
CREATE POLICY "Admins update disputes" ON disputes FOR UPDATE USING (
  EXISTS (SELECT 1 FROM admins WHERE user_id = auth.uid())
);
CREATE INDEX IF NOT EXISTS idx_disputes_booking ON disputes(booking_id);
CREATE INDEX IF NOT EXISTS idx_disputes_status ON disputes(status);

-- ========== H. REVIEW REPLIES ==========
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS provider_reply text;
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS provider_reply_at timestamptz;

-- ========== I. BUFFER TIME ==========
ALTER TABLE provider_profiles ADD COLUMN IF NOT EXISTS buffer_minutes int DEFAULT 0;

-- ========== J. BUSINESS VERIFICATION ==========
CREATE TABLE IF NOT EXISTS business_verifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE UNIQUE,
  business_name text,
  registration_number text,
  document_url text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  admin_notes text,
  submitted_at timestamptz DEFAULT now(),
  reviewed_at timestamptz,
  reviewed_by uuid REFERENCES profiles(id)
);

ALTER TABLE business_verifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Providers view own business verification" ON business_verifications FOR SELECT USING (auth.uid() = provider_id);
CREATE POLICY "Admins view all business verifications" ON business_verifications FOR SELECT USING (
  EXISTS (SELECT 1 FROM admins WHERE user_id = auth.uid())
);
CREATE POLICY "Providers submit business verification" ON business_verifications FOR INSERT WITH CHECK (auth.uid() = provider_id);
CREATE POLICY "Providers update own pending verification" ON business_verifications FOR UPDATE USING (auth.uid() = provider_id AND status = 'pending');
CREATE POLICY "Admins update business verifications" ON business_verifications FOR UPDATE USING (
  EXISTS (SELECT 1 FROM admins WHERE user_id = auth.uid())
);

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_business_verified boolean DEFAULT false;

-- ========== 2. SERVICE REQUEST MARKETPLACE ==========
CREATE TABLE IF NOT EXISTS service_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  title text NOT NULL,
  description text,
  category_id uuid REFERENCES service_categories(id),
  preferred_date date,
  preferred_time time,
  location text NOT NULL,
  latitude numeric(9,6),
  longitude numeric(9,6),
  budget_min numeric(10,2),
  budget_max numeric(10,2),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'matched', 'booked', 'expired', 'cancelled')),
  expires_at timestamptz DEFAULT (now() + interval '7 days'),
  created_at timestamptz DEFAULT now()
);

ALTER TABLE service_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can view open requests" ON service_requests FOR SELECT USING (status = 'open' OR client_id = auth.uid());
CREATE POLICY "Clients create requests" ON service_requests FOR INSERT WITH CHECK (auth.uid() = client_id);
CREATE POLICY "Clients update own requests" ON service_requests FOR UPDATE USING (auth.uid() = client_id);
CREATE INDEX IF NOT EXISTS idx_service_requests_status ON service_requests(status);
CREATE INDEX IF NOT EXISTS idx_service_requests_category ON service_requests(category_id);
CREATE INDEX IF NOT EXISTS idx_service_requests_client ON service_requests(client_id);

CREATE TABLE IF NOT EXISTS service_request_quotes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES service_requests(id) ON DELETE CASCADE,
  provider_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  quoted_price numeric(10,2) NOT NULL,
  message text,
  estimated_duration int,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'expired')),
  created_at timestamptz DEFAULT now(),
  UNIQUE(request_id, provider_id)
);

ALTER TABLE service_request_quotes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Request owner views quotes" ON service_request_quotes FOR SELECT USING (
  EXISTS (SELECT 1 FROM service_requests WHERE id = request_id AND client_id = auth.uid())
  OR provider_id = auth.uid()
);
CREATE POLICY "Providers create quotes" ON service_request_quotes FOR INSERT WITH CHECK (auth.uid() = provider_id);
CREATE POLICY "Providers update own quotes" ON service_request_quotes FOR UPDATE USING (auth.uid() = provider_id);
CREATE INDEX IF NOT EXISTS idx_quotes_request ON service_request_quotes(request_id);
CREATE INDEX IF NOT EXISTS idx_quotes_provider ON service_request_quotes(provider_id);

-- ========== WHATSAPP CONTACT ==========
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS whatsapp_number text;
ALTER TABLE provider_profiles ADD COLUMN IF NOT EXISTS preferred_contact text DEFAULT 'in_app' CHECK (preferred_contact IN ('in_app', 'whatsapp', 'both'));

-- ========== CASH PAYMENTS ==========
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS payment_method text DEFAULT 'paynow' CHECK (payment_method IN ('paynow', 'cash', 'ecocash'));
