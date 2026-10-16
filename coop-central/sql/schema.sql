-- Co-op Central: Cooperative Society Membership & Savings Management System
-- Run in MySQL 8+:  mysql -u root -p < sql/schema.sql   (or open in Workbench and run all)

DROP DATABASE IF EXISTS coop_central;
CREATE DATABASE coop_central CHARACTER SET utf8mb4;
USE coop_central;

-- ---------- TABLES ----------
CREATE TABLE member (
  member_id  INT AUTO_INCREMENT PRIMARY KEY,
  name       VARCHAR(80)  NOT NULL,
  phone      CHAR(10)     NOT NULL UNIQUE,
  email      VARCHAR(100) UNIQUE,
  address    VARCHAR(200),
  join_date  DATE         NOT NULL DEFAULT (CURDATE()),
  status     ENUM('Active','Inactive') NOT NULL DEFAULT 'Active',
  CONSTRAINT chk_phone CHECK (phone REGEXP '^[0-9]{10}$')
) AUTO_INCREMENT = 101;

CREATE TABLE savings_account (
  account_id INT AUTO_INCREMENT PRIMARY KEY,
  member_id  INT NOT NULL UNIQUE,
  balance    DECIMAL(12,2) NOT NULL DEFAULT 0,
  opened_on  DATE NOT NULL DEFAULT (CURDATE()),
  CONSTRAINT fk_acc_member FOREIGN KEY (member_id) REFERENCES member(member_id) ON DELETE CASCADE,
  CONSTRAINT chk_balance CHECK (balance >= 0)
);

CREATE TABLE savings_txn (
  txn_id     INT AUTO_INCREMENT PRIMARY KEY,
  account_id INT NOT NULL,
  txn_type   ENUM('Deposit','Withdrawal') NOT NULL,
  amount     DECIMAL(12,2) NOT NULL,
  txn_date   DATE NOT NULL DEFAULT (CURDATE()),
  remarks    VARCHAR(120),
  CONSTRAINT fk_txn_acc FOREIGN KEY (account_id) REFERENCES savings_account(account_id),
  CONSTRAINT chk_txn_amt CHECK (amount > 0),
  INDEX idx_txn_date (txn_date)
);

CREATE TABLE loan (
  loan_id       INT AUTO_INCREMENT PRIMARY KEY,
  member_id     INT NOT NULL,
  principal     DECIMAL(12,2) NOT NULL,
  interest_rate DECIMAL(5,2)  NOT NULL DEFAULT 12.00,
  outstanding   DECIMAL(12,2) NOT NULL DEFAULT 0,
  issue_date    DATE NOT NULL DEFAULT (CURDATE()),
  due_date      DATE NOT NULL,
  status        ENUM('Active','Overdue','Closed') NOT NULL DEFAULT 'Active',
  CONSTRAINT fk_loan_member FOREIGN KEY (member_id) REFERENCES member(member_id),
  CONSTRAINT chk_principal CHECK (principal >= 1000),
  CONSTRAINT chk_rate CHECK (interest_rate BETWEEN 1 AND 36),
  CONSTRAINT chk_due CHECK (due_date > issue_date)
);

CREATE TABLE loan_repayment (
  repayment_id INT AUTO_INCREMENT PRIMARY KEY,
  loan_id      INT NOT NULL,
  amount       DECIMAL(12,2) NOT NULL,
  paid_on      DATE NOT NULL DEFAULT (CURDATE()),
  CONSTRAINT fk_rep_loan FOREIGN KEY (loan_id) REFERENCES loan(loan_id),
  CONSTRAINT chk_rep_amt CHECK (amount > 0)
);

-- ---------- TRIGGERS (business rules) ----------
DELIMITER $$

-- Every new member gets a savings account automatically
CREATE TRIGGER trg_member_account AFTER INSERT ON member
FOR EACH ROW BEGIN
  INSERT INTO savings_account (member_id) VALUES (NEW.member_id);
END$$

-- Block transactions on inactive members and overdrafts
CREATE TRIGGER trg_txn_before BEFORE INSERT ON savings_txn
FOR EACH ROW BEGIN
  DECLARE cur DECIMAL(12,2); DECLARE st VARCHAR(10);
  SELECT a.balance, m.status INTO cur, st
    FROM savings_account a JOIN member m ON m.member_id = a.member_id
   WHERE a.account_id = NEW.account_id FOR UPDATE;
  IF st = 'Inactive' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Member is inactive';
  END IF;
  IF NEW.txn_type = 'Withdrawal' AND NEW.amount > cur THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient balance for this withdrawal';
  END IF;
