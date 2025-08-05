python3 -m venv zerotrustvenv
source zerotrustvenv/bin/activate
pip install tpm2_pytss

python3 seal_unseal.py
