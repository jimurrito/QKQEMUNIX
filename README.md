# qkqemunix

![Language](https://img.shields.io/badge/language-Nix-5277C3?logo=nixos)
![License](https://img.shields.io/badge/license-GPL--3.0-blue)

A Nix flake for streamlining the creation and management of QEMU VMs via `nixos-rebuild build-vm` and systemd.

Each VM is defined as a NixOS host in your config flake, runs as a dedicated unprivileged system user (`qkqemunix`), and is managed as a persistent systemd service with optional port forwarding and firewall rules.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Usage](#usage)
  - [1. Add qkqemunix to your NixOS config flake](#1-add-qkqemunix-to-your-nixos-config-flake)
  - [2. Enable and configure VMs](#2-enable-and-configure-vms)
  - [3. Define the VM's NixOS configuration](#3-define-the-vms-nixos-configuration)
- [Real Example](#real-example)
- [Flake Reference](#flake-reference)
- [Options Reference](#options-reference)
- [What the Module Configures](#what-the-module-configures)
- [Connecting to a Running VM](#connecting-to-a-running-vm)
- [Notes](#notes)
- [License](#license)

---

## Prerequisites

- A NixOS host with flakes enabled
- A separate NixOS config flake that defines each VM as a named `nixosConfiguration`
- Each VM config must include a `virtualisation.vmVariant` block (see [step 3](#3-define-the-vms-nixos-configuration))

---

## Usage

### 1. Add `qkqemunix` to your NixOS config flake

In your host's `flake.nix`, add this repo as an input and import the NixOS module:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    qkqemunix = {
      url = "github:jimurrito/qkqemunix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, qkqemunix, ... }: {
    nixosConfigurations.<my-host> = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        qkqemunix.nixosModules.default
        ./hosts/<my-host>/configuration.nix
      ];
    };
  };
}
```

### 2. Enable and configure VMs

In your host's `configuration.nix`:

```nix
services.quick-qemu = {
  enable = true;

  # Shared config repo used by all VMs (can be overridden per VM)
  configRepo = "git+https://<your-git-host>/<user>/<repo>";

  # Root directory under which each VM's working directory is created.
  # Each VM gets: <diskPathRoot>/<vm-name>  (default: /libvirt)
  diskPathRoot = "/libvirt";

  virtualmachines = {

    # VM using all defaults (inherits configRepo and diskPathRoot)
    <vm-name> = {
      enable = true;
      portForwarding = {
        ssh  = { vm = 22; host = 2222; openOnHostFW = true; };
        http = { vm = 80; host = 8080; openOnHostFW = true; };
      };
    };

    # VM with per-VM overrides
    <other-vm-name> = {
      enable = true;
      overrides = {
        configRepo = "git+https://<your-git-host>/<user>/<other-repo>";
        diskPath   = "/data/vms/<other-vm-name>";
      };
      portForwarding = {
        ssh = { vm = 22; host = 2223; openOnHostFW = true; };
      };
    };

  };
};
```

Each key under `virtualmachines` (e.g. `<vm-name>`) must correspond to a `nixosConfiguration` name in the target config repo.

### 3. Define the VM's NixOS configuration

In your VM config flake, create a `nixosConfiguration` with the same name as the VM key:

```nix
nixosConfigurations.<vm-name> = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [ ./hosts/<vm-name>/configuration.nix ];
};
```

In the VM's `configuration.nix`, add a `vmVariant` block to configure QEMU resources:

```nix
virtualisation.vmVariant = {
  virtualisation = {
    memorySize = <memory-mb>;  # e.g. 4096 for 4 GB
    cores      = <core-count>;
    graphics   = false;        # headless; console via ttyS0
    diskSize   = <disk-mb>;    # e.g. 20480 for 20 GB
  };
};
```

---

## Real Example

A host running two VMs — one using the shared config repo, one with its own:

```nix
services.quick-qemu = {
  enable = true;
  configRepo = "git+https://forgejo.example.com/jimurrito/nixos-configs";

  virtualmachines = {

    my-vm = {
      enable = true;
      portForwarding = {
        ssh  = { vm = 22; host = 2222; openOnHostFW = true; };
        http = { vm = 80; host = 8080; openOnHostFW = true; };
      };
    };

    my-root-vm = {
      enable = true;
      runAsRoot = true;
      portForwarding = {
        ssh = { vm = 22; host = 2224; openOnHostFW = true; };
      };
    };

    my-other-vm = {
      enable = true;
      overrides = {
        configRepo = "git+https://forgejo.example.com/jimurrito/other-nixos-config";
      };
      portForwarding = {
        ssh = { vm = 22; host = 2223; openOnHostFW = true; };
      };
    };

  };
};
```

---

## Flake Reference

`qkqemunix` exposes one output:

- **`nixosModules.default`** — the NixOS module (`services.quick-qemu`) that wires up systemd services, firewall rules, libvirt, and the `qkqemunix` user for each declared VM. The `run.bash` launcher is bundled into the module and invoked by each VM's systemd service automatically.

To consume the module in your flake:

```nix
{
  inputs.qkqemunix.url = "github:jimurrito/qkqemunix";
  inputs.qkqemunix.inputs.nixpkgs.follows = "nixpkgs";

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

---

## Options Reference

All options live under `services.quick-qemu`.

| Option                                                      | Type                | Default     | Description                                                             |
| ----------------------------------------------------------- | ------------------- | ----------- | ----------------------------------------------------------------------- |
| `enable`                                                    | bool                | `false`     | Enable the qkqemunix module                                             |
| `configRepo`                                                | string              | —           | Flake URL to the repo containing each VM's `nixosConfiguration`         |
| `diskPathRoot`                                              | string              | `"/libvirt"`| Root directory under which each VM's working directory is created       |
| `virtualmachines.<name>.enable`                             | bool                | `false`     | Enable the systemd service for this VM                                  |
| `virtualmachines.<name>.runAsRoot`                          | bool                | `false`     | Run the VM's systemd service as `root` instead of the `qkqemunix` user  |
| `virtualmachines.<name>.overrides.<key>.configRepo`         | string              | `""`        | Override the shared `configRepo` for this VM                            |
| `virtualmachines.<name>.overrides.<key>.diskPath`           | string              | `""`        | Override the computed disk path (`diskPathRoot/<name>`) for this VM     |
| `virtualmachines.<name>.portForwarding`                     | attrs of submodules | `{}`        | Named port forwards from VM to host                                     |
| `virtualmachines.<name>.portForwarding.<name>.vm`           | int                 | `22`        | Port inside the VM to forward                                           |
| `virtualmachines.<name>.portForwarding.<name>.host`         | int                 | `2222`      | Port on the host to bind                                                |
| `virtualmachines.<name>.portForwarding.<name>.protocol`     | string              | `"tcp"`     | Protocol for the forward (`"tcp"` or `"udp"`)                           |
| `virtualmachines.<name>.portForwarding.<name>.openOnHostFW` | bool                | `false`     | Automatically open `host` port on the host firewall                     |

---

## What the Module Configures

When `services.quick-qemu.enable = true`, the module will:

- Enable `virtualisation.libvirtd`
- Enable nested virtualization (`kvm_intel nested=1`)
- Create a dedicated `qkqemunix` system user and group (home at `/libvirt`)
- For each enabled VM:
  - Create a oneshot service `qkqemunix-dpc-<name>` that ensures the VM's working directory exists
  - Create a systemd service `qkqemunix-<name>` (starts after the dpc service) running as `qkqemunix` (or `root` if `runAsRoot = true`)
  - Set `QEMU_NET_OPTS` with one `hostfwd` entry per item in `portForwarding`
  - Open host ports on the firewall for any `portForwarding` entry with `openOnHostFW = true`
  - Restart the service automatically on failure

---

## Connecting to a Running VM

SSH into a running VM via its forwarded host port:

```bash
ssh -p 2222 user@localhost
```

Adjust the port to match the `host` value you configured for the VM's SSH forward.

---

## Notes

- The config repo URL must be accessible from the host at runtime — `qkqemunix-run` fetches it fresh on every start via `nixos-rebuild build-vm --refresh`.
- `graphics = false` is recommended for server VMs — console output is routed through `ttyS0` and captured by systemd, accessible via `journalctl -u qkqemunix-<name>`.
- VM working directories are created automatically by `qkqemunix-dpc-<name>` before the VM starts. The `qkqemunix` user (or `root` if `runAsRoot = true`) must have write access to `diskPathRoot`.
- Always use an absolute path for any `overrides.diskPath` value.

---

## License

[GPL-3.0](LICENSE.md)
