#!/bin/bash

cp files/.aerospace.toml $HOME/.aerospace.toml

rm -rf $HOME/.config/sketchybar
cp -r files/.config/sketchybar $HOME/.config

rm -rf $HOME/.config/iterm-config
cp -r files/.config/iterm-config $HOME/.config
