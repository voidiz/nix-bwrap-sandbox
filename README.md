# nix-bwrap-sandbox

## requirements

- [bubblewrap](https://github.com/containers/bubblewrap)
- nix with `nix-command` and `flakes` features
- `script(1)`

## usage

```bash
curl -fsSL https://raw.githubusercontent.com/voidiz/nix-bwrap-sandbox/master/install.sh | bash

bwrap-sandbox
```

## references

- [sandbox-bwrap-nix](https://github.com/grigio/sandbox-bwrap-nix)
