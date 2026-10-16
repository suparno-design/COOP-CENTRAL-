import mysql.connector
from flask import Flask, render_template, request, redirect, url_for, flash
import config

app = Flask(__name__)
app.secret_key = config.SECRET_KEY


def db():
    return mysql.connector.connect(**config.DB)


def query(sql, params=(), write=False):
    """Run one statement. Returns rows (dicts) for SELECT, None for writes."""
    conn = db()
    try:
        cur = conn.cursor(dictionary=True)
        cur.execute(sql, params)
        if write:
            conn.commit()
            return None
        return cur.fetchall()
    finally:
        conn.close()


def write(sql, params, ok_msg):
    """Run a write; triggers raise SIGNAL errors, which we show as flash messages."""
    try:
        query(sql, params, write=True)
        flash(ok_msg, "ok")
    except mysql.connector.Error as e:
        flash(e.msg, "err")


@app.template_filter("inr")
def inr(n):
    return "₹{:,.0f}".format(n or 0)


def mark_overdue():
    query("UPDATE loan SET status='Overdue' "
          "WHERE status='Active' AND due_date < CURDATE() AND outstanding > 0", write=True)


@app.route("/")
def dashboard():
    mark_overdue()
    stats = query("""
        SELECT (SELECT COALESCE(SUM(balance),0) FROM v_member_summary WHERE status='Active') AS savings,
               (SELECT COUNT(*) FROM member WHERE status='Active') AS active,
               (SELECT COUNT(*) FROM member) AS total,
               (SELECT COALESCE(SUM(outstanding),0) FROM loan) AS outstanding,
               (SELECT COUNT(*) FROM loan WHERE status='Overdue') AS overdue""")[0]
    recent = query("""
        SELECT t.txn_date, m.name, t.txn_type, t.amount
          FROM savings_txn t
          JOIN savings_account a ON a.account_id = t.account_id
          JOIN member m ON m.member_id = a.member_id
         ORDER BY t.txn_id DESC LIMIT 5""")
    return render_template("dashboard.html", s=stats, recent=recent, page="dash")


@app.route("/members", methods=["GET", "POST"])
def members():
    if request.method == "POST":
        write("INSERT INTO member (name, phone) VALUES (%s, %s)",
              (request.form["name"].strip(), request.form["phone"]), "Member added.")
        return redirect(url_for("members"))
    rows = query("SELECT * FROM v_member_summary ORDER BY member_id")
    return render_template("members.html", rows=rows, page="mem")


@app.post("/members/<int:mid>/toggle")
def toggle_member(mid):
    write("UPDATE member SET status = IF(status='Active','Inactive','Active') WHERE member_id=%s",
          (mid,), "Member status updated.")
    return redirect(url_for("members"))


@app.route("/savings", methods=["GET", "POST"])
def savings():
    if request.method == "POST":
        f = request.form
        write("INSERT INTO savings_txn (account_id, txn_type, amount) "
              "SELECT account_id, %s, %s FROM savings_account WHERE member_id=%s",
              (f["type"], f["amount"], f["member_id"]), f"{f['type']} saved.")
        return redirect(url_for("savings"))
    members_ = query("SELECT member_id, name FROM member WHERE status='Active' ORDER BY name")
    txns = query("""
        SELECT t.txn_id, t.txn_date, m.name, t.txn_type, t.amount
          FROM savings_txn t
          JOIN savings_account a ON a.account_id = t.account_id
          JOIN member m ON m.member_id = a.member_id
         ORDER BY t.txn_id DESC""")
    return render_template("savings.html", members=members_, txns=txns, page="sav")


@app.route("/loans", methods=["GET", "POST"])
def loans():
    if request.method == "POST":
        f = request.form
        write("INSERT INTO loan (member_id, principal, interest_rate, due_date) "
              "VALUES (%s, %s, %s, DATE_ADD(CURDATE(), INTERVAL %s MONTH))",
              (f["member_id"], f["principal"], f["rate"], f["months"]), "Loan issued.")
        return redirect(url_for("loans"))
    mark_overdue()
    members_ = query("SELECT member_id, name FROM member WHERE status='Active' ORDER BY name")
    rows = query("SELECT * FROM v_loan_details ORDER BY loan_id DESC")
    return render_template("loans.html", members=members_, rows=rows, page="loan")


@app.post("/loans/<int:lid>/repay")
def repay(lid):
    write("INSERT INTO loan_repayment (loan_id, amount) VALUES (%s, %s)",
          (lid, request.form["amount"]), "Repayment recorded.")
    return redirect(url_for("loans"))


if __name__ == "__main__":
    app.run(debug=True)
