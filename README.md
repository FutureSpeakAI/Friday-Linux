# Friday Linux

Friday Linux is a sealed, encrypted, bootable operating system that starts an
x86-64 PC directly into [Agent Friday](https://github.com/FutureSpeakAI/Agent-Friday).

It runs from a USB-attached SSD or from an internal disk. Every byte of user
state lives on an encrypted partition. Updates are atomic and roll back on their
own when a boot fails. At each boot the system re-profiles the hardware it finds,
so the same drive selects the best local model that machine can hold. It writes
nothing to any other disk in the host.

The system is built with [bootc](https://containers.github.io/bootc/) on a
Universal Blue and Fedora base, which means the operating system ships as a
container image and is updated the same way a container is.

## Status

Milestone M0 of five has passed. The image builds, boots under QEMU with OVMF,
forms its encrypted lockbox, seals `/usr` read-only, and fits inside the size
budget at roughly 1.7 GiB compressed against an 8 GiB ceiling. Continuous
integration reproduces all of that on every run.

None of that is the same as being ready to run on real hardware, and nobody has
done that yet. Every result above comes from a virtual machine with no GPU
attached. Bare-metal boot, Secure Boot enrollment, GPU inference, the interactive
first-boot wizard, the kiosk shell, and the automatic rollback test are all
scheduled for later milestones and none of them has been exercised. Images are
also pushed unsigned, because signing is a deliberate and documented deferral
rather than an oversight, so a pulled image should not be treated as verified.

Read this repository as an account of work in progress. It is published so the
design and the record can be examined, not because it is ready to install.

## What it is not

These are non-goals taken from the specification rather than a list assembled
after the fact.

* Not a general-purpose desktop distribution. The kiosk shell is the desktop.
* No macOS or Apple silicon support.
* No ARM or aarch64 images. Nothing here precludes them; they are not built or
  tested.
* No dual-boot installation alongside an existing operating system. Installation
  to an internal disk claims the whole disk.
* Does not bundle Ollama. The residency layer drives `llama-server` directly.
* Does not bundle PyTorch. Local voice runs on CTranslate2 and ONNX.
* Not a client hypervisor, and not an application marketplace.

## Known gaps

Three items are deferred rather than solved, and a reader deciding whether to
trust this should not have to find them by reading the commit history.

1. **The EFI system partition is not sized to specification.** The root and
   boot partitions are fixed at 16 GiB and 1 GiB exactly as specified.
   `bootc-image-builder` exposes no primitive for ESP size, so that partition
   ships at whatever default the tool produces and has not been confirmed
   against the 512 MiB figure the specification asks for. A measurement in a
   built image showed roughly 501 MiB, which is close, but close by coincidence
   is not the same as configured.
2. **`friday.service` runs in the generic `init_t` SELinux domain** rather than
   a domain of its own. A small custom policy module grants exactly one narrow
   permission and nothing wider, so this is not an open hole today. The problem
   is that it does not scale, because every future permission the application
   needs will require another hand-written addition to that module.
3. **The lockbox accepts a typed passphrase only.** The first-boot wizard reads
   a literal passphrase from an unattended configuration file. The option to
   generate a random passphrase and display it once, along with the opt-in
   recovery key, is not implemented and requires the interactive wizard that
   arrives in M1.

## Dependencies

Friday Linux consumes Agent Friday at a pinned release tag, currently `v5.9.0`,
recorded in `build/agent-friday.pin`. The two repositories are separate by
design. Friday Linux is the deployment target and Agent Friday is the
application, and the specification forbids forking the application into this
repository. Some upstream changes the specification assumes are not yet merged,
and the workarounds standing in for them are recorded in `docs/DECISIONS.md`.

## Building

A Windows host is not a build environment. Building requires WSL2 with Ubuntu
and rootful podman, or a Linux runner. Producing the disk image additionally
needs root for loop-device access, and booting it needs QEMU with KVM.

Build the container image:

```bash
podman build -t friday-linux:testing -f Containerfile .
```

`bootc-image-builder` reads from root's container storage, so move the image
across rather than rebuilding it under `sudo`:

```bash
podman save -o /tmp/friday-linux.tar localhost/friday-linux:testing
sudo podman load -i /tmp/friday-linux.tar
```

Produce the raw disk image. The disk customization file is mounted at the fixed
path `/config.toml`, as `bootc-image-builder` accepts no flag for it:

```bash
sudo podman run --rm \
  --privileged \
  --security-opt label=type:unconfined_t \
  -v "$(pwd)/output:/output" \
  -v "$(pwd)/build/disk.toml:/config.toml:ro" \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type raw \
  --rootfs xfs \
  localhost/friday-linux:testing
```

These are the commands continuous integration runs on every build, in this
order. `.github/workflows/build.yml` and `.github/workflows/boot-test.yml` are
the authoritative versions.

## Documentation

`docs/SPEC.md` is the full system specification and the place to start.
`docs/DECISIONS.md` holds the architecture decisions, the challenges raised
against them, and every deviation taken. `docs/MILESTONES.md` is the execution
record, and it keeps superseded and mistaken intermediate states rather than
tidying them away, so it reads as a log rather than a summary.
`docs/VERIFY.md` lists facts the build sandbox could not check, each with the
command that would check it.

These were written as working documents rather than published material. They
contain absolute paths from the author's development machine and refer to
sibling repositories that are not public.

## License

MIT. See [LICENSE](LICENSE).

Friday Linux is built on Fedora Linux. It is not affiliated with, endorsed by,
or a product of the Fedora Project or Red Hat.
