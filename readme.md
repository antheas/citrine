```bash
# Create docker image with working rpm-ostree
./builder/prepare.sh
# Source `fd` alias that allows running commands with it
source ./builder/alias.sh

# Make image using just
fd just compose
```