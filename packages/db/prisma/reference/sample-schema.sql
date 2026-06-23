-- ============================================================================
-- PTAS168 — Property Management — sample SQL schema (PostgreSQL 16)
-- ----------------------------------------------------------------------------
-- Hand-authored DDL transcribed from the ERD in prisma/schema.prisma.
-- This is a REFERENCE / sample artifact only — Prisma (@ptas/db) remains the
-- single owner of the real DB layer. Do not point migrations at this file.
--
-- ERD at a glance (── = has-many, ── │ = optional one-to-one):
--
--   building ──< floor ──< room ──< contract >── tenant
--                              │ ──< room_service >── service_fee
--                              │ ──< meter_reading
--                              │ ──< invoice ──< invoice_line_item
--                              │           └─── (snapshots tenant)
--                              │ ── telegram_link (1:1, optional)
--                              │ ──< bank_payment
--   user ──< notification
--   setting (k/v)            bank_notification_group (standalone)
-- ============================================================================

BEGIN;

-- Needed for gen_random_uuid().
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ── Enumerated types ────────────────────────────────────────────────────────
CREATE TYPE user_role              AS ENUM ('owner', 'manager', 'staff', 'viewer');
CREATE TYPE user_status            AS ENUM ('active', 'inactive');
CREATE TYPE auth_via               AS ENUM ('credentials', 'telegram');
CREATE TYPE tenant_status          AS ENUM ('active', 'inactive');
CREATE TYPE contract_status        AS ENUM ('active', 'terminated');
CREATE TYPE service_type           AS ENUM ('WATER', 'ELECTRICITY', 'FIXED');
CREATE TYPE invoice_status         AS ENUM ('progress', 'paid', 'cancelled');
CREATE TYPE invoice_payment_method AS ENUM ('Cash', 'QRTransfer');
CREATE TYPE line_item_type         AS ENUM ('RENT', 'WATER', 'ELECTRICITY', 'FIXED_SERVICE');
CREATE TYPE notification_type      AS ENUM ('OVERDUE_INVOICE', 'PAYMENT_RECEIVED', 'TENANT_ADDED', 'GENERIC');

