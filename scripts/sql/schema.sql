-- ============================================================
-- Circuit finance database — consolidated schema
-- Target: PostgreSQL 13+
-- Run this against a fresh database.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto; -- needed for gen_random_uuid()

-- ------------------------------------------------------------
-- users: treasurers and other people who can log in
-- ------------------------------------------------------------
CREATE TABLE users (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name   TEXT NOT NULL,
    email       TEXT NOT NULL UNIQUE,
    role        TEXT NOT NULL CHECK (role IN ('admin', 'treasurer', 'viewer')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------
-- accounts: the physical places money sits (bank, petty cash/M-Pesa)
-- ------------------------------------------------------------
CREATE TABLE accounts (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name             TEXT NOT NULL UNIQUE,
    account_type     TEXT NOT NULL CHECK (account_type IN ('bank', 'mobile_money_cash')),
    currency         TEXT NOT NULL DEFAULT 'KES',
    opening_balance  NUMERIC(14, 2) NOT NULL DEFAULT 0,
    is_active        BOOLEAN NOT NULL DEFAULT true
);

-- ------------------------------------------------------------
-- funds: what pool of money a transaction belongs to
-- ------------------------------------------------------------
CREATE TABLE funds (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name           TEXT NOT NULL UNIQUE,
    description    TEXT,
    is_restricted  BOOLEAN NOT NULL DEFAULT false
);

-- ------------------------------------------------------------
-- categories: the nature of a transaction (self-referencing for subcategories)
-- ------------------------------------------------------------
CREATE TABLE categories (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                 TEXT NOT NULL,
    category_type        TEXT NOT NULL CHECK (category_type IN ('income', 'expense')),
    parent_category_id   UUID REFERENCES categories(id) ON DELETE SET NULL,
    UNIQUE (name, category_type)
);

-- ------------------------------------------------------------
-- churches: member churches of the circuit
-- ------------------------------------------------------------
CREATE TABLE churches (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name       TEXT NOT NULL UNIQUE,
    is_active  BOOLEAN NOT NULL DEFAULT true
);

-- ------------------------------------------------------------
-- ministers: NOT tied to a single church — they can serve any church,
-- or the circuit as a whole
-- ------------------------------------------------------------
CREATE TABLE ministers (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name   TEXT NOT NULL,
    screen_name TEXT NOT NULL,
    is_active   BOOLEAN NOT NULL DEFAULT true
);

-- ------------------------------------------------------------
-- transactions: every income/expense entry
-- amount is always positive; direction comes from categories.category_type
-- ------------------------------------------------------------
CREATE TABLE transactions (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id               UUID NOT NULL REFERENCES accounts(id),
    category_id              UUID NOT NULL REFERENCES categories(id),
    fund_id                  UUID REFERENCES funds(id),
    church_id                UUID REFERENCES churches(id),      -- set when tied to a church (e.g. assessment received)
    minister_id              UUID REFERENCES ministers(id),     -- set when tied to a minister (e.g. stipend, pension)
    related_transaction_id   UUID REFERENCES transactions(id),  -- set for a charge tied to another transaction
    amount                   NUMERIC(14, 2) NOT NULL CHECK (amount > 0),
    transaction_date         DATE NOT NULL,
    description               TEXT,
    entered_by               UUID NOT NULL REFERENCES users(id),
    updated_by                UUID REFERENCES users(id),
    is_voided                BOOLEAN NOT NULL DEFAULT false,
    voided_reason             TEXT,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_transactions_account    ON transactions(account_id);
CREATE INDEX idx_transactions_category   ON transactions(category_id);
CREATE INDEX idx_transactions_fund       ON transactions(fund_id);
CREATE INDEX idx_transactions_church     ON transactions(church_id);
CREATE INDEX idx_transactions_minister   ON transactions(minister_id);
CREATE INDEX idx_transactions_related    ON transactions(related_transaction_id);
CREATE INDEX idx_transactions_date       ON transactions(transaction_date);

-- ------------------------------------------------------------
-- transfers: money moving between the two accounts
-- ------------------------------------------------------------
CREATE TABLE transfers (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_account_id  UUID NOT NULL REFERENCES accounts(id),
    to_account_id    UUID NOT NULL REFERENCES accounts(id),
    amount           NUMERIC(14, 2) NOT NULL CHECK (amount > 0),
    transfer_date    DATE NOT NULL,
    description      TEXT,
    entered_by       UUID NOT NULL REFERENCES users(id),
    updated_by       UUID REFERENCES users(id),
    is_voided        BOOLEAN NOT NULL DEFAULT false,
    voided_reason    TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (from_account_id <> to_account_id)
);

CREATE INDEX idx_transfers_from ON transfers(from_account_id);
CREATE INDEX idx_transfers_to   ON transfers(to_account_id);

-- ------------------------------------------------------------
-- audit_log: generic change history for any table
-- ------------------------------------------------------------
CREATE TABLE audit_log (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name   TEXT NOT NULL,
    record_id    UUID NOT NULL,
    action       TEXT NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
    changed_by   UUID REFERENCES users(id),
    changed_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    diff         JSONB
);

CREATE INDEX idx_audit_log_record ON audit_log(table_name, record_id);

-- ------------------------------------------------------------
-- report_runs: a record of every generated monthly report
-- ------------------------------------------------------------
CREATE TABLE report_runs (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    period_start   DATE NOT NULL,
    period_end     DATE NOT NULL,
    generated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    generated_by   UUID REFERENCES users(id),
    pdf_path       TEXT,
    UNIQUE (period_start, period_end)
);

-- ------------------------------------------------------------
-- church_assessment_targets: each church's assessment target, per year
-- ------------------------------------------------------------
CREATE TABLE church_assessment_targets (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id      UUID NOT NULL REFERENCES churches(id),
    year           INTEGER NOT NULL,
    target_amount  NUMERIC(14, 2) NOT NULL CHECK (target_amount > 0),
    UNIQUE (church_id, year)
);

-- ------------------------------------------------------------
-- circuit_targets: flexible targets by category, per year — optionally
-- tied to a specific minister (stipend/pension/rent), or circuit-wide
-- when minister_id is NULL (e.g. assessment paid to synod). New target
-- types (categories) can be added later without changing this table.
-- ------------------------------------------------------------
CREATE TABLE circuit_targets (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_category_id  UUID NOT NULL REFERENCES categories(id),
    minister_id          UUID REFERENCES ministers(id),
    year                 INTEGER NOT NULL,
    target_amount        NUMERIC(14, 2) NOT NULL CHECK (target_amount > 0)
);

-- one target per minister per category per year
CREATE UNIQUE INDEX idx_circuit_targets_minister
    ON circuit_targets(target_category_id, minister_id, year) WHERE minister_id IS NOT NULL;
-- one circuit-wide target per category per year
CREATE UNIQUE INDEX idx_circuit_targets_circuit_wide
    ON circuit_targets(target_category_id, year) WHERE minister_id IS NULL;

-- ------------------------------------------------------------
-- keep updated_at current on transaction edits
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_transactions_updated_at
    BEFORE UPDATE ON transactions
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

-- ------------------------------------------------------------
-- generic audit trigger: fires no matter which tool issues the SQL
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION log_audit_event()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, record_id, action, diff)
        VALUES (TG_TABLE_NAME, OLD.id, 'DELETE', to_jsonb(OLD));
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, record_id, action, changed_by, diff)
        VALUES (
            TG_TABLE_NAME, NEW.id, 'UPDATE', NEW.updated_by,
            jsonb_build_object('old', to_jsonb(OLD), 'new', to_jsonb(NEW))
        );
        RETURN NEW;
    ELSIF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (table_name, record_id, action, changed_by, diff)
        VALUES (TG_TABLE_NAME, NEW.id, 'INSERT', NEW.entered_by, to_jsonb(NEW));
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_transactions_audit
    AFTER INSERT OR UPDATE OR DELETE ON transactions
    FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER trg_transfers_audit
    AFTER INSERT OR UPDATE OR DELETE ON transfers
    FOR EACH ROW EXECUTE FUNCTION log_audit_event();

-- ------------------------------------------------------------
-- account_balances: current balance per account, excluding voided rows
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW account_balances AS
SELECT
    a.id                    AS account_id,
    a.name                  AS account_name,
    a.opening_balance
        + COALESCE(SUM(
            CASE
                WHEN t.is_voided THEN 0
                WHEN c.category_type = 'income'  THEN t.amount
                WHEN c.category_type = 'expense' THEN -t.amount
                ELSE 0
            END
          ), 0)
        + COALESCE((SELECT SUM(tr_in.amount)  FROM transfers tr_in  WHERE tr_in.to_account_id = a.id AND NOT tr_in.is_voided), 0)
        - COALESCE((SELECT SUM(tr_out.amount) FROM transfers tr_out WHERE tr_out.from_account_id = a.id AND NOT tr_out.is_voided), 0)
        AS current_balance
FROM accounts a
LEFT JOIN transactions t ON t.account_id = a.id
LEFT JOIN categories c   ON c.id = t.category_id
GROUP BY a.id, a.name, a.opening_balance;

-- ------------------------------------------------------------
-- general_ledger: one chronological, read-only view of everything
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW general_ledger AS
SELECT * FROM (
    SELECT
        t.id,
        t.transaction_date          AS entry_date,
        a.name                      AS account_name,
        c.name                      AS category_name,
        ch.name                     AS church_name,
        m.screen_name               AS minister_name,
        CASE WHEN c.category_type = 'income' THEN t.amount ELSE -t.amount END AS signed_amount,
        t.description,
        u.full_name                 AS entered_by_name,
        t.is_voided,
        t.voided_reason,
        'transaction'                AS entry_type
    FROM transactions t
    JOIN accounts a     ON a.id = t.account_id
    JOIN categories c   ON c.id = t.category_id
    LEFT JOIN churches ch  ON ch.id = t.church_id
    LEFT JOIN ministers m  ON m.id = t.minister_id
    JOIN users u        ON u.id = t.entered_by

    UNION ALL

    SELECT
        tr.id,
        tr.transfer_date            AS entry_date,
        af.name || ' -> ' || ato.name AS account_name,
        'Transfer'                   AS category_name,
        NULL                          AS church_name,
        NULL                          AS minister_name,
        tr.amount                    AS signed_amount,
        tr.description,
        u.full_name                  AS entered_by_name,
        tr.is_voided,
        tr.voided_reason,
        'transfer'                    AS entry_type
    FROM transfers tr
    JOIN accounts af  ON af.id = tr.from_account_id
    JOIN accounts ato ON ato.id = tr.to_account_id
    JOIN users u      ON u.id = tr.entered_by
) combined
ORDER BY entry_date DESC;
