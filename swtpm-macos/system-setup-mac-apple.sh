brew install cmake openssl@3 autoconf automake libtool pkg-config socat cryptography

brew --prefix openssl@3
export LDFLAGS="-L$(brew --prefix openssl@3)/lib"
export CPPFLAGS="-I$(brew --prefix openssl@3)/include"
export PKG_CONFIG_PATH="$(brew --prefix openssl@3)/lib/pkgconfig"

git clone https://github.com/stefanberger/libtpms.git
cd libtpms

git apply libtpms.macos.apple.patch

./autogen.sh --with-tpm2 --with-openssl --prefix=/opt/homebrew/opt
make
sudo make install
cd ..

git clone https://github.com/stefanberger/swtpm.git
cd swtpm
./autogen.sh --with-tpm2 --with-openssl --prefix=/opt/homebrew/opt
make
sudo make install
cd ..


git clone https://github.com/tpm2-software/tpm2-tss.git
cd tpm2-tss
rm -f configure config.cache config.log

git apply tpm2-tss.macos.apple.patch


./bootstrap
./configure --prefix=/usr/local  --disable-tcti-cmd
make CFLAGS="-Wno-error=typedef-redefinition"
make
sudo make install

git clone https://github.com/tpm2-software/tpm2-tools.git
cd tpm2-tools

git apply tpm2-tools.macos.apple.patch

./bootstrap
./configure --with-openssl-prefix=$(brew --prefix openssl@3) --disable-hardening 

make 
sudo make install
 


