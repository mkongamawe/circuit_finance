-- ============================================================
-- Seed data skeleton — normalized circuit finance schema
-- roles/currencies are already inserted by the schema file itself
-- (structural, not a judgment call). Everything below is a
-- skeleton for you to fill in with real circuit data.
-- ============================================================

-- ------------------------------------------------------------
-- accounts
-- ------------------------------------------------------------
INSERT INTO accounts (name, account_type, currency_id, opening_balance) VALUES
    ('Coop Bank', 'bank', (SELECT id FROM currencies WHERE code = 'KES'), 0),
    ('Petty cash / M-Pesa', 'mobile_money_cash', (SELECT id FROM currencies WHERE code = 'KES'), 0);

-- ------------------------------------------------------------
-- categories: parent categories
-- ------------------------------------------------------------
INSERT INTO categories (name, category_type) VALUES
    ('Offertory', 'income'),
    ('Assessment Received', 'income'),
    ('Assessment Paid', 'expense'),
    ('Stipend', 'expense'),
    ('Travel', 'expense'),
    ('Rent', 'expense'),
    ('Pension', 'expense'),
    ('Transaction Charges', 'expense'),
    ('Stationary', 'expense'),
    ('Entertainment', 'expense'),
    ('Airtime', 'expense'),
    ('Preacher Welfare', 'expense'),
    ('Bank Opening/Expense', 'expense'),
    ('Refund', 'expense')
    ('Fuel', 'expense'),
    ('Maintenance', 'expense')
    ('Loan', 'income');

-- subcategories of Offertory
INSERT INTO categories (name, category_type, parent_category_id)
SELECT 'Circuit Service Offertory', 'income', id
FROM categories WHERE name = 'Offertory' AND category_type = 'income';

INSERT INTO categories (name, category_type, parent_category_id)
SELECT 'Thanksgiving Service Offertory', 'income', id
FROM categories WHERE name = 'Offertory' AND category_type = 'income';

INSERT INTO categories (name, category_type, parent_category_id)
SELECT 'Special Service Offertory', 'income', id
FROM categories WHERE name = 'Offertory' AND category_type = 'income';

-- ------------------------------------------------------------
-- churches
-- ------------------------------------------------------------
-- INSERT INTO churches (name) VALUES
    ('Kilifi Church', true),
    ('Roka Church', true),
    ('Mtondia Church', true),
    ('Amani Church', false),
    ('St. Matthews', false),
    ('Ganze', false),
    ('Kaembeni Church', false);

-- ------------------------------------------------------------
-- ministers — full_name is now generated from name parts
-- ------------------------------------------------------------
-- INSERT INTO ministers (first_name, middle_name, surname, screen_name) VALUES
    ('Jackson', 'Kazungu','Karimiko', 'Min 1', true),
    ('Caren', NULL, 'Mwagwabi', 'Min 2', true),
    ('Harrison', NULL, 'Mramba', 'Min 3', true),
    ('Joseph', NULL, 'Mwarumba', 'Min 4', false),
    ('Bruce', 'Dominic', 'Kadungo', 'Bishop B', true),
    ('Joshua', NULL, 'Baraka', 'Bishop A', true);

-- ------------------------------------------------------------
-- church_assessment_targets, current year
-- ------------------------------------------------------------
INSERT INTO church_assessment_targets (church_id, year, target_amount)
SELECT id, 2026, 1500000
FROM churches WHERE name = 'Kilifi Church';

INSERT INTO church_assessment_targets (church_id, year, target_amount)
SELECT id, 2026, 36000
FROM churches WHERE name = 'Roka Church';

INSERT INTO church_assessment_targets (church_id, year, target_amount)
SELECT id, 2026, 36000
FROM churches WHERE name = 'Mtondia Church';

INSERT INTO church_assessment_targets (church_id, year, target_amount)
SELECT id, 2026, 10200
FROM churches WHERE name = 'Amani Church';

-- ------------------------------------------------------------
-- circuit_targets, current year
-- ------------------------------------------------------------
INSERT INTO circuit_targets (target_category_id, minister_id, year, target_amount)
SELECT c.id, m.id, 2026, 360000
FROM categories c, ministers m
WHERE c.name = 'Stipend' AND c.category_type = 'expense'
  AND m.full_name = 'Jackson Karimiko';

INSERT INTO circuit_targets (target_category_id, minister_id, year, target_amount)
SELECT c.id, m.id, 2026, 360000
FROM categories c, ministers m
WHERE c.name = 'Stipend' AND c.category_type = 'expense'
  AND m.full_name = 'Caren Mwagwabi';

INSERT INTO circuit_targets (target_category_id, minister_id, year, target_amount)
SELECT c.id, m.id, 2026, 240000
FROM categories c, ministers m
WHERE c.name = 'Travel' AND c.category_type = 'expense'
  AND m.full_name = 'Jackson Karimiko';

INSERT INTO circuit_targets (target_category_id, minister_id, year, target_amount)
SELECT c.id, m.id, 2026, 240000
FROM categories c, ministers m
WHERE c.name = 'Travel' AND c.category_type = 'expense'
  AND m.full_name = 'Caren Mwagwabi';

INSERT INTO circuit_targets (target_category_id, minister_id, year, target_amount)
SELECT c.id, m.id, 2026, 72000
FROM categories c, ministers m
WHERE c.name = 'Pension' AND c.category_type = 'expense'
  AND m.full_name = 'Jackson Karimiko';

INSERT INTO circuit_targets (target_category_id, minister_id, year, target_amount)
SELECT c.id, m.id, 2026, 72000
FROM categories c, ministers m
WHERE c.name = 'Pension' AND c.category_type = 'expense'
  AND m.full_name = 'Caren Mwagwabi';

INSERT INTO circuit_targets (target_category_id, minister_id, year, target_amount)
SELECT c.id, m.id, 2026, 174000
FROM categories c, ministers m
WHERE c.name = 'Rent' AND c.category_type = 'expense'
  AND m.full_name = 'Jackson Karimiko';

INSERT INTO circuit_targets (target_category_id, minister_id, year, target_amount)
SELECT c.id, m.id, 2026, 96000
FROM categories c, ministers m
WHERE c.name = 'Rent' AND c.category_type = 'expense'
  AND m.full_name = 'Caren Mwagwabi';

INSERT INTO circuit_targets (target_category_id, minister_id, year, target_amount)
SELECT c.id, NULL, 2026, 300000
FROM categories c
WHERE c.name = 'Assessment Paid' AND c.category_type = 'expense';

-- ------------------------------------------------------------
-- currencies
-- ------------------------------------------------------------
INSERT INTO currencies (code, name, symbol) VALUES
    ('KES', 'Kenyan Shilling', 'KSh');

-- ------------------------------------------------------------
-- roles
-- ------------------------------------------------------------
INSERT INTO roles (name, description) VALUES
    ('admin',     'Full access, including schema-level changes and voiding'),
    ('treasurer', 'Enters transactions and transfers, requests voids');
