# Import Libraries
import os
import calendar
import pandas as pd
import numpy as np
import jinja2
import subprocess
import shutil
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import sys
from datetime import datetime
from sqlalchemy import create_engine, text

# --- Load the tex templat ---
def render_latex_template(data_dict, file_base_name):
    latex_jinja_env = jinja2.Environment(
        block_start_string = r'\BLOCK{', block_end_string = '}', # type: ignore
        variable_start_string = r'\VAR{', variable_end_string = '}', # type: ignore
        loader = jinja2.FileSystemLoader(os.path.abspath('.'))
    )

    # 1. Load the separate .tex file
    template = latex_jinja_env.get_template('templates/church_report_template.tex')
    rendered_tex = template.render(data_dict)

    # 2. Save the .tex file to output/latex/
    tex_path = os.path.join("output", "latex", f"{file_base_name}.tex")
    os.makedirs(os.path.dirname(tex_path), exist_ok=True)
    with open(tex_path, "w") as f:
        f.write(rendered_tex)

    # 3. Compile and Move PDF
    try:
        output_dir = os.path.abspath("logs")
        os.makedirs(output_dir, exist_ok=True)
        
        subprocess.run([
            'pdflatex', '-interaction=nonstopmode', 
            f'-output-directory={output_dir}', tex_path
        ], check=True) # stdout=subprocess.DEVNULL,

        source_pdf = os.path.join(output_dir, f"{file_base_name}.pdf")
        dest_pdf = os.path.join("output", "pdf", f"{file_base_name}.pdf")
        
        os.makedirs("output/pdf", exist_ok=True)
        shutil.move(source_pdf, dest_pdf)
        print(f"Success: {dest_pdf}")

    except Exception as e:
        print(f"Error during PDF generation: {e}")

# --- Compare Assessment Income performance ---
def save_assessment_income_bars(df, start_date, end_date):
    # 1. Determine how many months are in the period
    num_months = (end_date.year - start_date.year) * 12 + (end_date.month - start_date.month) + 1

    # 2. Calculate the start of the previous period
    prev_start = start_date - pd.DateOffset(months=num_months)
    prev_end = start_date - pd.Timedelta(days=1)
    
    # Function to get data subset for start and end dates
    def get_monthly_data(s, e, by_quarter=False):
        subset = df[(df['date'] >= s) & (df['date'] <= e) & (df['category'] == 'Assessment Received')\
                    & (df['transaction_type'] == 'Income')].copy()
        
        # 2. Safety Check:
        if subset.empty:
            return pd.Series(dtype='float64')

        if by_quarter:
            # 3. Vectorized approach: Faster and avoids the "Multiple Columns" error
            quarter_map = {1: 'Jan-Mar', 2: 'Apr-Jun', 3: 'Jul-Sep', 4: 'Oct-Dec'}
            
            # We create the label by combining two simple Series
            q_names = subset['date'].dt.quarter.map(quarter_map)
            years = subset['date'].dt.year.astype(str)
            
            subset['quarter_label'] = q_names + " " + years
            return subset.groupby('quarter_label', sort=False)['amount'].sum()
        else:
            # Standard monthly grouping
            return subset.groupby(subset['date'].dt.strftime('%b %Y'), sort=False)['amount'].sum()
    
    prev_vals = get_monthly_data(prev_start, prev_end, by_quarter=(num_months >= 6))
    curr_vals = get_monthly_data(start_date, end_date, by_quarter=(num_months >= 6))
    
    # 3. Calculate means for trend comparison
    prev_total = prev_vals.sum()
    curr_total = curr_vals.sum()
    prev_mean = prev_total / len(prev_vals) if len(prev_vals) > 0 else 0
    curr_mean = curr_total / len(curr_vals) if len(curr_vals) > 0 else 0
    
    if prev_mean == 0:
        summary_text = "Initial period of reporting."
    else:
        percent_change = ((curr_mean - prev_mean) / prev_mean) * 100

        if percent_change > 0:
            color = "green"
            direction = "improved"
        else:
            color = "red"
            direction = "decreased"
        
        summary_text = (
            rf"Assessment income has \textcolor{{{color}}}{{\textbf{{{direction}}} "
            rf"by \textbf{{{abs(percent_change):.1f}\%}}}} compared to the previous period."
        )

    # 4. Plotting for number of months > 6, we show quarterly bars, otherwise monthly
    all_labels = list(prev_vals.index) + list(curr_vals.index)
    all_values = list(prev_vals.values) + list(curr_vals.values)

    # Assigning colours
    colors = ['#1976D2'] * len(prev_vals) + ['#2E7D32'] * len(curr_vals)

    plt.figure(figsize=(10, 5))
    bars = plt.bar(all_labels, all_values, color=colors)
    
    # Add a legend manually since we have mixed colors
    from matplotlib.lines import Line2D
    legend_elements = [Line2D([0], [0], color='#1976D2', lw=4, label='Previous Period'),
                       Line2D([0], [0], color='#2E7D32', lw=4, label='Current Period')]
    plt.legend(handles=legend_elements)

    plt.title('Assessment Income Trend', fontsize=12, fontweight='bold')
    plt.ylabel('Amount (KSh)')
    plt.tight_layout()
    plt.savefig('logs/assessment_income_trend.png', dpi=300)
    plt.close()

    return summary_text

