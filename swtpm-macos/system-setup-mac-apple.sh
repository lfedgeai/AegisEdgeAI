# macos steps
brew install cmake openssl@3 autoconf automake libtool pkg-config socat
brew install cryptography

export LDFLAGS="-L$(brew --prefix openssl@3)/lib"
export CPPFLAGS="-I$(brew --prefix openssl@3)/include"
export PKG_CONFIG_PATH="$(brew --prefix openssl@3)/lib/pkgconfig"

git clone https://github.com/stefanberger/libtpms.git
cd libtpms
./autogen.sh --with-tpm2 --with-openssl --prefix=/usr/local
make
sudo make install
cd ..

git clone https://github.com/stefanberger/swtpm.git
cd swtpm
./autogen.sh --with-tpm2 --with-openssl --prefix=/usr/local
make
sudo make install
cd ..
