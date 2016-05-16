#!/bin/bash
# Entrypoint script for dockerized right_chimp

first_arg=$1
operation=$*

case "$first_arg" in
  chimpd)
    chimp_operation="$operation --bind-address=0.0.0.0"
    echo "Executing chimpd operation: '$chimp_operation'"
    $chimp_operation
    ;;
  chimp)
    chimp_operation="$operation"
    echo "Executing chimp operation: '$chimp_operation'"
    $chimp_operation
    ;;
  *)
    echo "Error: Requested operation '$operation' does not appear to be a 'chimp' or 'chimpd' operation"
    exit 1
    ;;
esac
