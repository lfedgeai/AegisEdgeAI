cd tpm
rm *.ctx *.pem *.pub *.priv *.bin *.sig *.out *.msg *.pcrs *.hash

./swtpm.sh &
sleep 1

./tpm-ek-ak-persist.sh
sleep 1

cd ..

cd ./spire-tpm-plugin
rm *.ctx *.pem *.pub *.priv *.bin *.sig *.out *.msg *.pcrs *.hash
# New C replacement for tpm-app-persist.sh
#export APP_HANDLE=0x8101000B
#export AK_HANDLE=0x8101000A
./ma
./tpm-app-persist --force app.ctx appsk_pubkey.pem

