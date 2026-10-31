<!-- bump: patch -->
PROVIDER_ROUTING.md states every unpinnable probe outcome
The permission-probe paragraph said a CLI reads `unpinnable (pin flags not enforced)` only when it wrote the probe file. `setup-providers.sh` also grades it so when the probe leaves its throwaway directory removed, replaced or unlistable, and the doc now says so.