# --- Comparative offertory bars ---
def save_comparative_offertory_bars(df, start_date, end_date):
    # 1. Determine how many months are in the period
    num_months = (end_date.year - start_date.year) * 12 + (end_date.month - start_date.month) + 1

    # 2. Calculate the start of the previous period
    prev_start = start_date - pd.DateOffset(months=num_months)
    prev_end = start_date - pd.Timedelta(days=1)
    
    # Function to get data subset for start and end dates
    def get_monthly_data(s, e, by_quarter=False):
        subset = df[(df['date'] >= s) & (df['date'] <= e) & (df['category'].str.contains('Offertory', na=False))\
                    & (df['transaction_type'] == 'Income')]
        
        # 2. Safety Check:
        if subset.empty:
            return pd.Series(dtype='float64')

        if by_quarter:
            # 3. Vectorized approach: Faster and avoids the "Multiple Columns" error
            quarter_map = {1: 'Jan-Mar', 2: 'Apr-Jun', 3: 'Jul-Sep', 4: 'Oct-Dec'}
            
            # We create the label by combining two simple Series
            q_names = subset['date'].dt.quarter.map(quarter_map)
            years = subset['date'].dt.year.astype(str)
            
            subset['quarter_label'] = q_names + " " + years
            return subset.groupby('quarter_label', sort=False)['amount'].sum()
        else:
            # Standard monthly grouping
            return subset.groupby(subset['date'].dt.strftime('%b %Y'), sort=False)['amount'].sum()
    
    prev_vals = get_monthly_data(prev_start, prev_end, by_quarter=(num_months >= 6))
    curr_vals = get_monthly_data(start_date, end_date, by_quarter=(num_months >= 6))

    # 3. Calculate means for trend comparison
    prev_total = prev_vals.sum()
    curr_total = curr_vals.sum()
    prev_mean = prev_total / len(prev_vals) if len(prev_vals) > 0 else 0
    curr_mean = curr_total / len(curr_vals) if len(curr_vals) > 0 else 0

    if prev_mean == 0:
        summary_text = "Initial period of reporting."
    else:
        percent_change = ((curr_mean - prev_mean) / prev_mean) * 100

        if percent_change > 0:
            color = "green"
            direction = "improved"
        else:
            color = "red"
            direction = "decreased"
        
        summary_text = (
            rf"Offertory income has \textcolor{{{color}}}{{\textbf{{{direction}}} "
            rf"by \textbf{{{abs(percent_change):.1f}\%}}}} compared to the previous period."
        )

    # 4. Plotting for number of months > 6, we show quarterly bars, otherwise monthly
    all_labels = list(prev_vals.index) + list(curr_vals.index)
    all_values = list(prev_vals.values) + list(curr_vals.values)

    # Assigning colours
    colors = ['#1976D2'] * len(prev_vals) + ['#2E7D32'] * len(curr_vals)

    plt.figure(figsize=(10, 5))
    bars = plt.bar(all_labels, all_values, color=colors)
    
    # Add a legend manually since we have mixed colors
    from matplotlib.lines import Line2D
    legend_elements = [Line2D([0], [0], color='#1976D2', lw=4, label='Previous Period'),
                       Line2D([0], [0], color='#2E7D32', lw=4, label='Current Period')]
    plt.legend(handles=legend_elements)

    plt.title('Offertory Income Trend', fontsize=12, fontweight='bold')
    plt.ylabel('Amount (KSh)')
    plt.tight_layout()
    plt.savefig('logs/offertory_income_trend.png', dpi=300)
    plt.close()

    return summary_text

