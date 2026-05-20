#!/bin/bash
# usage: ./run_sim.sh comparator
MODULE=$1
iverilog -o sim.out rtl/$MODULE.v tb/tb_$MODULE.v
vvp sim.out
gtkwave ${MODULE}.vcd