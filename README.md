# vstrfryn29 - A strfry write policy plugin that adds support for NIP-29

![V Language](https://img.shields.io/badge/language-V-blue.svg)

This module depends on [ismyhc.vnostr](https://github.com/ismyhc/vnostr) and [ismyhc.vsecp256k1](https://github.com/ismyhc/vsecp256k1)

#### You'll need to install the following libraries:
- automake
- libtool
- vlang

### Ubuntu
`sudo apt-get install automake libtool`

### Vlang install instructions 
```bash
git clone https://github.com/vlang/v
cd v
make
```

### Then you'll want to add v to your path
`export PATH="$HOME/Development/Tools/v:$PATH"` Or whever your path to v bin is.

### Now compile the vstrfryn29 into a binary
- In the directory of where you cloned this repo
- First you'll pull the dependencies
- Next you will compile the vsecp256k1 lib
- Build your vstrfryn29 binary

```bash
v install
v run ~/.vmodules/<user_name>/vsecp256k1/build.vsh
v .
```