# Assessment income report
def save_assessment_church_target_bars(df, start_date, end_date, targets_df):
    # 1. Determine period length and grouping logic
    num_months = (end_date.year - start_date.year) * 12 + (end_date.month - start_date.month) + 1
    by_quarter = num_months >= 6

    # 2. Extract Assessment Income Targets
    targets_df['monthly_target'] = targets_df['monthly_target']/12
    income_targets = targets_df[targets_df['category'] == 'Assessment_Income']
    # Create a lookup for targets: {('Church 1', 2026): 45000}
    target_lookup = dict(zip(zip(income_targets['Entity'], income_targets['year']), income_targets['monthly_target']))

    # 3. Filter Actuals (Income + Assessment)
    actual_data = df[(df['date'] >= start_date) & (df['date'] <= end_date) & 
                     (df['category'] == 'Assessment Received') & (df['transaction_type'] == 'Income')].copy()
    
    # 4. Define Grouping Logic
    if by_quarter:
        quarter_map = {1: 'Jan-Mar', 2: 'Apr-Jun', 3: 'Jul-Sep', 4: 'Oct-Dec'}
        actual_data['label'] = actual_data['date'].apply(lambda d: f"{quarter_map[d.quarter]} {d.year}")
    else:
        actual_data['label'] = actual_data['date'].dt.strftime('%b %Y')

    # Pivot actuals: Rows = Time Labels, Columns = Churches
    actual_summary = actual_data.groupby(['label', 'description'], sort=False)['amount'].sum().unstack(fill_value=0)
    time_labels = actual_summary.index
    churches = actual_summary.columns
    
    # 5. Plotting Setup
    x = np.arange(len(time_labels))
    width = 0.35 if len(churches) == 1 else 0.8 / len(churches)
    fig, ax = plt.subplots(figsize=(12, 6))
    
    performance_msgs = []
    
    # 6. Iterate through each church to plot Target vs. Actual
    for i, church in enumerate([c for c in churches if c in income_targets['Entity'].values]):
        offset = (i - (len(churches)-1)/2) * width
        
        # Calculate Targets for the time labels (handles year transitions)
        # Note: If quarterly, the target is monthly_target * 3
        current_targets = []
        for label in time_labels:
            year = int(label.split()[-1])
            m_target = target_lookup.get((church, year), 0)
            current_targets.append(m_target * 3 if by_quarter else m_target)

        # Plot Target (Grey Ghost Bar)
        ax.bar(x + offset, current_targets, width, color='#E0E0E0', edgecolor='#BDBDBD', label=f'{church} Target')
        
        # Plot Actual (Green/Blue Bar)
        bar_color = '#2E7D32' if i % 2 == 0 else '#1976D2'
        ax.bar(x + offset, actual_summary[church], width * 0.8, color=bar_color, label=f'{church} Actual')

        # 7. Stewardship Signal Calculation
        total_actual = actual_summary[church].sum()
        total_target = sum(current_targets)
        perf_pct = (total_actual / total_target) * 100 if total_target > 0 else 0
        
        # Color Logic for Text
        t_color = "Gold" if perf_pct >= 100 else "green" if perf_pct > 80 else "red"
        performance_msgs.append(
            rf"{church} has reached \textcolor{{{t_color}}}{{\textbf{{{perf_pct:.1f}\%}}}}"
        )

    # 8. Finalize Visuals
    ax.set_title(f'Church Assessment Performance ({"Quarterly" if by_quarter else "Monthly"})', fontsize=14, fontweight='bold')
    ax.set_ylabel('Amount (KSh)')
    ax.set_xticks(x)
    ax.set_xticklabels(time_labels)
    ax.legend(loc='upper left', bbox_to_anchor=(1, 1))
    
    plt.tight_layout()
    plt.savefig('logs/assessment_income_church_trend.png', dpi=300)
    plt.close()

    return "Regarding assessment income, " + " and ".join(performance_msgs) + "."

