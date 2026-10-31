-- Order Management System (OMS)
-- PostgreSQL 14+
-- Run on a newly created database using psql or a PostgreSQL SQL editor.
-- Tables are created in foreign-key dependency order.

BEGIN;

-- 1. Customers
CREATE TABLE public.customers (
    id BIGINT PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    gender VARCHAR(10) CHECK (gender IN ('MALE', 'FEMALE', 'OTHER')),
    address TEXT,
    birthday DATE,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Products
CREATE TABLE public.products (
    id BIGINT PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    code VARCHAR(50) NOT NULL UNIQUE,
    price NUMERIC(15,2) NOT NULL CHECK (price >= 0),
    description TEXT,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Orders
CREATE TABLE public.orders (
    id BIGINT PRIMARY KEY,
    customer_id BIGINT NOT NULL,
    order_code VARCHAR(50) NOT NULL UNIQUE,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'CONFIRMED', 'PROCESSING', 'COMPLETED', 'CANCELLED')),
    total_amount NUMERIC(15,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    note TEXT,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id)
        REFERENCES public.customers(id) ON DELETE RESTRICT
);

-- 4. Order items
CREATE TABLE public.order_items (
    id BIGINT PRIMARY KEY,
    order_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(15,2) NOT NULL CHECK (unit_price >= 0),
    priority SMALLINT NOT NULL DEFAULT 3,
    subtotal NUMERIC(17,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_order_items_order FOREIGN KEY (order_id)
        REFERENCES public.orders(id) ON DELETE CASCADE,
    CONSTRAINT fk_order_items_product FOREIGN KEY (product_id)
        REFERENCES public.products(id) ON DELETE RESTRICT,
    CONSTRAINT uq_order_product UNIQUE (order_id, product_id)
);

-- 5. Inventories: each record represents an inventory input.
CREATE TABLE public.inventories (
    id BIGINT PRIMARY KEY,
    product_id BIGINT NOT NULL UNIQUE,
    quantity INTEGER NOT NULL CHECK (quantity >= 0),
    inputted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_inventories_product FOREIGN KEY (product_id)
        REFERENCES public.products(id) ON DELETE RESTRICT
);

-- Indexes for common filters and foreign-key joins.
-- UNIQUE(order_id, product_id) already indexes order_items.order_id.
CREATE INDEX idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX idx_orders_status ON public.orders(status);
CREATE INDEX idx_order_items_product_id ON public.order_items(product_id);
CREATE INDEX idx_inventories_product_id ON public.inventories(product_id);
CREATE INDEX idx_inventories_inputted_at ON public.inventories(inputted_at);

-- Automatically maintain updated_at for UPDATE operations.
CREATE FUNCTION public.oms_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_customers_updated_at
BEFORE UPDATE ON public.customers
FOR EACH ROW EXECUTE FUNCTION public.oms_set_updated_at();

CREATE TRIGGER trg_products_updated_at
BEFORE UPDATE ON public.products
FOR EACH ROW EXECUTE FUNCTION public.oms_set_updated_at();

CREATE TRIGGER trg_orders_updated_at
BEFORE UPDATE ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.oms_set_updated_at();

CREATE TRIGGER trg_order_items_updated_at
BEFORE UPDATE ON public.order_items
FOR EACH ROW EXECUTE FUNCTION public.oms_set_updated_at();

-- Recalculate order total whenever items are inserted, updated, or deleted.
CREATE FUNCTION public.oms_refresh_order_total()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' OR TG_OP = 'UPDATE' THEN
        UPDATE public.orders
           SET total_amount = COALESCE((
               SELECT SUM(subtotal) FROM public.order_items WHERE order_id = OLD.order_id
           ), 0)
         WHERE id = OLD.order_id;
    END IF;

    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.order_id IS DISTINCT FROM OLD.order_id) THEN
        UPDATE public.orders
           SET total_amount = COALESCE((
               SELECT SUM(subtotal) FROM public.order_items WHERE order_id = NEW.order_id
           ), 0)
         WHERE id = NEW.order_id;
    ELSIF TG_OP = 'UPDATE' THEN
        -- Already refreshed the same order above.
        NULL;
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_order_items_refresh_total
AFTER INSERT OR UPDATE OR DELETE ON public.order_items
FOR EACH ROW EXECUTE FUNCTION public.oms_refresh_order_total();

COMMIT;

-- Notes:
-- * This script is intended for a fresh database; rerunning it will raise table-exists errors.
-- * inventories.quantity tracks stock inputs only; it does not subtract sales or returns.
-- * order totals are automatically maintained by triggers. For highly concurrent writes to
--   the same order, perform item modifications in transactions with an appropriate order lock.
-- * Configure PostgREST permissions and RLS before exposing data over HTTP.
