# vstrfryn29 - A strfry write policy plugin that adds support for NIP-29

![V Language](https://img.shields.io/badge/language-V-blue.svg)

### Quickstart - The easy way
- Start with a fresh Ubuntu VM
- Point a domain to your server. You'll need this domain name for the setup

```bash
curl -O https://raw.githubusercontent.com/Galaxoid-Labs/vstrfryn29/refs/heads/main/easy_setup.sh
chmod +x easy_setup.sh
./easy_setup.sh
```

This will ask you handful of questions. Relay name, domain name, etc. It will also ask for prvate key hex. This will be nostr key that you want to use for the relay.

Once the script finishes you should be able to simply run

```bash
strfry relay
```

If you have issues you may need to reload your ~/.bashrc

```bash
source ~/.bashrc
```

You'll likely also want to either use something like `screen` or setup a system service to run your relay. Its also worth notting you'll need to lock down your server at somepoint as well.

### Compile and build from source

More on this later. Its not difficult, but needs a little more attention. Stay tuned.

### TODO
- Setting roles does not work yet. Im working on this
- You can only set groups to open/close and public. Private groups are not supported yet as strfry doesnt support AUTH yet
