import os
import sys
import requests
from tqdm import tqdm

# This block allows the script to be run directly
if __name__ == "__main__" and __package__ is None:
    project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    sys.path.insert(0, project_root)

from compliance_agent.config import settings

def download_file(url, folder_name, file_name):
    """
    Download a file from a URL to a specific folder.
    """
    if not os.path.exists(folder_name):
        os.makedirs(folder_name)

    file_path = os.path.join(folder_name, file_name)

    if os.path.exists(file_path):
        print(f"Model '{file_name}' already exists at {file_path}. Skipping download.")
        return file_path

    try:
        print(f"\nDownloading model: {file_name}")
        response = requests.get(url, stream=True)
        response.raise_for_status()

        total_size = int(response.headers.get('content-length', 0))

        with open(file_path, 'wb') as f, tqdm(
            desc=file_name,
            total=total_size,
            unit='iB',
            unit_scale=True,
            unit_divisor=1024,
        ) as bar:
            for chunk in response.iter_content(chunk_size=8192):
                if chunk:
                    size = f.write(chunk)
                    bar.update(size)

        print(f"Model '{file_name}' downloaded successfully to {file_path}")
        return file_path
    except requests.exceptions.RequestException as e:
        print(f"Error downloading '{file_name}': {e}")
        return None

def main():
    """
    Main function to download the configured LLM model.
    """
    print("--- Starting Model Setup ---")

    script_dir = os.path.dirname(os.path.abspath(__file__))

    model_url = settings.llm_model_url
    model_path_config = settings.llm_model_path

    if not model_url or not model_path_config:
        print("Error: LLM model URL or path not configured in config.py.")
        sys.exit(1)

    model_path = os.path.join(script_dir, model_path_config)
    models_dir = os.path.dirname(model_path)
    file_name = os.path.basename(model_path)

    download_file(model_url, models_dir, file_name)

    print("\n--- Model Setup Complete ---")

if __name__ == "__main__":
    main()