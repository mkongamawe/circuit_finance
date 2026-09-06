-- ============================================================
-- Circuit finance database — normalized schema (v2)
-- Target: PostgreSQL 13+
--
-- Changes from the original schema.sql, following the same
-- philosophy applied in society_schema.sql:
--   - roles, currencies added as lookup tables; users.role and
--     accounts.currency now reference them by FK instead of
--     inline text/CHECK. account_type and category_type are
--     deliberately left as inline CHECKs, matching the same
--     judgment call made in society_schema.sql — two fixed,
--     unlikely-to-grow options don't need a lookup table.
--   - full_name split into first_name / middle_name / surname on
--     users and ministers. full_name kept as a GENERATED column
--     so every existing view/join that reads full_name still
--     works unchanged. Not applied to churches (an org name, not
--     a person's).
--   - Voided transactions/transfers no longer use an is_voided
--     flag. Voiding now inserts a mirrored, negative-amount
--     reversal row (voided_tx_id points back at the original).
--     See void_transaction() / void_transfer() near the bottom.
--   - void_requests added so NocoDB (which can't call a Postgres
--     function directly) can let a treasurer submit a void
--     request; the function itself gets run by whoever processes
--     requests, same pattern as society_schema.sql.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto; -- needed for gen_random_uuid()

-- ------------------------------------------------------------
-- roles: who's allowed to do what. A lookup table rather than a
-- CHECK list so a new role doesn't require a schema change.
-- ------------------------------------------------------------
CREATE TABLE roles (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name         TEXT NOT NULL UNIQUE,  -- 'Admin', 'Treasurer'
    description  TEXT
);

-- ------------------------------------------------------------
-- currencies: what an account's balance is denominated in.
-- ------------------------------------------------------------
CREATE TABLE currencies (
    id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code    TEXT NOT NULL UNIQUE,   -- ISO 4217, e.g. 'KES'
    name    TEXT NOT NULL,
    symbol  TEXT
);

-- ------------------------------------------------------------
-- helper: builds a display full_name from parts. A function
-- rather than inline concatenation because GENERATED columns
-- require an IMMUTABLE expression, and concat_ws/trim are not
-- considered immutable by Postgres.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION build_full_name(
    first_name  TEXT,
    middle_name TEXT,
    surname     TEXT
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT btrim(
        COALESCE(NULLIF(first_name,  ''), '') ||
        CASE WHEN NULLIF(middle_name, '') IS NOT NULL THEN ' ' || middle_name ELSE '' END ||
        CASE WHEN NULLIF(surname,     '') IS NOT NULL THEN ' ' || surname     ELSE '' END
    );
$$;

-- ------------------------------------------------------------
-- users: treasurers and admins who can log in
-- ------------------------------------------------------------
CREATE TABLE users (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    first_name  TEXT NOT NULL,
    middle_name TEXT,
    surname     TEXT NOT NULL,
    full_name   TEXT GENERATED ALWAYS AS (
        build_full_name(first_name, middle_name, surname)
    ) STORED,
    email       TEXT NOT NULL UNIQUE,
    role_id     UUID NOT NULL REFERENCES roles(id),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------
-- accounts: the physical places money sits (bank, petty cash/M-Pesa)
-- ------------------------------------------------------------
CREATE TABLE accounts (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name             TEXT NOT NULL UNIQUE,
    account_type     TEXT NOT NULL CHECK (account_type IN ('bank', 'mobile_money_cash')),
    currency_id      UUID NOT NULL REFERENCES currencies(id),
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
    is_restricted  BOOLEAN NOT NULL DEFAULT false,
    is_active      BOOLEAN NOT NULL DEFAULT true
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
-- churches: member churches of the circuit (org name, not split)
-- ------------------------------------------------------------
CREATE TABLE churches (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name       TEXT NOT NULL UNIQUE,
    is_active  BOOLEAN NOT NULL DEFAULT true
);

-- ------------------------------------------------------------
-- ministers: NOT tied to a single church — they can serve any
-- church, or the circuit as a whole. screen_name is unrelated to
-- the name split below — it's the reporting-facing alias used in
-- place of full_name, kept exactly as before.
-- ------------------------------------------------------------
CREATE TABLE ministers (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    first_name   TEXT NOT NULL,
    middle_name  TEXT,
    surname      TEXT NOT NULL,
    full_name    TEXT GENERATED ALWAYS AS (
        build_full_name(first_name, middle_name, surname)
    ) STORED,
    screen_name  TEXT NOT NULL,  -- shown on reports instead of full_name
    is_active    BOOLEAN NOT NULL DEFAULT true
);

-- ------------------------------------------------------------
-- transactions: every income/expense entry.
--
-- Voiding note: there is no is_voided flag. To void a transaction,
-- a second row is inserted with the same account/category/fund/
-- church/minister, the amount negated, and voided_tx_id pointing
-- back at the original (see void_transaction() near the bottom).
-- Direction still comes from the linked category's category_type —
-- negating the amount on the reversal row makes it cancel the
-- original exactly when summed, so every balance/ledger view can
-- do a plain SUM(), no per-row flag to check.
-- ------------------------------------------------------------
CREATE TABLE transactions (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id               UUID NOT NULL REFERENCES accounts(id),
    category_id              UUID NOT NULL REFERENCES categories(id),
    fund_id                  UUID REFERENCES funds(id),
    church_id                UUID REFERENCES churches(id),
    minister_id              UUID REFERENCES ministers(id),
    related_transaction_id   UUID REFERENCES transactions(id),  -- set for a charge tied to another transaction
    voided_tx_id             UUID REFERENCES transactions(id),  -- set on a reversal row; points at the transaction it cancels
    amount                   NUMERIC(14, 2) NOT NULL,
    transaction_date         DATE NOT NULL,
    description              TEXT,
    voided_reason            TEXT,   -- populated on the reversal row, explaining why
    entered_by               UUID NOT NULL REFERENCES users(id),
    updated_by                UUID REFERENCES users(id),
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_amount_sign CHECK (
        (voided_tx_id IS NULL AND amount > 0)        -- ordinary entries are always positive
        OR (voided_tx_id IS NOT NULL AND amount < 0) -- reversal entries are always negative
    )
);

CREATE INDEX idx_transactions_account   ON transactions(account_id);
CREATE INDEX idx_transactions_category  ON transactions(category_id);
CREATE INDEX idx_transactions_fund      ON transactions(fund_id);
CREATE INDEX idx_transactions_church    ON transactions(church_id);
CREATE INDEX idx_transactions_minister  ON transactions(minister_id);
CREATE INDEX idx_transactions_related   ON transactions(related_transaction_id);
CREATE INDEX idx_transactions_voided    ON transactions(voided_tx_id);
CREATE INDEX idx_transactions_date      ON transactions(transaction_date);

-- a transaction can only be voided once
CREATE UNIQUE INDEX idx_transactions_voided_once
    ON transactions(voided_tx_id)
    WHERE voided_tx_id IS NOT NULL;

-- ------------------------------------------------------------
-- transfers: money moving between the two accounts.
-- Same voiding pattern as transactions — see void_transfer().
-- ------------------------------------------------------------
CREATE TABLE transfers (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_account_id   UUID NOT NULL REFERENCES accounts(id),
    to_account_id     UUID NOT NULL REFERENCES accounts(id),
    voided_tx_id       UUID REFERENCES transfers(id),
    amount              NUMERIC(14, 2) NOT NULL,
    transfer_date        DATE NOT NULL,
    description             TEXT,
    voided_reason           TEXT,
    entered_by               UUID NOT NULL REFERENCES users(id),
    updated_by                 UUID REFERENCES users(id),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),

    CHECK (from_account_id <> to_account_id),
    CONSTRAINT chk_transfer_amount_sign CHECK (
        (voided_tx_id IS NULL AND amount > 0)
        OR (voided_tx_id IS NOT NULL AND amount < 0)
    )
);

CREATE INDEX idx_transfers_from   ON transfers(from_account_id);
CREATE INDEX idx_transfers_to     ON transfers(to_account_id);
CREATE INDEX idx_transfers_voided ON transfers(voided_tx_id);

CREATE UNIQUE INDEX idx_transfers_voided_once
    ON transfers(voided_tx_id)
    WHERE voided_tx_id IS NOT NULL;

-- ------------------------------------------------------------
-- void_requests: lets NocoDB-side treasurers request a void
-- without needing to call a Postgres function directly. A
-- treasurer submits a row here; void_transaction()/void_transfer()
-- actually performs the reversal once the request is processed.
-- ------------------------------------------------------------
CREATE TABLE void_requests (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id  UUID REFERENCES transactions(id),
    transfer_id     UUID REFERENCES transfers(id),
    reason          TEXT,
    requested_by    UUID NOT NULL REFERENCES users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed_at    TIMESTAMPTZ,
    reversal_tx_id  UUID REFERENCES transactions(id),
    reversal_tr_id  UUID REFERENCES transfers(id),

    CONSTRAINT chk_void_target CHECK (
        (transaction_id IS NOT NULL AND transfer_id IS NULL) OR
        (transaction_id IS NULL AND transfer_id IS NOT NULL)
    )
);

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
-- report_runs: a record of every generated report
-- (unchanged from the original schema — still tracks pdf_path
-- and one row per period, since the report pipeline does write
-- PDFs to disk)
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
-- circuit_targets: flexible targets by category, per year —
-- optionally tied to a specific minister, or circuit-wide when
-- minister_id is NULL.
-- ------------------------------------------------------------
CREATE TABLE circuit_targets (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_category_id  UUID NOT NULL REFERENCES categories(id),
    minister_id           UUID REFERENCES ministers(id),
    year                  INTEGER NOT NULL,
    target_amount          NUMERIC(14, 2) NOT NULL CHECK (target_amount > 0)
);

CREATE UNIQUE INDEX idx_circuit_targets_minister
    ON circuit_targets(target_category_id, minister_id, year) WHERE minister_id IS NOT NULL;
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
-- account_balances: current balance per account.
-- No is_voided filter needed — a voided transaction's negative
-- reversal row cancels it out under a plain SUM().
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW account_balances AS
SELECT
    a.id                    AS account_id,
    a.name                  AS account_name,
    a.opening_balance
        + COALESCE(SUM(
            CASE
                WHEN c.category_type = 'income'  THEN t.amount
                WHEN c.category_type = 'expense' THEN -t.amount
                ELSE 0
            END
          ), 0)
        + COALESCE((SELECT SUM(tr_in.amount)  FROM transfers tr_in  WHERE tr_in.to_account_id = a.id), 0)
        - COALESCE((SELECT SUM(tr_out.amount) FROM transfers tr_out WHERE tr_out.from_account_id = a.id), 0)
        AS current_balance
FROM accounts a
LEFT JOIN transactions t ON t.account_id = a.id
LEFT JOIN categories c   ON c.id = t.category_id
GROUP BY a.id, a.name, a.opening_balance;

-- ------------------------------------------------------------
-- general_ledger: one chronological, read-only view of everything.
-- is_voided/voided_reason booleans are gone; is_reversal + which
-- entry a row reverses (voids_entry_date) replace them.
-- category_type is preserved on reversal rows so reporting can
-- net income/expense correctly. fund_name added — the original
-- circuit general_ledger never joined funds, despite transactions
-- having a fund_id column.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW general_ledger AS
SELECT * FROM (
    SELECT
        t.id,
        t.transaction_date            AS entry_date,
        a.name                        AS account_name,
        c.name                        AS category_name,
        c.category_type               AS category_type,
        f.name                        AS fund_name,
        ch.name                       AS church_name,
        m.screen_name                 AS minister_name,
        CASE WHEN c.category_type = 'income' THEN t.amount ELSE -t.amount END AS signed_amount,
        t.description,
        u.full_name                   AS entered_by_name,
        (t.voided_tx_id IS NOT NULL)  AS is_reversal,
        vt.transaction_date           AS voids_entry_date,
        t.voided_reason,
        'transaction'                  AS entry_type
    FROM transactions t
    JOIN accounts a        ON a.id = t.account_id
    JOIN categories c      ON c.id = t.category_id
    LEFT JOIN funds f      ON f.id = t.fund_id
    LEFT JOIN churches ch  ON ch.id = t.church_id
    LEFT JOIN ministers m  ON m.id = t.minister_id
    JOIN users u           ON u.id = t.entered_by
    LEFT JOIN transactions vt ON vt.id = t.voided_tx_id

    UNION ALL

    SELECT
        tr.id,
        tr.transfer_date              AS entry_date,
        af.name || ' -> ' || ato.name AS account_name,
        'Transfer'                     AS category_name,
        'transfer'                     AS category_type,
        NULL                            AS fund_name,
        NULL                            AS church_name,
        NULL                            AS minister_name,
        tr.amount                      AS signed_amount,
        tr.description,
        u.full_name                    AS entered_by_name,
        (tr.voided_tx_id IS NOT NULL)  AS is_reversal,
        vtr.transfer_date              AS voids_entry_date,
        tr.voided_reason,
        'transfer'                      AS entry_type
    FROM transfers tr
    JOIN accounts af  ON af.id = tr.from_account_id
    JOIN accounts ato ON ato.id = tr.to_account_id
    JOIN users u      ON u.id = tr.entered_by
    LEFT JOIN transfers vtr ON vtr.id = tr.voided_tx_id
) combined
ORDER BY entry_date DESC;

-- ------------------------------------------------------------
-- void_transaction / void_transfer: the voiding mechanism itself.
-- Rather than trusting every caller to build the mirrored
-- reversal row correctly by hand, these functions do it: fetch
-- the original, copy its dimensions, negate the amount, and
-- stamp voided_tx_id. Guards against voiding a reversal row
-- itself, or voiding the same transaction twice (the partial
-- unique indexes above enforce the latter at the DB level too).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION void_transaction(
    p_transaction_id  UUID,
    p_entered_by       UUID,
    p_reason            TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_reversal_id  UUID;
    orig           RECORD;
BEGIN
    SELECT * INTO orig FROM transactions WHERE id = p_transaction_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Transaction % not found', p_transaction_id;
    END IF;

    IF orig.voided_tx_id IS NOT NULL THEN
        RAISE EXCEPTION 'Transaction % is itself a reversal entry and cannot be voided', p_transaction_id;
    END IF;

    IF EXISTS (SELECT 1 FROM transactions WHERE voided_tx_id = p_transaction_id) THEN
        RAISE EXCEPTION 'Transaction % has already been voided', p_transaction_id;
    END IF;

    INSERT INTO transactions (
        account_id, category_id, fund_id, church_id, minister_id, voided_tx_id,
        amount, transaction_date, description, voided_reason, entered_by
    )
    VALUES (
        orig.account_id, orig.category_id, orig.fund_id, orig.church_id, orig.minister_id, orig.id,
        -orig.amount, CURRENT_DATE, orig.description, p_reason, p_entered_by
    )
    RETURNING id INTO v_reversal_id;

    RETURN v_reversal_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION void_transfer(
    p_transfer_id  UUID,
    p_entered_by    UUID,
    p_reason         TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_reversal_id  UUID;
    orig           RECORD;
BEGIN
    SELECT * INTO orig FROM transfers WHERE id = p_transfer_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Transfer % not found', p_transfer_id;
    END IF;

    IF orig.voided_tx_id IS NOT NULL THEN
        RAISE EXCEPTION 'Transfer % is itself a reversal entry and cannot be voided', p_transfer_id;
    END IF;

    IF EXISTS (SELECT 1 FROM transfers WHERE voided_tx_id = p_transfer_id) THEN
        RAISE EXCEPTION 'Transfer % has already been voided', p_transfer_id;
    END IF;

    INSERT INTO transfers (
        from_account_id, to_account_id, voided_tx_id,
        amount, transfer_date, description, voided_reason, entered_by
    )
    VALUES (
        orig.from_account_id, orig.to_account_id, orig.id,
        -orig.amount, CURRENT_DATE, orig.description, p_reason, p_entered_by
    )
    RETURNING id INTO v_reversal_id;

    RETURN v_reversal_id;
END;
$$ LANGUAGE plpgsql;