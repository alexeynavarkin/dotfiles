#!/bin/bash

cp $HOME/.aerospace.toml .

rm -rf .config/sketchybar
cp -r $HOME/.config/sketchybar .config/sketchybar