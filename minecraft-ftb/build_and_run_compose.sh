#!/bin/bash

set -e

./build.sh && docker compose up && docker compose down
