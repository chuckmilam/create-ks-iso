# Copilot instructions

- Use `./test-container-build.sh` for the container smoke tests.
- For a full boot ISO test, set `RHEL_SOURCE_ISO` to the provided installation ISO and use rootful Podman (`CONTAINER_ENGINE=podman CONTAINER_ENGINE_SUDO=true`) when the host runs rootless Podman. Rootless Podman cannot mount the source ISO in this environment.
- In WSL, set `TEST_OUTPUT_BASE=/mnt/d/ISOs` when running a full ISO test so the generated boot ISO is written to the Windows disk, not the expanding WSL virtual disk. The test script checks storage capacity and prints the exact output path. Keep credentials in a private Linux-side directory, not beside the ISO on shared Windows storage.
- Full ISO builds need at least three times the source ISO size free on the container-storage filesystem and the source ISO size plus 1 GiB free on the output filesystem.
- Removing temporary files frees space inside WSL, but may not shrink the host-side `ext4.vhdx`; reclaiming that space requires shutting down WSL and compacting the VHD.
