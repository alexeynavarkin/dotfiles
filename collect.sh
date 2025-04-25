#!/bin/bash

cp $HOME/.aerospace.toml files/.aerospace.toml

rm -rf .config/sketchybar
cp -r $HOME/.config/sketchybar files/.config