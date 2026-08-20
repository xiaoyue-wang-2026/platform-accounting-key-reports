import subprocess
import sys

# List of required packages
required_packages = ["pandas", "redshift_connector","tqdm"]

# Install any missing packages
for package in required_packages:
    try:
        __import__(package)
    except ImportError:
        print(f"{package} not found. Installing...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", package])

import os
import pandas as pd
import redshift_connector
from tqdm import tqdm

class RedshiftUploader:
    def __init__(self):
        """
        Initialize the RedshiftUploader with hardcoded connection details.
        """
        self.host = 'dataeng-prod.cqyxh8rl6vlx.us-west-2.redshift.amazonaws.com'
        self.port = 5439
        self.database = 'data_warehouse_rc1'

    def connect(self, user, password):
        """
        Establish a connection to Redshift.
        """
        try:
            conn = redshift_connector.connect(
                host=self.host,
                port=self.port,
                database=self.database,
                user=user,
                password=password
            )
            print("Connected to Redshift successfully!")
            return conn
        except Exception as e:
            print(f"Connection failed: {e}")
            return None

    def find_file(self, filename):
        """
        Search for a file in the current working directory or its subdirectories.
        """
        for root, dirs, files in os.walk(os.getcwd()):
            if filename in files:
                return os.path.join(root, filename)
        return None

    def map_data_types(self, dtype):
        """
        Map pandas data types to Redshift-compatible SQL data types.
        """
        if pd.api.types.is_integer_dtype(dtype):
            return "BIGINT"
        elif pd.api.types.is_float_dtype(dtype):
            return "DOUBLE PRECISION"
        elif pd.api.types.is_bool_dtype(dtype):
            return "BOOLEAN"
        elif pd.api.types.is_datetime64_any_dtype(dtype):
            return "TIMESTAMP"
        else:
            return "VARCHAR(65535)"

    def format_value(self, value):
        """
        Format values for SQL insert, handling NULLs and escaping strings.
        """
        if pd.isnull(value):
            return "NULL"
        if isinstance(value, str):
            return f"'{value.replace("'", "''")}'"  # Escape single quotes
        return str(value)

    def load_csv_to_redshift(self, conn, csv_path, table_name, batch_size=10000):
        """
        Load a CSV file into a new table in Redshift with optimized settings.
        """
        try:
            # Read CSV into a DataFrame
            absolute_path = self.find_file(csv_path)
            if not absolute_path:
                raise FileNotFoundError(f"File '{csv_path}' not found.")
            
            df = pd.read_csv(absolute_path)
            print('Imported CSV successfully')

            # Generate CREATE TABLE statement dynamically
            create_table_sql = f"CREATE TABLE {table_name} ("
            for column, dtype in zip(df.columns, df.dtypes):
                redshift_type = self.map_data_types(dtype)
                create_table_sql += f'"{column}" {redshift_type}, '
            create_table_sql = create_table_sql.rstrip(", ") + ");"

            # Execute the CREATE TABLE statement
            cursor = conn.cursor()
            cursor.execute(f"DROP TABLE IF EXISTS {table_name};")  # Optional cleanup
            cursor.execute(create_table_sql)
            conn.commit()
            print(f"Table {table_name} created successfully.")

            # Prepare multi-row INSERT statements
            total_rows = len(df)
            columns = ", ".join([f'"{col}"' for col in df.columns])
            with tqdm(total=total_rows, desc="Inserting rows", unit="rows") as pbar:
                for start_idx in range(0, total_rows, batch_size):
                    chunk = df.iloc[start_idx:start_idx + batch_size]
                    values = ", ".join(
                        f"({', '.join(map(self.format_value, row))})"
                        for row in chunk.to_numpy()
                    )
                    insert_sql = f"INSERT INTO {table_name} ({columns}) VALUES {values}"
                    cursor.execute(insert_sql)
                    conn.commit()  # Commit after each batch
                    pbar.update(len(chunk))
            
            print(f"All data loaded into {table_name} successfully.")

        except Exception as e:
            print(f"An error occurred: {e}")

    def run(self):
        """
        Full workflow for loading a CSV into Redshift, including user prompts.
        """
        # Prompt for credentials
        connection = None
        while not connection:
            username = input("Enter your Redshift username: ")
            password = input("Enter your Redshift password: ")
            connection = self.connect(username, password)
            if not connection:
                print("Invalid username or password. Please try again.")

        # Prompt for CSV file
        while True:
            csv_file = input("Enter the name of the CSV file to upload: ")
            if self.find_file(csv_file):
                print(f"CSV file '{csv_file}' found.")
                break
            else:
                print(f"CSV file '{csv_file}' not found. Try again.")

        # Prompt for table name
        table_name = input("Enter the name of the table to create in Redshift: ")

        # Load the CSV into Redshift
        self.load_csv_to_redshift(connection, csv_file, table_name)

        # Close the connection
        connection.close()
        print("Done!")


# Main Script
if __name__ == "__main__":
    uploader = RedshiftUploader()
    uploader.run()
