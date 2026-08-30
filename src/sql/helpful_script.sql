-- ######################################
-- Incase I want a running balance for bank:
-- ######################################
WITH bank_account AS (
    -- 1. Identify the Bank Account and its starting balance
    SELECT id, name, opening_balance
    FROM accounts
    WHERE account_type = 'mobile_money_cash'
),
ledger_entries AS (
    -- 2a. Inject the Opening Balance as the very first row
    SELECT
        NULL::UUID AS id,
        '1900-01-01'::DATE AS entry_date, -- Artificial date to force it to the top
        'Opening Balance' AS category,
        'Initial Cash Balance' AS description,
        CASE WHEN b.opening_balance >= 0 THEN b.opening_balance ELSE NULL END AS debit,
        CASE WHEN b.opening_balance < 0 THEN ABS(b.opening_balance) ELSE NULL END AS credit,
        b.opening_balance AS net_change
    FROM bank_account b

    UNION ALL

    -- 2b. Standard Transactions (Incomes & Expenses)
    SELECT 
        t.id,
        t.transaction_date AS entry_date,
        c.name AS category,
        COALESCE(m.full_name, ch.name, NULLIF(t.description, '')) AS description,
        CASE WHEN c.category_type = 'income' THEN t.amount ELSE NULL END AS debit,
        CASE WHEN c.category_type = 'expense' THEN t.amount ELSE NULL END AS credit,
        CASE WHEN c.category_type = 'income' THEN t.amount ELSE -t.amount END AS net_change
    FROM transactions t
    JOIN categories c ON c.id = t.category_id
    LEFT JOIN churches ch ON ch.id = t.church_id
    LEFT JOIN ministers m ON m.id = t.minister_id
    JOIN bank_account b ON t.account_id = b.id
    WHERE NOT t.is_voided

    UNION ALL

    -- 2c. Transfers IN (Money deposited into Bank -> Debit)
    SELECT 
        tr.id,
        tr.transfer_date AS entry_date,
        'Transfer In' AS category,
        NULLIF(tr.description, '') AS description,
        tr.amount AS debit,
        NULL AS credit,
        tr.amount AS net_change
    FROM transfers tr
    JOIN bank_account b ON tr.to_account_id = b.id
    WHERE NOT tr.is_voided

    UNION ALL

    -- 2d. Transfers OUT (Money withdrawn from Bank -> Credit)
    SELECT 
        tr.id,
        tr.transfer_date AS entry_date,
        'Transfer Out' AS category,
        NULLIF(tr.description, '') AS description,
        NULL AS debit,
        tr.amount AS credit,
        -tr.amount AS net_change
    FROM transfers tr
    JOIN bank_account b ON tr.from_account_id = b.id
    WHERE NOT tr.is_voided
)
-- 3. Calculate the Running Balance
SELECT 
    NULLIF(entry_date, '1900-01-01'::DATE) AS date, -- Hide the artificial date for clean presentation
    category,
    description,
    debit,
    credit,
    SUM(net_change) OVER (ORDER BY entry_date, id NULLS FIRST) AS running_balance
FROM ledger_entries
ORDER BY entry_date, id NULLS FIRST;

-- ######################################
-- Incase I want to see the account balances at a particular date
-- ######################################
WITH as_of AS (
    SELECT DATE '2026-06-30' AS cutoff   -- change this one line to check a different date
)
SELECT
    a.id                     AS account_id,
    a.name                   AS account_name,
    a.opening_balance
        + COALESCE(SUM(
            CASE
                WHEN c.category_type = 'income'  THEN t.amount
                WHEN c.category_type = 'expense' THEN -t.amount
                ELSE 0
            END
          ), 0)
        + COALESCE((
            SELECT SUM(tr_in.amount) FROM transfers tr_in, as_of
            WHERE tr_in.to_account_id = a.id
              AND NOT tr_in.is_voided
              AND tr_in.transfer_date <= as_of.cutoff
          ), 0)
        - COALESCE((
            SELECT SUM(tr_out.amount) FROM transfers tr_out, as_of
            WHERE tr_out.from_account_id = a.id
              AND NOT tr_out.is_voided
              AND tr_out.transfer_date <= as_of.cutoff
          ), 0)
        AS balance_as_of
FROM accounts a
CROSS JOIN as_of
LEFT JOIN transactions t
       ON t.account_id = a.id
      AND NOT t.is_voided
      AND t.transaction_date <= as_of.cutoff
LEFT JOIN categories c ON c.id = t.category_id
GROUP BY a.id, a.name, a.opening_balance
ORDER BY a.name;

-- ######################################
-- Incase I want to see changes that occured at a particular period
-- ######################################
SELECT
    al.table_name,
    al.action,
    -- al.record_id,
    al.changed_at,
    u.full_name AS changed_by,
    al.diff
FROM audit_log al
LEFT JOIN users u ON u.id = al.changed_by
WHERE al.table_name IN ('transactions', 'transfers')
  AND al.action IN ('INSERT', 'DELETE')
  AND al.changed_at > '2026-08-16'
  AND (
    (al.diff->>'transaction_date') BETWEEN '2026-01-01' AND '2026-06-30'
    OR (al.diff->>'transfer_date') BETWEEN '2026-01-01' AND '2026-06-30'
  )
ORDER BY al.changed_at;

-- ######################################
-- Audit log queries for any audits to be done.
-- ######################################
-- 1. Any UPDATEs to transactions or transfers since the first report was signed off
SELECT
    al.table_name,
    al.record_id,
    al.changed_at,
    u.full_name AS changed_by,
    al.diff->'old' AS before,
    al.diff->'new' AS after
FROM audit_log al
LEFT JOIN users u ON u.id = al.changed_by
WHERE al.table_name IN ('transactions', 'transfers')
  AND al.action = 'UPDATE'
  AND al.changed_at > '2026-08-16'
ORDER BY al.changed_at;

-- 2. Any brand-new transactions/transfers entered since then, dated within
--    the reporting period (Jan–Jun 2026) — covers the "voided one, re-entered
--    correctly" pattern, which shows up as an INSERT rather than an UPDATE
SELECT
    al.table_name,
    al.action,
    al.record_id,
    al.changed_at,
    u.full_name AS changed_by,
    al.diff
FROM audit_log al
LEFT JOIN users u ON u.id = al.changed_by
WHERE al.table_name IN ('transactions', 'transfers')
  AND al.action IN ('INSERT', 'DELETE')
  AND al.changed_at > '2026-08-16'
  AND (
    (al.diff->>'transaction_date') BETWEEN '2026-01-01' AND '2026-06-30'
    OR (al.diff->>'transfer_date') BETWEEN '2026-01-01' AND '2026-06-30'
  )
ORDER BY al.changed_at;