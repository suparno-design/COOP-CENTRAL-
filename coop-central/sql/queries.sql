USE coop_central;

-- 1. Members with balances (view)
SELECT * FROM v_member_summary ORDER BY balance DESC;

-- 2. Total savings of active members
SELECT SUM(balance) AS total_savings, COUNT(*) AS active_members
  FROM v_member_summary WHERE status = 'Active';

-- 3. Transaction history of one member
SELECT t.txn_id, t.txn_date, t.txn_type, t.amount
  FROM savings_txn t JOIN savings_account a ON a.account_id = t.account_id
 WHERE a.member_id = 101 ORDER BY t.txn_date DESC;

-- 4. Monthly deposits vs withdrawals
SELECT DATE_FORMAT(txn_date,'%Y-%m') AS month,
       SUM(CASE WHEN txn_type='Deposit'    THEN amount ELSE 0 END) AS deposits,
       SUM(CASE WHEN txn_type='Withdrawal' THEN amount ELSE 0 END) AS withdrawals
  FROM savings_txn GROUP BY month ORDER BY month;

-- 5. Overdue loans
SELECT * FROM v_loan_details
 WHERE status = 'Overdue' OR (status = 'Active' AND due_date < CURDATE());

-- 6. Members who have never taken a loan
SELECT m.member_id, m.name FROM member m
 WHERE NOT EXISTS (SELECT 1 FROM loan l WHERE l.member_id = m.member_id);

-- 7. Members saving above the society average
SELECT name, balance FROM v_member_summary
 WHERE balance > (SELECT AVG(balance) FROM savings_account);

-- 8. Loan repayment progress
SELECT l.loan_id, m.name, l.principal, l.outstanding,
       ROUND((l.principal - l.outstanding) / l.principal * 100, 1) AS repaid_pct
  FROM loan l JOIN member m USING (member_id);

-- 9. Top 3 savers
SELECT name, balance FROM v_member_summary ORDER BY balance DESC LIMIT 3;

-- 10. Trigger demos (each should fail with a message)
-- INSERT INTO savings_txn (account_id, txn_type, amount) VALUES (1,'Withdrawal',999999);
-- INSERT INTO loan (member_id, principal, due_date) VALUES (103, 5000, '2027-12-01');
