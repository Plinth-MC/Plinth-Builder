# Plinth

Build repo for Plinth. Pulls in the forks as submodules and builds the Quest APK.

    git clone --recursive https://github.com/Plinth-MC/Plinth.git
    cd Plinth
    scripts/build.sh

Steps can be run on their own, e.g. `scripts/build.sh pojlib unity`.
`scripts/build.sh install` pushes the APK to a connected Quest over adb.
Set `UNITY=` if the editor lives somewhere else. The APK ends up in `outputs/`.

`scripts/build.sh visor addon server` builds a Fabric dedicated server zip for
multiplayer (launcher, mods, start scripts) into `outputs/`.
