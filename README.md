# HoloCraft

Build repo for HoloCraft. Pulls in the forks as submodules and builds the Quest APK.

    git clone --recursive https://github.com/HoloCraft-MR/HoloCraft.git
    cd HoloCraft
    scripts/build.sh

Steps can be run on their own, e.g. `scripts/build.sh pojlib unity`.
`scripts/build.sh install` pushes the APK to a connected Quest over adb.
Set `UNITY=` if the editor lives somewhere else. The APK ends up in `outputs/`.
