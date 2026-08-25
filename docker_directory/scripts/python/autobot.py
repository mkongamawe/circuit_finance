import os
import subprocess
from datetime import datetime, timedelta

import pandas as pd
from send_report import send_church_report
from sqlalchemy import create_engine

# --- DATABASE CONFIGURATION ---
DB_URI = "postgresql://cozmopol:gre8t_ser7er%21@localhost:5432/circuit_finance_dev"

def get_dispatch_plan(today):
    # [ ]:First monday of the month: Ledger is sent 
    # [ ]: First wednesday of the quarter, report is sent.
    """Determines what actions to take based on the exact day."""
    is_first_monday = today.weekday() == 0 and today.day <= 7
    is_quarter_month = today.month in [1, 4, 7, 10]
    is_report_wednesday = today.weekday() == 2 and today.day <= 9 and is_quarter_month

    if not (is_first_monday or is_report_wednesday):
        return None, []

    month = today.month
    year = today.year - 1 if month == 1 else today.year
    prev_month_start = f"{year}-{ (12 if month == 1 else month - 1) :02d}-01"
    
    # Calculate end of previous month
    end_date = (today.replace(day=1) - timedelta(days=1)).strftime('%Y-%m-%d')

    if is_first_monday:
        return "monthly_csv", [(prev_month_start, end_date)]

    reports = []
    if is_report_wednesday:
        # Quarterly
        q_start = {1: 10, 4: 1, 7: 4, 10: 7}[month]
        reports.append(('Quarterly', f"{year}-{q_start:02d}-01", end_date))

        # Half-Yearly
        if month in [1, 7]:
            h_start = 7 if month == 1 else 1
            reports.append(('Half-Yearly', f"{year}-{h_start:02d}-01", end_date))

        # Annual
        if month == 1:
            reports.append(('Annual', f"{year}-01-01", end_date))

    return "quarterly_pdf", reports

def generate_monthly_csv(start_date, end_date):
    """Pulls the ledger for the previous month and saves it as a CSV."""
    engine = create_engine(DB_URI)
    query = f"""
        SELECT entry_date, account_name, category_name, description, signed_amount 
        FROM general_ledger 
        WHERE entry_date >= '{start_date}' AND entry_date <= '{end_date}'
        AND NOT is_voided
        ORDER BY entry_date ASC;
    """
    df = pd.read_sql(query, engine)
    
    if df.empty:
        return None # Triggers the "Please Update" email
    
    csv_path = f"pipeline_data/output/csv/ledger_{start_date}_to_{end_date}.csv"
    os.makedirs(os.path.dirname(csv_path), exist_ok=True)
    df.to_csv(csv_path, index=False)
    return csv_path

if __name__ == "__main__":
    # [x]: Check here to manually change the script date. For testing purposes.
    # today = datetime(2026, 7, 1)
    today = datetime.now()
    action, tasks = get_dispatch_plan(today)
    
    COMMITTEE = "robert.mwagwabi@live.com,emmasididi@gmail.com"
    BISHOP_CC = "clement.mwagwabi@outlook.com"

    if action == "monthly_csv":
        print("📊 Triggered: Monthly CSV Review")
        start_val, end_val = tasks[0]
        csv_file = generate_monthly_csv(start_val, end_val)
        
        if csv_file:
            send_church_report(COMMITTEE.split(','), BISHOP_CC, [csv_file], is_csv=True)
        else:
            send_church_report(COMMITTEE.split(','), BISHOP_CC, [], is_csv=True, empty_data=True)

    elif action == "quarterly_pdf":
        print("📑 Triggered: Quarterly PDF Dispatch")
        generated_files = []
        for r_type, start_val, end_val in tasks:
            subprocess.run(["bash", "run_docker_pipeline.sh", start_val, end_val, "no"])
            latest = max([os.path.join("pipeline_data/output/pdf", f) for f in os.listdir("pipeline_data/output/pdf")], key=os.path.getctime)
            generated_files.append(latest)
            
        send_church_report(COMMITTEE.split(','), BISHOP_CC, generated_files, is_csv=False)
    else:
        print("⏳ Today is neither the 1st Monday nor the 1st Wednesday of a quarter. Skipping.")