# --- Assessment expenditure performance ---
def save_assessment_expenditure_bars(df, start_date, end_date, targets_df):
    # 1. Determine period length and grouping logic
    num_months = (end_date.year - start_date.year) * 12 + (end_date.month - start_date.month) + 1
    by_quarter = num_months >= 6

    # 2. Extract Assessment Expense Targets
    expense_targets = targets_df[targets_df['category'] == 'Assessment Paid']
    target_lookup = dict(zip(expense_targets['year'], expense_targets['monthly_target']))
    
    # 3. Generate the full time range
    date_range = pd.date_range(start_date, end_date, freq='MS')
    temp_df = pd.DataFrame({'date': date_range})

    if by_quarter:
        quarter_map = {1: 'Jan-Mar', 2: 'Apr-Jun', 3: 'Jul-Sep', 4: 'Oct-Dec'}
        temp_df['label'] = temp_df['date'].dt.quarter.map(quarter_map) + " " + temp_df['date'].dt.year.astype(str)
        time_labels = temp_df['label'].unique().tolist()
    else:
        time_labels = temp_df['date'].dt.strftime('%b %Y').tolist()

    # 4. Get Actuals and Align with Full Range
    actual_data = df[(df['date'] >= start_date) & (df['date'] <= end_date) & 
                     (df['category'] == 'Assessment Paid') & (df['transaction_type'] == 'Expense')].copy()

    if not actual_data.empty:
        if by_quarter:
            quarter_map = {1: 'Jan-Mar', 2: 'Apr-Jun', 3: 'Jul-Sep', 4: 'Oct-Dec'}
            actual_data['label'] = actual_data['date'].dt.quarter.map(quarter_map) + " " + actual_data['date'].dt.year.astype(str)
        else:
            actual_data['label'] = actual_data['date'].dt.strftime('%b %Y')
        
        actual_grouped = actual_data.groupby('label')['amount'].sum()
    else:
        actual_grouped = pd.Series(dtype=float)

    # Reindex actuals to the full time_labels (fills gaps with 0)
    actual_values = [actual_grouped.get(label, 0) for label in time_labels]

    # 5. Calculate Targets for EVERY period in the range
    current_targets = []
    for label in time_labels:
        year = int(label.split()[-1])
        m_target = target_lookup.get(year, 0)
        current_targets.append(m_target * 3 if by_quarter else m_target)

    # 6. Performance Calculation
    total_actual = sum(actual_values)
    total_target = sum(current_targets)
    perf_pct = (total_actual / total_target) * 100 if total_target > 0 else 0

    # 7. Plotting
    x = np.arange(len(time_labels))
    width = 0.6
    fig, ax = plt.subplots(figsize=(10, 5))
    
    # Target bars (Grey)
    ax.bar(x, current_targets, width, color='#E0E0E0', edgecolor='#9E9E9E', label='Synod Target')
    # Actual bars (Green - slightly thinner)
    ax.bar(x, actual_values, width * 0.7, color='#4CAF50', label='Actual Paid')

    ax.set_title(f'Assessment Expenditure Performance ({"Quarterly" if by_quarter else "Monthly"})', 
                 fontsize=12, fontweight='bold')
    ax.set_ylabel('Amount (KSh)')
    ax.set_xticks(x)
    ax.set_xticklabels(time_labels)
    ax.legend()
    
    plt.tight_layout()
    plt.savefig('logs/assessment_perf.png', dpi=300)
    plt.close()

    # 8. Stewardship Signal
    t_color = "Gold" if perf_pct >= 100 else "green" if perf_pct > 80 else "red"
    assessment_msg = (
        rf"In this period, the assessment expenditure performance has been at "
        rf"\textcolor{{{t_color}}}{{\textbf{{{perf_pct:.1f}\%}}}} of the Synod target."
    )

    return assessment_msg

