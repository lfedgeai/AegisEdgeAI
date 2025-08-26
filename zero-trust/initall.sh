cd tpm
rm *.ctx *.pem *.pub *.priv *.bin *.sig *.out *.msg *.pcrs *.hash

./swtpm.sh
sleep 1
./tpm-ek-ak-persist.sh
sleep 1
./tpm-app-persist.sh
sleep 1
./generate_quote.sh

sleep 1
./verify_quote.sh

sleep 1
./sign_app_message.sh
sleep 1
./verify_app_message_signature.sh

cd ..

sleep 1
./cleanup_all_agents.sh --force
