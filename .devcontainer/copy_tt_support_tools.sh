#! /bin/sh

if [ ! -L tt ]; then
    cp -R /ttsetup/tt-support-tools tt
    cd tt && git pull && cd ..
fi

# Repository status refresh: 2026-07-14