# --- Check on minsterial payments ---
def save_minister_stipend_bars(df, start_date, end_date, targets_df):
    # 1. Get Targets for Stipends
    stipend_targets = targets_df[targets_df['category'].str.contains('Stipend', case=False)]

    full_timeline = pd.date_range(start_date, end_date, freq='MS').strftime('%b %Y').tolist()
    
    # 2. Get Actuals for Stipends
    stipend_data = df[(df['date'] >= start_date) & (df['date'] <= end_date) & (df['category'] == 'Stipend')]
    
    if stipend_data.empty:
        # If no stipends were paid at all, create an empty dataframe with the timeline
        actuals = pd.DataFrame(index=full_timeline)
    else:
        # Group by Month and Description
        actuals = stipend_data.groupby([stipend_data['date'].dt.strftime('%b %Y'), 'description'], sort=False)['amount'].sum().unstack(fill_value=0)

    # Group by Month and Description (which contains the Minister's name)
    actuals = actuals.reindex(full_timeline, fill_value=0)
    months = actuals.index
    ministers = actuals.columns # e.g., ['Min 1', 'Min 2']
    clean_targets = stipend_targets['Entity'].astype(str).str.strip().values
    valid_ministers = [m for m in ministers if str(m).strip() in clean_targets]
    
    # 3. Plotting Setup
    x = np.arange(len(months))
    width = 0.3 # Width of each minister's bar
    fig, ax = plt.subplots(figsize=(12, 6))
    
    performance_summaries = []
   
    # 4. Iterate through Ministers to plot and calculate performance
    for i, minister in enumerate([m for m in ministers if m in stipend_targets['Entity'].values]):
        # Calculate offset for grouped bars
        offset = (i - (len(ministers)-1)/2) * width
        
        # Get target for this minister (assuming goal stays same within the year)
        # We'll take the 2026 target as the baseline for the report
        m_target = stipend_targets[(stipend_targets['Entity'] == minister)]['monthly_target'].values[0]
        
        # Plot Target (Background Grey)
        ax.bar(x + offset, [m_target]*len(months), width, color='#F5F5F5', edgecolor='#D3D3D3', linestyle='--', label=f'{minister} Target')
        
        # Plot Actual (Foreground)
        color = '#DAA520' if i == 0 else '#4682B4' # Gold for Min 1, SteelBlue for Min 2
        ax.bar(x + offset, actuals[minister], width * 0.8, color=color, label=f'{minister} Actual')
        
        # Calculate Average Performance for the message
        avg_paid = actuals[minister].mean()
        perf_pct = (avg_paid / m_target) * 100
        
        # Determine Color for LaTeX Text
        if perf_pct >= 100: text_color = "Gold"
        elif perf_pct > 80: text_color = "green"
        else: text_color = "red"
        
        performance_summaries.append(
            rf"payment for {minister} is \textcolor{{{text_color}}}{{\textbf{{{perf_pct:.1f}\%}}}}"
        )

    # 5. Finalize Plot
    ax.set_title('Ministerial Stipend Fulfillment', fontsize=14, fontweight='bold')
    ax.set_ylabel('Amount (KSh)')
    ax.set_xticks(x)
    ax.set_xticklabels(months)
    ax.legend(loc='upper left', bbox_to_anchor=(1, 1))
    plt.tight_layout()
    plt.savefig('logs/stipend_perf.png', dpi=300)
    plt.close()

    # Join summaries into a single message
    final_msg = "On average, the " + ", ".join(performance_summaries) + "."
    return final_msg

