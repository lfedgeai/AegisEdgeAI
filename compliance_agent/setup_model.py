import os
import requests
from tqdm import tqdm

def download_file(url, folder_name, file_name):
    """
    Download a file from a URL to a specific folder.
    """
    if not os.path.exists(folder_name):
        os.makedirs(folder_name)

    file_path = os.path.join(folder_name, file_name)

    if os.path.exists(file_path):
        print(f"Model already exists at {file_path}. Skipping download.")
        return file_path

    try:
        response = requests.get(url, stream=True)
        response.raise_for_status()  # Raise an exception for bad status codes

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

        print(f"Model downloaded successfully to {file_path}")
        return file_path
    except requests.exceptions.RequestException as e:
        print(f"Error downloading the model: {e}")
        return None

if __name__ == "__main__":
    # URL of the GGUF model to download.
    # Using the more reliable Phi-3-mini model.
    model_url = "https://huggingface.co/TheBloke/Phi-3-mini-4k-instruct-GGUF/resolve/main/Phi-3-mini-4k-instruct-q4.gguf"

    # Directory to save the model inside the compliance_agent directory
    script_dir = os.path.dirname(os.path.abspath(__file__))
    models_dir = os.path.join(script_dir, 'models')

    # Filename for the downloaded model
    model_name = "Phi-3-mini-4k-instruct-q4.gguf"

    print("Starting model download...")
    download_file(model_url, models_dir, model_name)