END$$

-- Keep balance in sync
CREATE TRIGGER trg_txn_after AFTER INSERT ON savings_txn
FOR EACH ROW BEGIN
  UPDATE savings_account
     SET balance = balance + IF(NEW.txn_type = 'Deposit', NEW.amount, -NEW.amount)
   WHERE account_id = NEW.account_id;
END$$

-- Loan rules: active member, one open loan, limit = 3x savings
CREATE TRIGGER trg_loan_before BEFORE INSERT ON loan
FOR EACH ROW BEGIN
  DECLARE bal DECIMAL(12,2); DECLARE st VARCHAR(10); DECLARE open_cnt INT;
  SELECT a.balance, m.status INTO bal, st
    FROM savings_account a JOIN member m ON m.member_id = a.member_id
   WHERE a.member_id = NEW.member_id;
  SELECT COUNT(*) INTO open_cnt FROM loan WHERE member_id = NEW.member_id AND status <> 'Closed';
  IF st = 'Inactive' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Inactive members cannot take loans';
  ELSEIF open_cnt > 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Member already has an open loan';
  ELSEIF NEW.principal > 3 * bal THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Loan exceeds 3x savings balance';
  END IF;
  SET NEW.outstanding = NEW.principal;
END$$

-- Repayment cannot exceed outstanding
CREATE TRIGGER trg_rep_before BEFORE INSERT ON loan_repayment
FOR EACH ROW BEGIN
  DECLARE out_amt DECIMAL(12,2);
  SELECT outstanding INTO out_amt FROM loan WHERE loan_id = NEW.loan_id FOR UPDATE;
  IF NEW.amount > out_amt THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Repayment exceeds outstanding amount';
  END IF;
END$$

-- Reduce outstanding, close loan at zero
CREATE TRIGGER trg_rep_after AFTER INSERT ON loan_repayment
FOR EACH ROW BEGIN
  UPDATE loan
     SET outstanding = outstanding - NEW.amount,
         status = IF(outstanding = 0, 'Closed', status)
   WHERE loan_id = NEW.loan_id;
END$$

DELIMITER ;

-- ---------- VIEWS ----------
CREATE VIEW v_member_summary AS
SELECT m.member_id, m.name, m.phone, m.join_date, m.status, a.account_id, a.balance
  FROM member m JOIN savings_account a ON a.member_id = m.member_id;

CREATE VIEW v_loan_details AS
SELECT l.loan_id, l.member_id, m.name, l.principal, l.interest_rate,
       l.outstanding, l.issue_date, l.due_date, l.status
  FROM loan l JOIN member m ON m.member_id = l.member_id;

-- ---------- SAMPLE DATA ----------
INSERT INTO member (name, phone, email, join_date) VALUES
 ('Ravi Kumar',   '9876500101', 'ravi@example.com',    '2024-02-10'),
 ('Lakshmi Devi', '9876500102', 'lakshmi@example.com', '2024-03-22'),
 ('Imran Sheikh', '9876500103', 'imran@example.com',   '2024-06-05'),
 ('Anita Reddy',  '9876500104', 'anita@example.com',   '2025-01-18'),
 ('Suresh Babu',  '9876500105', 'suresh@example.com',  '2025-04-02');

INSERT INTO savings_txn (account_id, txn_type, amount, txn_date) VALUES
 (1,'Deposit',12000,'2026-08-02'), (2,'Deposit',8000,'2026-08-05'),
 (3,'Deposit',15000,'2026-08-11'), (4,'Deposit',5000,'2026-09-01'),
 (1,'Withdrawal',2000,'2026-09-14'), (5,'Deposit',3000,'2026-09-20'),
 (2,'Deposit',4000,'2026-10-03');

INSERT INTO loan (member_id, principal, interest_rate, issue_date, due_date, status) VALUES
 (103, 20000, 12, '2026-04-01', '2027-03-01', 'Active'),
 (101, 10000, 12, '2026-03-30', '2026-09-30', 'Overdue');

INSERT INTO loan_repayment (loan_id, amount, paid_on) VALUES (1, 6000, '2026-09-01');

UPDATE member SET status = 'Inactive' WHERE member_id = 105;