# The final function
def generate_church_report(df, start_str, end_str, targets_df, db_engine):
    start_date = pd.to_datetime(start_str)
    end_date = pd.to_datetime(end_str) + pd.offsets.MonthEnd(0)
    
    period_label = f"{start_date.strftime('%d %b %Y')} -- {end_date.strftime('%d %b %Y')}"
    file_base_name = f"report_{start_date.strftime('%b%y')}_{end_date.strftime('%b%y')}".lower()
    
    # --- 2. NEW Opening Balances Logic ---
    # Fetch base opening balances from the database schema
    acc_df = pd.read_sql("SELECT name, opening_balance FROM accounts", db_engine)
    base_bank = acc_df[acc_df['name'].str.contains('bank', case=False)]['opening_balance'].sum()
    base_cash = acc_df[acc_df['name'].str.contains('cash|m-pesa', case=False)]['opening_balance'].sum()

    # Calculate movement strictly BEFORE the start_date
    prior_data = df[df['date'] < start_date]
    prior_bank_move = prior_data[prior_data['account'].str.contains('bank', case=False)]['correct_amount'].sum()
    prior_cash_move = prior_data[prior_data['account'].str.contains('cash|m-pesa', case=False)]['correct_amount'].sum()
    
    opening_bank = base_bank + prior_bank_move
    opening_cash = base_cash + prior_cash_move
    total_opening = opening_bank + opening_cash
    
    # --- 3. Filtering for Current Period ---
    # We no longer need to worry about excluding "Opening" types, because they don't exist in the ledger anymore!
    current_period_mask = (df['date'] >= start_date) & (df['date'] <= end_date)
    report_data = df.loc[current_period_mask].copy()
    
    # 4. STRATIFIED CLOSING BALANCES (Balance C/F)
    # Calculate how each account changed specifically in this window
    bank_change = report_data[report_data['account'] == 'Bank']['correct_amount'].sum()
    cash_change = report_data[report_data['account'].str.contains('cash|m-pesa', case=False)]['correct_amount'].sum()
    
    closing_bank = opening_bank + bank_change
    closing_cash = opening_cash + cash_change
    
    # 5. Build the T-Account Lists
    # Grouping categories for the table
    summary = report_data.groupby(['transaction_type', 'category'])['amount'].sum().reset_index()
    income_summary = summary[summary['transaction_type'] == 'Income']
    expense_summary = summary[summary['transaction_type'] == 'Expense']
    expense_summary = expense_summary.sort_values(by='amount', ascending=False)

    inc_list = [
        ("Balance B/F (Bank)", opening_bank),
        ("Balance B/F (Cash)", opening_cash)
    ]
    
    # NEW: Iteratively build the income list to inject the Assessment breakdown
    for _, row in income_summary.iterrows():
        cat = row['category']
        amt = row['amount']
        
        # 1. Add the main Income line (e.g., "Assessment", "Offertory")
        inc_list.append((cat, amt))
        
        # 2. If the category is Assessment, fetch and append the breakdown
        if cat == 'Assessment Received':
            # Filter the raw report_data for just the Assessment incomes
            assessment_breakdown = report_data[(report_data['transaction_type'] == 'Income') & 
                                               (report_data['category'] == 'Assessment Received')]
            
            # Group by 'description' (which contains the church names) and sort highest to lowest
            church_totals = assessment_breakdown.groupby('description')['amount'].sum().sort_values(ascending=False)
            
            for church, b_amt in church_totals.items():
                # Use LaTeX formatting to indent (\hspace) and italicize (\textit) the church name
                # This makes it visually distinct from the main categories
                formatted_church_name = rf"\hspace{{4mm}} \textit{{{church}}}"
                inc_list.append((formatted_church_name, b_amt))
    
    # Add the expenses to their list
    exp_list = expense_summary[['category', 'amount']].values.tolist()

    # NEW: Calculate and append the Expenditure Subtotal
    total_expenditure = expense_summary['amount'].sum()
    
    # We use \textbf{} so it stands out visually from regular expense categories
    exp_list.append((r"\textbf{Subtotal}", total_expenditure))
    
    # 6. Formatting for LaTeX Table Rows
    max_l = max(len(inc_list), len(exp_list))
    rows_string = ""
    for i in range(max_l):
        i_cat = inc_list[i][0] if i < len(inc_list) else ""
        i_val = f"{inc_list[i][1]:,.2f}" if i < len(inc_list) else ""
        e_cat = exp_list[i][0] if i < len(exp_list) else ""
        e_val = f"{exp_list[i][1]:,.2f}" if i < len(exp_list) else ""
        
        # Only print the row if there is at least one category present
        rows_string += f"{i_cat} & {i_val} & {e_cat} & {e_val} \\\\ \n"

    # 7. Grand Totals (Receipts must equal Payments + Closing Balances)
    total_receipts = total_opening + income_summary['amount'].sum()
    
    # 8. HAND OFF (Run the plotting functions)
    # Ensure these match the variable names in your latest Template
    assessment_income_general_text = save_assessment_income_bars(df, start_date, end_date)
    offertory_text = save_comparative_offertory_bars(df, start_date, end_date)
    assessment_income_church_target_text = save_assessment_church_target_bars(df, start_date, end_date, targets_df)
    assessment_expenditure_text = save_assessment_expenditure_bars(df, start_date, end_date, targets_df)
    minister_stipend_text = save_minister_stipend_bars(df, start_date, end_date, targets_df)
    
    # 9. PACKING (Final data for Jinja2)
    data_to_pass = {
        'period_label': period_label,
        'table_rows': rows_string,
        'closing_bank': f"{closing_bank:,.2f}",
        'closing_cash': f"{closing_cash:,.2f}",
        'total_sum': f"{total_receipts:,.2f}",
        'assessment_income_general_text': assessment_income_general_text,
        'offertory_summary_text': offertory_text,
        'assessment_income_church_target_text': assessment_income_church_target_text,
        'assessment_expenditure_text': assessment_expenditure_text,
        'minister_stipend_text': minister_stipend_text,
        'report_gen_date': datetime.now().strftime('%d/%m/%Y')
    }

    # Build the PDF and move it to output/pdf/
    render_latex_template(data_to_pass, file_base_name)

    # --- 10. LOG THE REPORT RUN IN THE DATABASE ---
    pdf_dest_path = f"output/pdf/{file_base_name}.pdf"
    
    with db_engine.begin() as conn:
        log_query = text("""
            INSERT INTO report_runs (period_start, period_end, pdf_path)
            VALUES (:start, :end, :path)
            ON CONFLICT (period_start, period_end) 
            DO UPDATE SET 
                generated_at = now(), 
                pdf_path = EXCLUDED.pdf_path;
        """)
        
        conn.execute(log_query, {
            "start": start_date.strftime('%Y-%m-%d'),
            "end": end_date.strftime('%Y-%m-%d'),
            "path": pdf_dest_path
        })
    print(f"✅ Logged report run in database for {period_label}")
