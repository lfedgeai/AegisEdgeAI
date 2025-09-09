brew install cmake openssl@3 autoconf automake libtool pkg-config socat cryptography

export LDFLAGS="-L$(brew --prefix openssl@3)/lib"
export CPPFLAGS="-I$(brew --prefix openssl@3)/include"
export PKG_CONFIG_PATH="$(brew --prefix openssl@3)/lib/pkgconfig"
export PREFIX="/opt/homebrew"
export EPREFIX=$PREFIX
export LIBFUSE_LIBS="-L/opt/homebrew/lib -ltpms"
export TPM2TOOLS_TCTI="libtss2-tcti-swtpm.dylib:host=127.0.0.1,port=2321"

git clone https://github.com/stefanberger/libtpms.git
cd libtpms

git apply libtpms.macos.apple.patch

./autogen.sh --with-tpm2 --with-openssl --prefix=$PREFIX --exec-prefix=$EPREFIX
make
sudo make install
cd ..

git clone https://github.com/stefanberger/swtpm.git
cd swtpm
./autogen.sh --with-tpm2 --with-openssl --prefix=$PREFIX --exec-prefix=$EPREFIX
make
sudo make install
cd ..


git clone https://github.com/tpm2-software/tpm2-tss.git
cd tpm2-tss
rm -f configure config.cache config.log

git apply tpm2-tss.macos.apple.patch


./bootstrap
./configure --with-tctidefaultmodule=libtss2-tcti-swtpm --with-tctidefaultconfig="swtpm:host=localhost,port=2321" --prefix=$PREFIX --exec-prefix=$EPREFIX
make CFLAGS="-Wno-error=typedef-redefinition"
make
sudo make install

git clone https://github.com/tpm2-software/tpm2-tools.git
cd tpm2-tools

git apply tpm2-tools.macos.apple.patch

./bootstrap
export TSS2_TCTILDR_LIBS="-L$PREFIX/lib -ltss2-tctildr -ltss2-tcti-swtpm -ltss2-tcti-mssim -ltss2-tcti-device -ltss2-esys"
./configure  --disable-hardening --prefix=$PREFIX --exec-prefix=$EPREFIX TSS2_TCTILDR_LIBS=$TSS2_TCTILDR_LIBS 

make 
sudo make install
 


