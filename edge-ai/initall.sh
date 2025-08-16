cd tpm

./swtpm.sh
sleep 1
./tpm-ek-ak-persist.sh
sleep 1
./tpm-app-persist.sh
sleep 1
./sign_app_message.sh
sleep 1
./generate_quote.sh

sleep 1
./verify_quote.sh
sleep 1
./verify_app_message_signature.sh
