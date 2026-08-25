import smtplib
import os
import sys
from datetime import datetime
from email.message import EmailMessage

def send_church_report(recipients, cc_email, attachment_paths, is_csv=False, empty_data=False):
    # --- CONFIGURATION ---
    SENDER_EMAIL = "cnyiro2000@gmail.com" 
    SENDER_PASSWORD = str(os.environ.get('MCK_EMAIL_PASS')).strip() 
    SMTP_SERVER = "smtp.gmail.com"
    SMTP_PORT = 465

    # Ensure attachment_paths is always a list, even if empty or a single string
    if isinstance(attachment_paths, str):
        attachment_paths = [attachment_paths]

    # 1. Create the Email
    msg = EmailMessage()
    report_month = datetime.now().strftime('%B %Y')
    
    msg['From'] = SENDER_EMAIL
    msg['To'] = ", ".join(recipients)
    msg['Cc'] = cc_email
    
    # 2. Handle the "No Data" Scenario
    if empty_data:
        msg['Subject'] = "ACTION REQUIRED: Missing Circuit Financial Data"
        body = """Good day,
        
The automated system attempted to generate the monthly ledger review, but no transactions or transfers were found for the previous month. 

Kindly update the financial database at your earliest convenience. If you require corrections or assistance, please reach out to the system administrator.

Best Regards,
Circuit Steward Office
Weslyan Methodist Church - Coast Region Conference"""
        msg.set_content(body)

    # 3. Handle the "Monthly CSV" Scenario
    elif is_csv:
        msg['Subject'] = f"Circuit Ledger Review: {report_month}"
        file_list_text = "\n".join([f"- {os.path.basename(p)}" for p in attachment_paths])
        body = f"""Good day,
        
Please find attached the raw CSV ledger export for the previous month. Kindly review these entries for accuracy before the quarterly PDF reports are generated.

Documents included in this dispatch:
{file_list_text}

Best Regards,
Circuit Steward Office
Weslyan Methodist Church - Coast Region Conference

---
CONFIDENTIALITY NOTICE: This email and any attachments are intended solely for the use of the Kilifi Circuit Finance Committee. If you are not the intended recipient, please notify the sender and delete this message immediately."""
        msg.set_content(body)

    # 4. Handle the "Quarterly PDF" Scenario
    else:
        msg['Subject'] = f"Kilifi Circuit Financial Review: {report_month}"
        file_list_text = "\n".join([f"- {os.path.basename(p)}" for p in attachment_paths])
        body = f"""Good day,

Please find the attached financial reports for the Kilifi Circuit. 

These automated documents provide a detailed breakdown of our current stewardship signals, including assessment performance and ministerial care (stipends).

Documents included in this dispatch:
{file_list_text}

This is a system-generated report for the Circuit Steward's Office. If you have any queries regarding the data visualizations, please reach out to the Treasury.

Best Regards,
Circuit Steward Office
Weslyan Methodist Church - Coast Region Conference

---
CONFIDENTIALITY NOTICE: This email and any attachments are intended solely for the use of the Kilifi Circuit Finance Committee. If you are not the intended recipient, please notify the sender and delete this message immediately."""
        msg.set_content(body)

    # 5. Attachments Loop
    for path in attachment_paths:
        try:
            # Determine if it's a PDF or CSV for the email client
            ext = path.split('.')[-1].lower()
            subtype = 'csv' if ext == 'csv' else 'pdf'
            
            with open(path, 'rb') as f:
                file_data = f.read()
                msg.add_attachment(
                    file_data, 
                    maintype='application', 
                    subtype=subtype, 
                    filename=os.path.basename(path)
                )
        except Exception as e:
            print(f"Warning: Could not attach {path}: {e}")

    # 6. Send the Mail
    try:
        with smtplib.SMTP_SSL(SMTP_SERVER, SMTP_PORT) as smtp:
            smtp.login(SENDER_EMAIL, SENDER_PASSWORD)
            smtp.send_message(msg)
            print(f"✅ Success: Dispatch sent to {len(recipients)} recipients.")
    except Exception as e:
        print(f"❌ Failed to send email: {e}")

if __name__ == "__main__":
    # To keep this compatible with your manual Bash script:
    recipients_list = sys.argv[1].split(',')
    cc_addr = sys.argv[2]
    pdf_path = sys.argv[3] 
    
    send_church_report(recipients_list, cc_addr, pdf_path)