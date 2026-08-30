import json
import os
import subprocess
import sys

import jinja2
from sqlalchemy import create_engine, text


def build_pdf(start_str, end_str):
    # 1. Read the JSON Context from Phase 1
    json_path = "/data/table/report_summary.json"
    if not os.path.exists(json_path):
        print(f"❌ Error: Could not find {json_path}. Did python-ledger run?")
        sys.exit(1)
        
    with open(json_path, "r") as f:
        data_dict = json.load(f)

    file_base_name = data_dict['file_base_name']

    # 2. Setup Jinja2 Environment
    latex_jinja_env = jinja2.Environment(
        block_start_string = r'\BLOCK{', block_end_string = '}',
        variable_start_string = r'\VAR{', variable_end_string = '}',
        loader = jinja2.FileSystemLoader(os.path.abspath('/app'))
    )
    
    template = latex_jinja_env.get_template('templates/church_report_template.tex')
    rendered_tex = template.render(data_dict)

    # 3. Save the rendered .tex file to the output directory
    os.makedirs("/data/output", exist_ok=True)
    tex_path = f"/data/output/{file_base_name}.tex"
    
    with open(tex_path, "w") as f:
        f.write(rendered_tex)

    # 4. Compile PDF using TEXINPUTS (No symlinks needed!)
    print(f"🔨 Compiling {file_base_name}.tex ...")
    
    # This tells pdflatex exactly where to find the images.
    # The trailing colon ':' is required! It tells LaTeX to also load its default system fonts/packages.
    custom_env = os.environ.copy()
    custom_env['TEXINPUTS'] = ".:/app/data/logo/:/data/plots/:"

    for attempt in range(2):
        result = subprocess.run([
            'pdflatex', '-interaction=nonstopmode', 
            '-output-directory=/data/output', tex_path
        ], capture_output=True, text=True, cwd='/app', env=custom_env)

        if result.returncode != 0:
            print(f"❌ Error during PDF generation (Attempt {attempt + 1})!")
            print("\n--- LATEX ERROR LOG ---")
            print("\n".join(result.stdout.splitlines()[-40:])) 
            print("-----------------------\n")
            sys.exit(1)

    print(f"✅ Success: PDF generated at /data/output/{file_base_name}.pdf")

    # 5. Log the report run to the Database
    DB_URI = "postgresql://cozmopol:gre8t_ser7er%21@localhost:5432/circuit_finance_dev"
    engine = create_engine(DB_URI)
    
    pdf_dest_path = f"output/pdf/{file_base_name}.pdf" 
    
    with engine.begin() as conn:
        log_query = text("""
            INSERT INTO report_runs (period_start, period_end, pdf_path)
            VALUES (:start, :end, :path)
            ON CONFLICT (period_start, period_end) 
            DO UPDATE SET 
                generated_at = now(), 
                pdf_path = EXCLUDED.pdf_path;
        """)
        conn.execute(log_query, {
            "start": start_str,
            "end": end_str,
            "path": pdf_dest_path
        })
    print(f"✅ Logged report run in database for {start_str} to {end_str}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python latex_builder.py <start_date> <end_date>")
        sys.exit(1)
        
    start_date = sys.argv[1]
    end_date = sys.argv[2]
    build_pdf(start_date, end_date)