if __name__ == "__main__":
    try:
        # 1. Connect to Postgres
        engine = create_engine("postgresql://cozmopol:gre8t_ser7er%21@localhost:5432/circuit_finance_dev")
        
        # 2. Query the General Ledger View and map it to your old DataFrame format
        ledger_query = """
            -- PART 1: Standard Incomes and Expenses
            SELECT 
                t.transaction_date AS date,
                CASE WHEN c.category_type = 'income' THEN 'Income' ELSE 'Expense' END AS transaction_type,
                c.name AS category,
                COALESCE(m.screen_name, ch.name, NULLIF(t.description, '')) AS description,
                a.name AS account,
                t.amount AS amount,
                CASE WHEN c.category_type = 'income' THEN t.amount ELSE -t.amount END AS correct_amount
            FROM transactions t
            JOIN accounts a ON a.id = t.account_id
            JOIN categories c ON c.id = t.category_id
            LEFT JOIN churches ch ON ch.id = t.church_id
            LEFT JOIN ministers m ON m.id = t.minister_id
            WHERE NOT t.is_voided

            UNION ALL

            -- PART 2: Transfer OUT (Negative impact on sender account)
            SELECT 
                tr.transfer_date AS date,
                'Transfer' AS transaction_type,
                'Transfer' AS category,
                NULLIF(tr.description, '') AS description,
                a_from.name AS account,
                tr.amount AS amount,
                -tr.amount AS correct_amount
            FROM transfers tr
            JOIN accounts a_from ON a_from.id = tr.from_account_id
            WHERE NOT tr.is_voided

            UNION ALL

            -- PART 3: Transfer IN (Positive impact on receiver account)
            SELECT 
                tr.transfer_date AS date,
                'Transfer' AS transaction_type,
                'Transfer' AS category,
                NULLIF(tr.description, '') AS description,
                a_to.name AS account,
                tr.amount AS amount,
                tr.amount AS correct_amount
            FROM transfers tr
            JOIN accounts a_to ON a_to.id = tr.to_account_id
            WHERE NOT tr.is_voided
        """
        ledger_df = pd.read_sql(ledger_query, engine)
        ledger_df['date'] = pd.to_datetime(ledger_df['date'])
        ledger_df['account'] = ledger_df['account'].str.title()

        # Rename category in the main ledger
        ledger_df['category'] = ledger_df['category'].replace('Assessment Paid', 'Synod Assessment')

        # 3. Query Targets (Joining both target tables to match your old format)
        targets_query = """
            SELECT 
                c.name AS "Entity", cat.year, cat.target_amount AS monthly_target, 'Assessment_Income' AS category
            FROM church_assessment_targets cat
            JOIN churches c ON c.id = cat.church_id
            UNION ALL
            SELECT 
                COALESCE(m.screen_name, 'Circuit') AS "Entity", ct.year, ct.target_amount AS monthly_target, cats.name AS category
            FROM circuit_targets ct
            LEFT JOIN ministers m ON m.id = ct.minister_id
            JOIN categories cats ON cats.id = ct.target_category_id
        """
        targets_df = pd.read_sql(targets_query, engine)

        # Rename category in the targets dataframe to match
        targets_df['category'] = targets_df['category'].replace('Assessment Paid', 'Synod Assessment')

        # 4. Handle Arguments
        if len(sys.argv) == 3 and sys.argv[1] != "":
            start_date = sys.argv[1]
            end_date = sys.argv[2]
        else:
            today = datetime.today()
            start_date = today.strftime('%Y-%m-01')
            end_date = start_date

        # Pass the engine to the main function so it can query opening balances
        generate_church_report(ledger_df, start_date, end_date, targets_df, engine)

    except Exception as e:
        print(f"An unexpected error occurred: {e}")