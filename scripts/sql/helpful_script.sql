-- Incase I want a running balance for bank:
WITH bank_account AS (
    -- 1. Identify the Bank Account and its starting balance
    SELECT id, name, opening_balance
    FROM accounts
    WHERE account_type = 'bank'
),
ledger_entries AS (
    -- 2a. Inject the Opening Balance as the very first row
    SELECT
        NULL::UUID AS id,
        '1900-01-01'::DATE AS entry_date, -- Artificial date to force it to the top
        'Opening Balance' AS category,
        'Initial Bank Balance' AS description,
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