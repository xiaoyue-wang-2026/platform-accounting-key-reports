import subprocess
import sys
import os

# Clone the repository (if not already cloned)
repo_url = "https://github.com/Gusto/data-analyst.git"
repo_name = "data-analyst"
if not os.path.exists(repo_name):
    subprocess.run(["git", "clone", repo_url], check=True)

# Add the new folder to the Python path
uploader_path = os.path.join(repo_name, "Tools", "CSV_to_Redshift_Uploader")
sys.path.append(uploader_path)

# Import required packages
required_packages = ["pandas", "redshift_connector", "tqdm"]

# Install any missing packages
for package in required_packages:
    try:
        __import__(package)
    except ImportError:
        print(f"{package} not found. Installing...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", package])

import pandas as pd
import redshift_connector
from tqdm import tqdm

# Import and run the RedshiftUploader class
try:
    from csv_to_redshift import RedshiftUploader
except ModuleNotFoundError:
    print(f"Error: Ensure the file 'csv_to_redshift.py' exists in the path {uploader_path}.")
    sys.exit(1)

if __name__ == "__main__":
    uploader = RedshiftUploader()
    uploader.run()
