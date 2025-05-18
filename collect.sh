#!/bin/bash

cp $HOME/.aerospace.toml files/.aerospace.toml

rm -rf files/.config/sketchybar
cp -r $HOME/.config/sketchybar files/.config

rm -rf files/.config/iterm-config
cp -r $HOME/.config/iterm-config files/.config