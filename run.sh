#!/bin/bash

updog -p 8123 &

anoman ledger &

wait -n

exit $?