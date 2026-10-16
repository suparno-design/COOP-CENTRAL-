# Co-op Central
Cooperative Society Membership & Savings Management System (DBMS PBL Review 3)

Stack: Python Flask + MySQL 8 + Jinja templates.

## Folder structure
```
coop-central/
├── app.py              Flask routes
├── config.py           DB credentials (env vars or edit defaults)
├── requirements.txt
├── sql/
│   ├── schema.sql      tables, constraints, triggers, views, sample data
│   └── queries.sql     10 demo queries + trigger demos
├── templates/          base, dashboard, members, savings, loans
└── static/
    ├── css/style.css
    └── js/theme.js
```

## Run
1. Create the database: `mysql -u root -p < sql/schema.sql`
2. Set your MySQL password in `config.py` (or `DB_PASSWORD` env var)
3. `pip install -r requirements.txt`
4. `python app.py` then open http://127.0.0.1:5000

## Tables
member, savings_account, savings_txn, loan, loan_repayment (+ views v_member_summary, v_loan_details)

## Rules enforced by triggers
- New member automatically gets a savings account
- No withdrawal above balance; no transactions on inactive members
- Balance updates automatically after each transaction
- Loan: active member only, one open loan at a time, max 3x savings
- Repayment cannot exceed outstanding; loan closes at zero