-- ── Shared updated_at trigger ───────────────────────────────────────────────
-- Prisma's @updatedAt is application-side; in raw SQL we enforce it in the DB.
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ── Auth / users ────────────────────────────────────────────────────────────
CREATE TABLE users (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username          TEXT NOT NULL UNIQUE,
  password_hash     TEXT,
  full_name         TEXT NOT NULL,
  phone             TEXT,
  profile_image     TEXT,
  role              user_role   NOT NULL DEFAULT 'manager',
  status            user_status NOT NULL DEFAULT 'active',
  via               auth_via    NOT NULL DEFAULT 'credentials',
  -- Telegram fields: populated only on Telegram Mini App login.
  telegram_id       BIGINT UNIQUE,
  telegram_username TEXT,
  first_name        TEXT,
  last_name         TEXT,
  language_code     TEXT,
  is_premium        BOOLEAN NOT NULL DEFAULT false,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_login_at     TIMESTAMPTZ
);
CREATE INDEX idx_users_phone ON users (phone);
CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ── Property: building > floor > room ───────────────────────────────────────
CREATE TABLE buildings (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL,
  remark     TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_buildings_updated_at BEFORE UPDATE ON buildings
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE floors (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  building_id UUID NOT NULL REFERENCES buildings (id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  remark      TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_floors_building_id ON floors (building_id);
CREATE TRIGGER trg_floors_updated_at BEFORE UPDATE ON floors
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE rooms (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  floor_id           UUID NOT NULL REFERENCES floors (id)    ON DELETE CASCADE,
  building_id        UUID NOT NULL REFERENCES buildings (id) ON DELETE CASCADE,
  name               TEXT NOT NULL,
  size               TEXT,
  price_per_month    NUMERIC(12, 2) NOT NULL DEFAULT 0,
  active             BOOLEAN NOT NULL DEFAULT true,
  -- 'manual' (default) | 'auto' — how Start Bill pre-fills meter readings.
  meter_reading_mode TEXT NOT NULL DEFAULT 'manual',
  -- Asset inventory: [{ id, name, notes?, photoUrl?, addedAt }]
  assets             JSONB NOT NULL DEFAULT '[]',
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_rooms_floor_id    ON rooms (floor_id);
CREATE INDEX idx_rooms_building_id ON rooms (building_id);
CREATE TRIGGER trg_rooms_updated_at BEFORE UPDATE ON rooms
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ── Tenants & contracts ─────────────────────────────────────────────────────
CREATE TABLE tenants (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name  TEXT NOT NULL,
  phone      TEXT NOT NULL UNIQUE,
  photo_url  TEXT,
  -- Attached docs: [{ id, name, type, size, dataUrl, uploadedAt }]
  documents  JSONB NOT NULL DEFAULT '[]',
  status     tenant_status NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_tenants_updated_at BEFORE UPDATE ON tenants
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE contracts (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id            UUID NOT NULL REFERENCES rooms (id)   ON DELETE CASCADE,
  -- Restrict: a tenant with contracts cannot be hard-deleted.
  tenant_id          UUID NOT NULL REFERENCES tenants (id) ON DELETE RESTRICT,
  tenant_name        TEXT NOT NULL,            -- snapshot at contract time
  tenant_phone       TEXT NOT NULL,            -- snapshot at contract time
  start_date         DATE NOT NULL,
  end_date           DATE,
  base_rent          NUMERIC(12, 2) NOT NULL DEFAULT 0,
  security_deposit   NUMERIC(12, 2) NOT NULL DEFAULT 0,
  status             contract_status NOT NULL DEFAULT 'active',
  termination_reason TEXT,
  terminated_at      TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_contracts_room_id   ON contracts (room_id);
CREATE INDEX idx_contracts_tenant_id ON contracts (tenant_id);
CREATE INDEX idx_contracts_status    ON contracts (status);
CREATE TRIGGER trg_contracts_updated_at BEFORE UPDATE ON contracts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ── Services ────────────────────────────────────────────────────────────────
CREATE TABLE service_fees (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name         TEXT NOT NULL,
  icon         TEXT NOT NULL DEFAULT 'Box',
  service_type service_type NOT NULL DEFAULT 'FIXED',
  default_rate NUMERIC(12, 4) NOT NULL DEFAULT 0,
  unit         TEXT NOT NULL DEFAULT 'mo',
  active       BOOLEAN NOT NULL DEFAULT true,
  is_default   BOOLEAN NOT NULL DEFAULT false,  -- auto-enabled on new contracts
  deletable    BOOLEAN NOT NULL DEFAULT true,   -- system WATER/ELECTRICITY = false
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_service_fees_updated_at BEFORE UPDATE ON service_fees
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE room_services (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id        UUID NOT NULL REFERENCES rooms (id)        ON DELETE CASCADE,
  service_fee_id UUID NOT NULL REFERENCES service_fees (id) ON DELETE CASCADE,
  price_override NUMERIC(12, 4),
  active         BOOLEAN NOT NULL DEFAULT true,
  assigned_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (room_id, service_fee_id)
);
CREATE INDEX idx_room_services_room_id ON room_services (room_id);

-- ── Meter readings (one row per room/date/service_type) ─────────────────────
CREATE TABLE meter_readings (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id          UUID NOT NULL REFERENCES rooms (id) ON DELETE CASCADE,
  service_type     service_type NOT NULL,
  record_date      DATE NOT NULL,
  recorded_by_name TEXT NOT NULL,
  previous_reading NUMERIC(12, 3) NOT NULL,
  current_reading  NUMERIC(12, 3) NOT NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_meter_readings_lookup
  ON meter_readings (room_id, service_type, record_date);

-- ── Invoices ────────────────────────────────────────────────────────────────
CREATE TABLE invoices (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_number    TEXT NOT NULL UNIQUE,
  -- Restrict room delete while invoices exist; null the tenant link on delete.
  room_id           UUID NOT NULL REFERENCES rooms (id)   ON DELETE RESTRICT,
  tenant_id         UUID          REFERENCES tenants (id) ON DELETE SET NULL,
  -- Snapshots — preserved even if the room/tenant later changes.
  tenant_name       TEXT NOT NULL,
  tenant_phone      TEXT,
  room_name         TEXT NOT NULL,
  building_name     TEXT NOT NULL,
  floor_name        TEXT NOT NULL,
  bill_period_start DATE NOT NULL,
  bill_period_end   DATE NOT NULL,
  due_date          DATE NOT NULL,
  bill_days         INTEGER NOT NULL,
  days_in_month     INTEGER NOT NULL,
  status            invoice_status NOT NULL DEFAULT 'progress',
  base_rent         NUMERIC(12, 2) NOT NULL DEFAULT 0,
  security_deposit  NUMERIC(12, 2) NOT NULL DEFAULT 0,
  subtotal          NUMERIC(12, 2) NOT NULL DEFAULT 0,
  total_amount      NUMERIC(12, 2) NOT NULL DEFAULT 0,
  exchange_rate     NUMERIC(12, 2) NOT NULL DEFAULT 4000,
  khr_amount        NUMERIC(14, 2),
  payment_method    invoice_payment_method,
  paid_at           TIMESTAMPTZ,
  cancel_reason     TEXT,
  cancelled_at      TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_invoices_room_id     ON invoices (room_id);
CREATE INDEX idx_invoices_tenant_id   ON invoices (tenant_id);
CREATE INDEX idx_invoices_status      ON invoices (status);
CREATE INDEX idx_invoices_period      ON invoices (bill_period_start);
CREATE TRIGGER trg_invoices_updated_at BEFORE UPDATE ON invoices
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE invoice_line_items (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id       UUID NOT NULL REFERENCES invoices (id) ON DELETE CASCADE,
  line_item_type   line_item_type NOT NULL,
  description      TEXT NOT NULL,
  previous_reading NUMERIC(12, 3),
  current_reading  NUMERIC(12, 3),
  unit_price       NUMERIC(12, 4),
  amount           NUMERIC(12, 2) NOT NULL
);
CREATE INDEX idx_invoice_line_items_invoice_id ON invoice_line_items (invoice_id);

-- ── Notifications ────────────────────────────────────────────────────────────
CREATE TABLE notifications (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  type       notification_type NOT NULL,
  title      TEXT NOT NULL,
  body       TEXT NOT NULL,
  ref        TEXT,
  read       BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_notifications_user_read    ON notifications (user_id, read);
CREATE INDEX idx_notifications_user_created ON notifications (user_id, created_at);

-- ── Settings (key/value) ─────────────────────────────────────────────────────
CREATE TABLE settings (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_settings_updated_at BEFORE UPDATE ON settings
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ── Telegram & bank payments ─────────────────────────────────────────────────
CREATE TABLE bank_payments (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id        UUID REFERENCES rooms (id) ON DELETE SET NULL,  -- null until linked
  bank           TEXT NOT NULL,                                  -- 'ABA', 'ACLEDA', …
  amount         NUMERIC(14, 4) NOT NULL,
  currency       TEXT NOT NULL,                                  -- 'USD' | 'KHR'
  sender_name    TEXT,
  sender_account TEXT,
  transaction_id TEXT NOT NULL UNIQUE,                           -- dedupe key
  apv            TEXT,                                           -- ABA approval code
  paid_at        TIMESTAMPTZ NOT NULL,
  raw_text       TEXT NOT NULL,
  chat_id        TEXT,
  message_id     INTEGER,
  received_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_bank_payments_paid_at      ON bank_payments (paid_at);
CREATE INDEX idx_bank_payments_bank         ON bank_payments (bank);
CREATE INDEX idx_bank_payments_room_paid_at ON bank_payments (room_id, paid_at);

-- One chat ↔ one room (both sides unique).
CREATE TABLE telegram_links (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id    UUID NOT NULL UNIQUE REFERENCES rooms (id) ON DELETE CASCADE,
  chat_id    TEXT NOT NULL UNIQUE,
  chat_title TEXT,
  linked_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Property-wide chats where bank bots post confirmations (no room attribution).
CREATE TABLE bank_notification_groups (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chat_id    TEXT NOT NULL UNIQUE,
  chat_title TEXT,
  linked_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMIT;
