# qkqemunix

A Nix flake for streamlining the creation and management of QEMU VMs via `nixos-rebuild build-vm` and systemd.

Each VM is defined as a NixOS host in your config flake, runs as a dedicated unprivileged system user (`qkqemunix`), and is managed as a persistent systemd service with optional port forwarding and firewall rules.

---

## How It Works

`qkqemunix` exposes two outputs:

- **`packages.<system>.default`** — the `qkqemunix-run` wrapper script, which calls `nixos-rebuild build-vm` against a named NixOS host and launches the resulting QEMU VM.
- **`nixosModules.default`** — a NixOS module (`services.quick-qemu`) that wires up systemd services, firewall rules, libvirt, and the `qkqemunix` user for each declared VM.

---

## Prerequisites

- A NixOS host with flakes enabled
- A separate NixOS config flake that defines each VM as a named `nixosConfiguration`
- Each VM config must include a `virtualisation.vmVariant` block (see below)

---

## Usage

### 1. Add `qkqemunix` to your NixOS config flake

In your host's `flake.nix`, add this repo as an input and import the module:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    qkqemunix.url = "github:jimurrito/qkqemunix";
    qkqemunix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, qkqemunix, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        qkqemunix.nixosModules.default
        ./hosts/my-host/configuration.nix
      ];
    };
  };
}
```

### 2. Enable and configure VMs in your host configuration

In your host's `configuration.nix` (or any imported module):

```nix
services.quick-qemu = {
  enable = true;

  # Optional: set a shared config repo used by all VMs that opt in via useRootConfigRepo
  rootConfigRepo = "git+https://your.forgejo.instance/youruser/nixos-config";

  virtualmachines = {

    # VM using the shared root config repo
    my-vm = {
      enable = true;
      diskPath = "/var/qkqemunix/my-vm"; # must be accessible by the qkqemunix user
      useRootConfigRepo = true;
      portForwarding = [
        { vmPort = "22";  hostPort = "2222"; } # SSH
        { vmPort = "80";  hostPort = "8080"; } # HTTP
      ];
      firewall = {
        allowedTCPPorts = [ 2222 8080 ];
        allowedUDPPorts = [ ];
      };
    };

    # VM that runs its systemd service as root
    my-root-vm = {
      enable = true;
      diskPath = "/var/qkqemunix/my-root-vm";
      useRootConfigRepo = true;
      runAsRoot = true;
      portForwarding = [
        { vmPort = "22"; hostPort = "2224"; }
      ];
      firewall.allowedTCPPorts = [ 2224 ];
    };

    # VM with its own config repo
    my-other-vm = {
      enable = true;
      diskPath = "/var/qkqemunix/my-other-vm";
      useRootConfigRepo = false;
      configRepo = "git+https://your.forgejo.instance/youruser/other-nixos-config";
      portForwarding = [
        { vmPort = "22"; hostPort = "2223"; }
      ];
      firewall.allowedTCPPorts = [ 2223 ];
    };

  };
};
```

Each key under `virtualmachines` (e.g. `my-vm`) must correspond to a `nixosConfiguration` name in the target config repo — this is the name passed to `nixos-rebuild build-vm`.

### 3. Define the VM's NixOS configuration

In your VM config flake, create a `nixosConfiguration` with the same name as your VM key, and include a `vmVariant` block to configure QEMU resources:

```nix
# In your VM config flake's nixosConfigurations
nixosConfigurations.my-vm = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    ./hosts/my-vm/configuration.nix
  ];
};
```

In `./hosts/my-vm/configuration.nix` (or any module it imports):

```nix
virtualisation.vmVariant = {
  # This block is only applied when building with `build-vm`
  virtualisation = {
    memorySize = 4096; # MB — 4 GB
    cores      = 6;
    graphics   = false; # headless; console output via ttyS0
    diskSize   = 20480; # MB — 20 GB
  };
};
```

---

## Options Reference

All options live under `services.quick-qemu`.

| Option | Type | Default | Description |
|---|---|---|---|
| `enable` | bool | `false` | Enable the qkqemunix module |
| `rootConfigRepo` | string | — | Shared flake URL used by VMs with `useRootConfigRepo = true` |
| `virtualmachines.<name>.enable` | bool | `false` | Enable the systemd service for this VM |
| `virtualmachines.<name>.useRootConfigRepo` | bool | `false` | Use the top-level `rootConfigRepo` instead of a per-VM repo |
| `virtualmachines.<name>.runAsRoot` | bool | `false` | Run the VM's systemd service as `root` instead of the `qkqemunix` user |
| `virtualmachines.<name>.configRepo` | string | — | Per-VM flake URL (used when `useRootConfigRepo = false`) |
| `virtualmachines.<name>.diskPath` | string | `<name>` | Absolute path to the VM's working directory |
| `virtualmachines.<name>.portForwarding` | list of `{ vmPort, hostPort }` | `[]` | Port forwards from VM to host |
| `virtualmachines.<name>.portForwarding.[].vmPort` | string | `"22"` | Port inside the VM to forward |
| `virtualmachines.<name>.portForwarding.[].hostPort` | string | `"2222"` | Port on the host to bind |
| `virtualmachines.<name>.firewall.allowedTCPPorts` | list of int | `[]` | TCP ports to open on the host firewall |
| `virtualmachines.<name>.firewall.allowedUDPPorts` | list of int | `[]` | UDP ports to open on the host firewall |

---

## What the Module Configures

When `services.quick-qemu.enable = true`, the module will:

- Install `qkqemunix-run` and `virt-manager` into the system environment
- Enable `virtualisation.libvirtd`
- Enable nested virtualization (`kvm_intel nested=1`)
- Create a dedicated `qkqemunix` system user and group (home at `/var/qkqemunix`)
- For each enabled VM:
  - Create a systemd service `qkqemunix-<name>` that runs as the `qkqemunix` user (or `root` if `runAsRoot = true`)
  - Set `QEMU_NET_OPTS` with one `hostfwd` entry per item in `portForwarding`
  - Apply firewall rules from the VM's `firewall` block
  - Restart the service automatically on failure

---

## Connecting to a Running VM

Once a VM is started, SSH into it via the forwarded port on the host:

```bash
ssh -p 2222 user@localhost
```

Adjust the port to match the `hostPort` you configured.

---

## Notes

- The config repo URL (whether `rootConfigRepo` or a per-VM `configRepo`) must be accessible from the host at runtime — `qkqemunix-run` fetches it fresh on every start via `nixos-rebuild build-vm --refresh`.
- `graphics = false` is recommended for server VMs — console output is routed through `ttyS0`, which means VM console logs are captured by the systemd service and accessible via `journalctl -u qkqemunix-<name>`.
- The `diskPath` working directory must be writable by the `qkqemunix` user before the service starts.
- `diskPath` defaults to the VM name as a relative path if unset. Always provide an absolute path (e.g. `/var/qkqemunix/my-vm`) to avoid ambiguity about where the working directory resolves at runtime.